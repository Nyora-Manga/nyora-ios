//
//  NyoraLocalEngine.swift
//  Aidoku
//
//  On-device parser engine bridge. Wraps the GraalVM native-image static library
//  (libnyoraengine) that runs the real kotatsu-parsers JVM engine AOT-compiled to
//  native ARM64 — so the app parses ~960 sources locally, with NO cloud helper.
//
//  The engine speaks the SAME JSON protocol as the cloud helper's REST endpoints, so
//  NyoraHelper only swaps its transport (see NyoraHelper.get) — decoders/mappers in
//  NyoraSource.swift are untouched.
//
//  Requires libnyoraengine.a + NyoraNativeBridge.h linked into the target (see
//  native-engine/NATIVE_IOS.md). When the library is absent this whole type is compiled
//  out via `canImport`, so the app still builds against the cloud helper.
//

import Foundation
import AidokuRunner   // SourceError

// The C ABI comes from the NyoraEngine.xcframework (module `NyoraNativeBridge`). When linked
// via a bridging header instead, the symbols are global and NYORA_LOCAL_ENGINE gates compilation.
#if canImport(NyoraNativeBridge)
import NyoraNativeBridge
#endif

#if canImport(NyoraNativeBridge) || NYORA_LOCAL_ENGINE

/// Serial-safe façade over the native engine. One process-wide isolate; each request
/// attaches its own isolate thread so multiple sources parse concurrently.
final class NyoraLocalEngine: @unchecked Sendable {
    static let shared = NyoraLocalEngine()

    /// Master switch. ON by default whenever the native engine is linked (fully local); a user
    /// can still turn it off in Settings to fall back to the cloud helper.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "Nyora.localEngine.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "Nyora.localEngine.enabled") }
    }

    private var isolate: OpaquePointer?
    private let bootQueue = DispatchQueue(label: "xyz.nyora.engine.boot")
    private let workQueue = DispatchQueue(label: "xyz.nyora.engine.work", attributes: .concurrent)
    private var didBoot = false

    private init() {}

    // MARK: Boot

    /// Creates the isolate once and registers the URLSession transport. Idempotent.
    private func ensureBooted() throws {
        try bootQueue.sync {
            guard !didBoot else { return }
            var isolatePtr: OpaquePointer?
            var threadPtr: OpaquePointer?
            guard graal_create_isolate(nil, &isolatePtr, &threadPtr) == 0, isolatePtr != nil, threadPtr != nil else {
                throw SourceError.message("Local engine failed to start.")
            }
            self.isolate = isolatePtr
            // Install the transport on the boot thread's isolate thread, then detach it.
            nyora_register_http(threadPtr, nyoraHttpTransport)
            graal_detach_thread(threadPtr)
            self.didBoot = true
            NSLog("[NyoraLocalEngine] on-device GraalVM engine booted (isolate created)")
        }
    }

    // MARK: Request

    /// Runs a helper-style request in-process and returns the raw JSON, identical in shape
    /// to the cloud helper's response for `path`.
    func request(path: String, items: [URLQueryItem]) async throws -> Data {
        try ensureBooted()
        guard let isolate else { throw SourceError.message("Local engine not initialized.") }

        var params: [String: String] = [:]
        for item in items where item.value != nil { params[item.name] = item.value }
        let paramsJson = String(
            data: (try? JSONSerialization.data(withJSONObject: params)) ?? Data("{}".utf8),
            encoding: .utf8
        ) ?? "{}"

        return try await withCheckedThrowingContinuation { continuation in
            workQueue.async {
                var thread: OpaquePointer?
                guard graal_attach_thread(isolate, &thread) == 0, let thread else {
                    continuation.resume(throwing: SourceError.message("Local engine thread attach failed."))
                    return
                }
                defer { graal_detach_thread(thread) }

                let result: UnsafeMutablePointer<CChar>? = path.withCString { p in
                    paramsJson.withCString { q in
                        nyora_request(thread, UnsafeMutablePointer(mutating: p), UnsafeMutablePointer(mutating: q))
                    }
                }
                guard let result else {
                    continuation.resume(throwing: SourceError.message("Local engine returned nothing."))
                    return
                }
                let data = Data(bytes: result, count: strlen(result))
                nyora_free(thread, result)
                continuation.resume(returning: data)
            }
        }
    }
}

// MARK: - URLSession transport (called from the engine's worker threads)

/// Shared session for engine-originated fetches. URLSession owns cookies (HTTPCookieStorage)
/// since the engine runs with OkHttp's CookieJar disabled.
private let nyoraEngineSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    config.httpCookieStorage = .shared
    config.httpShouldSetCookies = true
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: config)
}()

private struct EngineHTTPRequest: Decodable {
    let method: String
    let url: String
    let headers: [String: String]
    let bodyB64: String?
}

private struct EngineHTTPResponse: Encodable {
    let status: Int
    let headers: [String: String]
    let bodyB64: String
    let contentType: String?
    let finalUrl: String?
}

