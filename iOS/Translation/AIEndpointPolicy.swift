import Foundation

/// Validates endpoints that receive user-provided AI credentials.
///
/// Credentials must never be sent over the network in clear text.  We allow
/// HTTPS endpoints, plus explicit loopback HTTP endpoints for local models
/// such as Ollama and LM Studio.  Redirects are limited to the same origin by
/// `SecureAIURLSessionDelegate` below, so an HTTPS API cannot silently forward
/// an Authorization header to another host or to HTTP.
enum AIEndpointPolicy {
    /// A configured provider is user-controlled, so never let its response
    /// body grow without bound in memory. Chat-completions JSON is ordinarily
    /// only a few KiB; four MiB leaves room for a useful long-page response
    /// while protecting the reader from a malicious or broken endpoint.
    static let maximumBYOKResponseBytes = 4 * 1_024 * 1_024

    static func chatCompletionsURL(baseURL rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              components.user == nil,
              components.password == nil,
              isAllowed(scheme: scheme, host: host)
        else {
            return nil
        }

        // A base URL never needs a query or fragment.  Dropping them prevents
        // accidental credential-bearing URLs and makes cache identities stable.
        components.query = nil
        components.fragment = nil

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.hasSuffix("chat/completions") {
            components.path = path.isEmpty ? "/chat/completions" : "/\(path)/chat/completions"
        } else {
            components.path = "/\(path)"
        }
        return components.url
    }

    /// A normalized, credential-free endpoint identity for result-cache keys.
    static func cacheIdentity(for rawValue: String) -> String {
        guard let url = chatCompletionsURL(baseURL: rawValue),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return "invalid"
        }
        components.query = nil
        components.fragment = nil
        // Hosts and schemes are case-insensitive, but URL paths are not.  Keep
        // the latter intact so two valid, case-distinct provider routes cannot
        // accidentally share a translation-cache entry.
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.url?.absoluteString ?? "invalid"
    }

    static func isAllowedURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host else { return false }
        return isAllowed(scheme: scheme, host: host)
    }

    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    static func permitsRedirect(from origin: URL, to destination: URL) -> Bool {
        isAllowedURL(destination) && sameOrigin(origin, destination)
    }

    private static func isAllowed(scheme: String, host: String) -> Bool {
        if scheme == "https" { return true }
        guard scheme == "http" else { return false }

        let normalizedHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return normalizedHost == "localhost"
            || normalizedHost == "127.0.0.1"
            || normalizedHost == "::1"
    }

    private static func effectivePort(_ url: URL) -> Int {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "https" ? 443 : 80
    }
}

/// An ephemeral session delegate that refuses cross-origin or insecure
/// redirects before URLSession can repeat the authenticated request.
final class SecureAIURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    private let origin: URL

    init(origin: URL) {
        self.origin = origin
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let destination = request.url,
              AIEndpointPolicy.permitsRedirect(from: origin, to: destination)
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

/// A bounded, redirect-safe alternative to `URLSession.data(for:)` for BYOK
/// requests.  `data(for:)` buffers until EOF with no maximum, which gives a
/// hostile configured endpoint an easy way to force an unbounded allocation.
/// This delegate accepts only successful responses, rejects oversized declared
/// bodies early, and cancels once streamed data crosses the fixed limit.
final class BoundedAIResponseDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private enum ResponseError: LocalizedError {
        case invalidResponse
        case unsuccessfulStatus(Int)
        case responseTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The AI endpoint returned an invalid response."
            case let .unsuccessfulStatus(status):
                return "The AI endpoint returned HTTP \(status)."
            case .responseTooLarge:
                return "The AI endpoint response exceeded the 4 MiB limit."
            }
        }
    }

    private let origin: URL
    private let maximumResponseBytes: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private weak var task: URLSessionDataTask?
    private var response: URLResponse?
    private var receivedData = Data()
    private var wasCancelled = false

    init(origin: URL, maximumResponseBytes: Int) {
        self.origin = origin
        self.maximumResponseBytes = maximumResponseBytes
    }

    func data(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        let dataTask = session.dataTask(with: request)
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard self.start(task: dataTask, continuation: continuation) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                dataTask.resume()
            }
        }, onCancel: {
            self.cancel()
        })
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let destination = request.url,
              AIEndpointPolicy.permitsRedirect(from: origin, to: destination)
        else {
            completionHandler(nil)
            fail(ResponseError.invalidResponse)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            fail(ResponseError.invalidResponse)
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel)
            fail(ResponseError.unsuccessfulStatus(http.statusCode))
            return
        }
        if response.expectedContentLength > Int64(maximumResponseBytes) {
            completionHandler(.cancel)
            fail(ResponseError.responseTooLarge)
            return
        }

        lock.lock()
        let canReceive = continuation != nil && !wasCancelled
        if canReceive { self.response = response }
        lock.unlock()
        completionHandler(canReceive ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let canAppend = continuation != nil && !wasCancelled
        let remaining = maximumResponseBytes - receivedData.count
        if canAppend && data.count <= remaining {
            receivedData.append(data)
            lock.unlock()
            return
        }
        lock.unlock()

        if canAppend {
            dataTask.cancel()
            fail(ResponseError.responseTooLarge)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
            return
        }

        lock.lock()
        let response = self.response
        let data = receivedData
        lock.unlock()
        guard let response else {
            finish(.failure(ResponseError.invalidResponse))
            return
        }
        finish(.success((data, response)))
    }

    private func start(
        task: URLSessionDataTask,
        continuation: CheckedContinuation<(Data, URLResponse), Error>
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !wasCancelled, self.continuation == nil else { return false }
        self.task = task
        self.continuation = continuation
        return true
    }

    private func cancel() {
        lock.lock()
        wasCancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
        finish(.failure(CancellationError()))
    }

    private func fail(_ error: Error) {
        lock.lock()
        let task = task
        lock.unlock()
        task?.cancel()
        finish(.failure(error))
    }

    private func finish(_ result: Result<(Data, URLResponse), Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        task = nil
        lock.unlock()
        guard let continuation else { return }
        switch result {
        case let .success(value):
            continuation.resume(returning: value)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
