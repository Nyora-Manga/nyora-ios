//
//  NyoraCloudflareSolver.swift
//  Aidoku (iOS) — Nyora fork
//
//  On-device Cloudflare "Just a moment" solver, mirroring nyora-mac's MacCloudflareSolver.
//
//  Two-phase, android/mac-style:
//    1. Passive — a hidden WKWebView loads the challenged origin. A simple JS challenge
//       ("Just a moment…") clears itself within a few seconds with no user action; we detect
//       that (real page title + cf_clearance) and finish silently.
//    2. Interactive — if the page is a Turnstile / "managed challenge" that REQUIRES a human,
//       we surface the SAME WebView in a real, full-screen sheet with an instruction banner.
//       The user completes the verification and taps Done (or closes the sheet) — we capture the
//       FINAL cf_clearance on close (a managed challenge can set an interim cookie mid-verify;
//       auto-closing on the first cookie captured a half-baked clearance CF then rejected).
//
//  The captured cf_clearance is copied into `HTTPCookieStorage.shared` so the engine's retried
//  URLSession request (and image loads) pass. cf_clearance is bound to (IP, User-Agent): the
//  WebView here uses the SAME Chrome/115 UA the engine sends over URLSession, so the clearance
//  it earns is valid for those requests (unlike mac, which uses a Safari UA because it relays
//  fetches through WebKit itself).
//

#if canImport(UIKit)
import Foundation
import WebKit
import UIKit

@MainActor
final class NyoraCloudflareSolver: NSObject {
    static let shared = NyoraCloudflareSolver()

    /// A REAL Safari UA — critically, one consistent with WKWebView's actual engine (WebKit).
    /// Exactly as nyora-mac's MacCloudflareSolver does it: a spoofed Chrome UA makes Cloudflare
    /// expect `sec-ch-ua` client hints that WebKit NEVER sends, so the challenge scores the browser
    /// as a bot and RE-CHALLENGES endlessly (the "infinite reload"). A genuine Safari identity has no
    /// such inconsistency and clears normally. cf_clearance is bound to this UA, so the engine's
    /// URLSession replay (see NyoraLocalEngine.doRequest) sends the SAME UA for a cleared host.
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"

    private var webView: WKWebView?
    private var inFlight: [String: Task<Bool, Never>] = [:]
    private var presenting = false

    /// How long to wait for a hands-free clear before showing the sheet to the user.
    private let passiveTimeout: TimeInterval = 6
    /// How long to give the user to complete an interactive challenge.
    private let interactiveTimeout: TimeInterval = 180

    /// Whether a valid cf_clearance cookie already exists for `host` (so the engine can send the
    /// solving UA on image requests). Read-only; never triggers a solve.
    nonisolated static func hasClearance(for host: String) -> Bool {
        HTTPCookieStorage.shared.cookies?.contains { c in
            c.name == "cf_clearance" && domainMatches(cookieDomain: c.domain, host: host)
        } ?? false
    }

    /// Clear a Cloudflare challenge for `urlString`. Returns true once a cf_clearance cookie is in
    /// the shared cookie store. Concurrent solves for the same host are COALESCED (browse fires
    /// several requests at once, each 403 asks to solve). Called only after a request actually hit
    /// a CF challenge, so it always attempts a fresh solve (any existing clearance was rejected).
    func solve(urlString: String) async -> Bool {
        guard let url = URL(string: urlString), let host = url.host else { return false }
        if let existing = inFlight[host] { return await existing.value }
        let task = Task { await self.performSolve(host: host) }
        inFlight[host] = task
        let result = await task.value
        inFlight[host] = nil
        return result
    }