/// C callback the engine invokes for every outbound request. MUST be a top-level
/// `@convention(c)` function (no captured state). Performs the request synchronously and
/// returns a malloc'd JSON C string the engine frees.
private func nyoraHttpTransport(
    _ thread: OpaquePointer?,
    _ requestJson: UnsafeMutablePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let respJson: String
    if let requestJson,
       let req = try? JSONDecoder().decode(EngineHTTPRequest.self, from: Data(bytes: requestJson, count: strlen(requestJson))),
       let url = URL(string: req.url) {
        respJson = performEngineRequest(req, url: url)
    } else {
        respJson = #"{"status":0,"headers":{},"bodyB64":"","finalUrl":null}"#
    }
    return strdup(respJson) // malloc'd; engine frees via UnmanagedMemory.free
}

private struct RawResponse {
    var status = 0
    var headers: [String: String] = [:]
    var body = Data()
    var finalUrl: String?
}

private func performEngineRequest(_ req: EngineHTTPRequest, url: URL) -> String {
    var result = doRequest(req, url: url)

    // On a Cloudflare challenge, clear it on-device (hidden WKWebView, engine UA) and retry once.
    #if canImport(UIKit)
    if isCloudflareChallenge(result), solveCloudflareBlocking(urlString: req.url) {
        result = doRequest(req, url: url)
    }
    #endif

    let resp = EngineHTTPResponse(
        status: result.status,
        headers: result.headers,
        bodyB64: result.body.base64EncodedString(),
        contentType: result.headers["Content-Type"] ?? result.headers["content-type"],
        finalUrl: result.finalUrl
    )
    if let data = try? JSONEncoder().encode(resp), let s = String(data: data, encoding: .utf8) {
        return s
    }
    return #"{"status":0,"headers":{},"bodyB64":""}"#
}

private func doRequest(_ req: EngineHTTPRequest, url: URL) -> RawResponse {
    var request = URLRequest(url: url)
    request.httpMethod = req.method
    for (k, v) in req.headers { request.setValue(v, forHTTPHeaderField: k) }
    if let b64 = req.bodyB64, let body = Data(base64Encoded: b64) { request.httpBody = body }

    // If this host has a Cloudflare clearance, send the SAME (Safari) User-Agent the WebView earned
    // it with — cf_clearance is bound to that UA, so replaying with the engine's default Chrome UA
    // gets the cookie rejected and CF re-challenges. Only cleared hosts are overridden, so open CDNs
    // (e.g. MangaDex) keep their default UA.
    #if canImport(UIKit)
    if let host = url.host, NyoraCloudflareSolver.hasClearance(for: host) {
        request.setValue(NyoraCloudflareSolver.userAgent, forHTTPHeaderField: "User-Agent")
    }
    #endif

    let semaphore = DispatchSemaphore(value: 0)
    var out = RawResponse()
    let task = nyoraEngineSession.dataTask(with: request) { data, response, _ in
        if let http = response as? HTTPURLResponse {
            out.status = http.statusCode
            out.finalUrl = http.url?.absoluteString
            for (k, v) in http.allHeaderFields {
                if let ks = k as? String, let vs = v as? String { out.headers[ks] = vs }
            }
        }
        if let data { out.body = data }
        semaphore.signal()
    }
    task.resume()
    semaphore.wait()
    return out
}

/// Recognise a Cloudflare interstitial (so we only spin up the WebView solver when warranted).
private func isCloudflareChallenge(_ r: RawResponse) -> Bool {
    guard r.status == 403 || r.status == 503 else { return false }
    let h = r.headers.reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value }
    if (h["cf-mitigated"] ?? "").lowercased() == "challenge" { return true }
    guard (h["server"] ?? "").lowercased().contains("cloudflare") else { return false }
    let text = String(data: r.body.prefix(6000), encoding: .utf8)?.lowercased() ?? ""
    return text.contains("just a moment")
        || text.contains("challenge-platform")
        || text.contains("cf-chl")
        || text.contains("_cf_chl")
        || text.contains("cf_chl_opt")
        || text.contains("enable javascript and cookies to continue")
}

#if canImport(UIKit)
/// Run the MainActor WebView solver from the engine's background transport thread, blocking it
/// until the challenge clears (or a timeout). Safe: this is a background thread, never the main one.
/// The timeout must exceed the solver's interactive window (180s) since an interactive Cloudflare
/// challenge waits on the USER to complete + close it.
private func solveCloudflareBlocking(urlString: String) -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    let box = NSMutableArray() // carries the Bool result across the boundary
    Task { @MainActor in
        let ok = await NyoraCloudflareSolver.shared.solve(urlString: urlString)
        box.add(ok)
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 200)
    return (box.firstObject as? Bool) ?? false
}
#endif

#endif // canImport(NyoraNativeBridge) || NYORA_LOCAL_ENGINE
