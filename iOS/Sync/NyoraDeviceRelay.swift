//
//  NyoraDeviceRelay.swift
//  Aidoku (iOS) — Nyora fork
//
//  Device-as-egress for Cloudflare Turnstile. cf_clearance is IP-locked, so a
//  cookie solved on this phone is useless to the server-side helper. Instead this
//  device PERFORMS the fetch itself — in a real WKWebView that clears the
//  challenge from the phone's own IP — and streams the bytes back to the helper
//  to parse.
//
//  Transport = long-poll over the helper's plain HTTP server (no WebSocket dep):
//    GET  /device/relay/poll    → next fetch task (or {} when idle)
//    POST /device/relay/result  → {id,status,contentType,bodyBase64}
//
//  Runs only while the app is foregrounded (iOS suspends background networking) —
//  which is exactly when the user is browsing and needs it.
//

import Foundation
import WebKit

@MainActor
final class NyoraDeviceRelay: NSObject {
    static let shared = NyoraDeviceRelay()

    private let base = URL(string: "https://api.hasanraza.tech")!
    private var running = false
    private var loopTask: Task<Void, Never>?

    private var webView: WKWebView?
    private var pendingFetch: CheckedContinuation<Data, Never>?

    private lazy var pollSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 35 // longer than the server's 25s long-poll
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private struct RelayTask: Decodable {
        let id: String
        let url: String
        let method: String?
        let headers: [String: String]?
        let bodyB64: String?
    }

    // MARK: - Lifecycle

    func start() {
        guard !running else { return }
        running = true
        loopTask = Task { [weak self] in await self?.loop() }
    }

    func stop() {
        running = false
        loopTask?.cancel()
        loopTask = nil
    }

    private func loop() async {
        while running && !Task.isCancelled {
            do {
                if let task = try await poll() {
                    await handle(task)
                }
                // on empty poll, immediately re-poll
            } catch {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    // MARK: - Long-poll

    private func poll() async throws -> RelayTask? {
        let (data, response) = try await pollSession.data(from: base.appendingPathComponent("device/relay/poll"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        // idle poll returns "{}" (no id)
        return try? JSONDecoder().decode(RelayTask.self, from: data)
    }

    private func handle(_ task: RelayTask) async {
        let result = await fetchInWebView(task)
        var payload: [String: Any] = ["id": task.id, "status": result.status, "contentType": result.contentType]
        payload["bodyB64"] = result.body.base64EncodedString()
        var request = URLRequest(url: base.appendingPathComponent("device/relay/result"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - WebView fetch (solves CF from this device's IP, then fetches)

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let controller = WKUserContentController()
        controller.add(self, name: "relayResult")
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        view.navigationDelegate = self
        view.alpha = 0.02
        view.isUserInteractionEnabled = false
        // Must live in a window for Cloudflare's challenge JS to run reliably.
        attachToWindow(view)
        webView = view
        return view
    }

    private func attachToWindow(_ view: WKWebView) {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first
        window?.addSubview(view)
    }

    private struct FetchResult { let status: Int; let contentType: String; let body: Data }

    private func fetchInWebView(_ task: RelayTask) async -> FetchResult {
        guard
            let url = URL(string: task.url),
            let origin = originURL(for: url)
        else { return FetchResult(status: 0, contentType: "", body: Data()) }

        let webView = ensureWebView()

        // 1) Navigate to the origin so Cloudflare's challenge runs + clears for
        //    this domain (managed/Turnstile challenges auto-solve in a real WebView).
        await load(webView, origin)
        try? await Task.sleep(nanoseconds: 4_000_000_000) // grace for the challenge to settle

        // 2) Same-origin fetch of the target URL with the cleared session, result
        //    posted back via the message handler.
        let script = buildFetchScript(task: task)
        let data: Data = await withCheckedContinuation { continuation in
            self.pendingFetch = continuation
            webView.evaluateJavaScript(script) { [weak self] _, error in
                if error != nil {
                    // JS failed to even start — resume with empty so we don't hang.
                    if let cont = self?.pendingFetch { self?.pendingFetch = nil; cont.resume(returning: Data()) }
                }
            }
        }

        // parse the JSON the JS posted
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (obj["ok"] as? Bool) == true,
            let status = obj["status"] as? Int
        else {
            return FetchResult(status: 0, contentType: "", body: Data())
        }
        let contentType = obj["contentType"] as? String ?? ""
        let body = (obj["bodyBase64"] as? String).flatMap { Data(base64Encoded: $0) } ?? Data()
        return FetchResult(status: status, contentType: contentType, body: body)
    }

    private func load(_ webView: WKWebView, _ url: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.pendingLoad = continuation
            webView.load(URLRequest(url: url))
        }
    }

    private var pendingLoad: CheckedContinuation<Void, Never>?

    private func originURL(for url: URL) -> URL? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host
        if let port = url.port { comps.port = port }
        comps.path = "/"
        return comps.url
    }

    private func buildFetchScript(task: RelayTask) -> String {
        let method = (task.method ?? "GET").uppercased()
        let urlJSON = jsonString(task.url)
        let methodJSON = jsonString(method)
        let headersJSON = (try? String(
            data: JSONSerialization.data(withJSONObject: task.headers ?? [:]),
            encoding: .utf8
        )) ?? "{}"
        let bodyString = task.bodyB64.flatMap { Data(base64Encoded: $0) }.flatMap { String(data: $0, encoding: .utf8) }
        let bodyJS = bodyString.map { jsonString($0) } ?? "null"

        return """
        (function() {
          var url = \(urlJSON);
          var method = \(methodJSON);
          var headers = \(headersJSON);
          var body = \(bodyJS);
          var opts = { method: method, credentials: 'include' };
          if (headers && Object.keys(headers).length) opts.headers = headers;
          if (body !== null && method !== 'GET' && method !== 'HEAD') opts.body = body;
          fetch(url, opts).then(function(r) {
            return r.arrayBuffer().then(function(buf) {
              var bytes = new Uint8Array(buf), bin = '', chunk = 0x8000;
              for (var i = 0; i < bytes.length; i += chunk) {
                bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
              }
              window.webkit.messageHandlers.relayResult.postMessage(JSON.stringify({
                ok: true, status: r.status,
                contentType: (r.headers.get('content-type') || ''),
                bodyBase64: btoa(bin)
              }));
            });
          }).catch(function(e) {
            window.webkit.messageHandlers.relayResult.postMessage(JSON.stringify({ ok: false, error: String(e) }));
          });
        })();
        """
    }

    private func jsonString(_ value: String) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: [value]), encoding: .utf8))
            .map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }
}

extension NyoraDeviceRelay: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let cont = pendingLoad { pendingLoad = nil; cont.resume() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let cont = pendingLoad { pendingLoad = nil; cont.resume() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let cont = pendingLoad { pendingLoad = nil; cont.resume() }
    }
}

extension NyoraDeviceRelay: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "relayResult" else { return }
        let data = (message.body as? String).flatMap { $0.data(using: .utf8) } ?? Data()
        if let cont = pendingFetch { pendingFetch = nil; cont.resume(returning: data) }
    }
}
