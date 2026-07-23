//
//  NyoraDeviceRelay.swift
//  Aidoku (iOS) — Nyora fork
//
//  Formerly the "device-as-egress" relay: the phone performed Cloudflare-gated fetches in a
//  WKWebView and streamed the bytes back to the CLOUD parser helper (api.nyora.xyz) to parse.
//
//  Parsing is now fully on-device (the cloud helper was removed), so there is nothing to relay
//  for — this is a no-op that preserves the call sites. If a source needs a Cloudflare solve,
//  that should be reintroduced against the local engine's transport, not a cloud endpoint.
//

import Foundation

@MainActor
final class NyoraDeviceRelay {
    static let shared = NyoraDeviceRelay()
    private init() {}

    func start() {}
    func stop() {}
}