    private func performSolve(host: String) async -> Bool {
        guard let url = URL(string: "https://\(host)/") else { return false }
        let wv = makeWebView()
        var request = URLRequest(url: URL(string: "https://\(host)/") ?? url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        wv.load(request)

        // Phase 1 — passive: detect INSTANTLY whether this needs a human. A CF challenge page is
        // titled "Just a moment…"; a simple JS challenge instead navigates to the real page (title
        // changes, cf_clearance appears) and we finish without ever showing a sheet.
        if await waitForAutoSolveOrChallenge(host: host, webView: wv) {
            await copyClearanceToShared(host: host, from: wv)
            teardown()
            return true
        }

        // Phase 2 — interactive: a human must act. Show the WebView and WAIT for the USER to close
        // the sheet, then capture the FINAL cookies.
        await presentInteractiveAndWait(host: host, webView: wv)
        await copyClearanceToShared(host: host, from: wv)
        teardown()
        return Self.hasClearance(for: host)
    }

    /// Returns true if a simple JS challenge auto-cleared (no sheet needed); false the moment the
    /// CF challenge page ("Just a moment…"/Turnstile) is up so the caller shows the sheet, or on
    /// timeout (show the sheet to be safe).
    private func waitForAutoSolveOrChallenge(host: String, webView wv: WKWebView) async -> Bool {
        let deadline = Date().addingTimeInterval(passiveTimeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            let title = (wv.title ?? "").lowercased()
            if title.contains("just a moment") || title.contains("attention required") ||
                title.contains("verifying") || title.contains("verify you are human") {
                return false
            }
            let cookies = await wv.configuration.websiteDataStore.httpCookieStore.allCookies()
            if cookies.contains(where: {
                $0.name == "cf_clearance" && Self.domainMatches(cookieDomain: $0.domain, host: host)
            }) {
                return true
            }
        }
        return false
    }

    /// Presents the live WebView full-screen with an instruction banner and suspends until the user
    /// closes it (Done / swipe) or the safety timeout elapses.
    private func presentInteractiveAndWait(host: String, webView wv: WKWebView) async {
        guard !presenting, let top = Self.topViewController() else { return }
        presenting = true
        defer { presenting = false }

        // Bring the (previously hidden) WebView to life for interaction.
        wv.alpha = 1
        wv.isUserInteractionEnabled = true

        let vc = CFChallengeViewController(webView: wv, host: host)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            let finish = {
                if !resumed { resumed = true; cont.resume() }
            }
            vc.onClose = finish
            top.present(nav, animated: true)
            // Safety timeout: force-dismiss if the user walks away.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(self.interactiveTimeout * 1_000_000_000))
                if vc.presentingViewController != nil { vc.dismiss(animated: true) }
                finish()
            }
        }
    }

    /// Copies the site's persistent clearance cookies from the WebView into the shared store the
    /// engine/image loaders use. Drops transient `cf_chl*` challenge-in-progress cookies — echoing
    /// them back makes Cloudflare restart the challenge.
    private func copyClearanceToShared(host: String, from wv: WKWebView) async {
        let cookies = await wv.configuration.websiteDataStore.httpCookieStore.allCookies()
        for cookie in cookies
        where Self.domainMatches(cookieDomain: cookie.domain, host: host) && !cookie.name.hasPrefix("cf_chl") {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func makeWebView() -> WKWebView {
        teardown()
        let config = WKWebViewConfiguration()
        // Ephemeral store so every solve runs the challenge fresh (a persistent store kept handing
        // back a long-expired cf_clearance instead of re-solving).
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.customUserAgent = Self.userAgent
        // Cloudflare's Turnstile JS only runs in a webview that's in the window hierarchy, so during
        // the passive phase attach it invisibly to the key window.
        if let window = Self.keyWindow() {
            webView.alpha = 0.01
            webView.isUserInteractionEnabled = false
            window.addSubview(webView)
        }
        self.webView = webView
        return webView
    }

    private func teardown() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first
    }

    private static func topViewController() -> UIViewController? {
        guard var top = keyWindow()?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    nonisolated static func domainMatches(cookieDomain: String, host: String) -> Bool {
        let d = cookieDomain.hasPrefix(".") ? String(cookieDomain.dropFirst()) : cookieDomain
        return host == d || host.hasSuffix("." + d) || d.hasSuffix("." + host) || host.hasSuffix(d)
    }
}

/// Full-screen host for the interactive Cloudflare challenge. The WebView is reparented in; the
/// user completes the verification and taps Done (or closes) — `onClose` fires exactly once, on
/// either the button or an interactive dismiss.
@MainActor
private final class CFChallengeViewController: UIViewController {
    private let webView: WKWebView
    private let host: String
    var onClose: (() -> Void)?
    private var closed = false

    init(webView: WKWebView, host: String) {
        self.webView = webView
        self.host = host
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Verify you're human"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(doneTapped)
        )

        let banner = UILabel()
        banner.text = "Complete the verification for \(host), then tap Done to continue."
        banner.font = .systemFont(ofSize: 13)
        banner.textColor = .secondaryLabel
        banner.numberOfLines = 2
        banner.textAlignment = .center
        banner.translatesAutoresizingMaskIntoConstraints = false

        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(banner)
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            webView.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: 8),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func doneTapped() {
        dismiss(animated: true) { [weak self] in self?.close() }
    }

    // Covers interactive (swipe-to-dismiss) and the safety-timeout force dismiss.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        close()
    }

    private func close() {
        guard !closed else { return }
        closed = true
        onClose?()
    }
}
#endif
