//
//  MihonSourceBridge.swift
//  Nyora
//

import Foundation

/// Bidirectional bridge between Mihon extension sources and Nyora sources.
///
/// Identical data to the JVM helper's `mihon-source-bridge.json`, embedded as a
/// Swift literal because iOS has no synchronized resource group. Both are emitted
/// by `nyora-shared/tools/build-source-bridge.py` in one run, so they cannot drift.
///
/// Nyora ids here are the parser enum form used everywhere else (`parser:MANGADEX`).
/// On iOS a local source records its parser id in `UserDefaults` under
/// `"<sourceId>.parserSource"`, which is what `localSourceId(for:)` joins on.
enum MihonSourceBridge {

    struct Candidate: Decodable {
        let id: String
        let lang: String
        let name: String

        var sourceId: Int64 { Int64(id) ?? 0 }
    }

    private struct File: Decodable {
        var version: Int = 0
        var toNyora: [String: String] = [:]
        var toMihon: [String: [Candidate]] = [:]
    }

    private static let file: File = {
        guard let data = MihonSourceBridgeData.json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(File.self, from: data)
        else { return File() }
        return decoded
    }()

    /// Mihon source id -> Nyora parser id.
    static let map: [Int64: String] = {
        var out: [Int64: String] = [:]
        for (key, value) in file.toNyora {
            if let id = Int64(key) { out[id] = value }
        }
        return out
    }()

    /// Nyora parser id -> the Mihon extensions scraping the same site.
    static var reverse: [String: [Candidate]] { file.toMihon }

    static var size: Int { map.count }

    static func nyoraSourceId(for mihonSourceId: Int64) -> String? { map[mihonSourceId] }

    /// Best Mihon equivalent for a Nyora source, preferring a language match so a
    /// French source does not export as the English extension. Candidates are
    /// pre-sorted (en, then all/multi, then id), so the first is a sane default.
    static func mihonSource(for nyoraSourceId: String, lang: String = "") -> Candidate? {
        guard let candidates = reverse[nyoraSourceId], !candidates.isEmpty else { return nil }
        let wanted = lang.lowercased()
        if !wanted.isEmpty {
            if let exact = candidates.first(where: { $0.lang.lowercased() == wanted }) { return exact }
            if wanted != "all", wanted != "multi",
               let any = candidates.first(where: { $0.lang.lowercased() == "all" }) { return any }
        }
        return candidates.first
    }

    // MARK: - Joining the bridge to this device's installed sources

    /// Nyora parser id for a locally installed source, e.g. `parser:MANGADEX`.
    /// Falls back to the raw source id for sources with no parser mapping.
    static func parserId(forLocalSource sourceId: String) -> String {
        if let parser = UserDefaults.standard.string(forKey: "\(sourceId).parserSource"), !parser.isEmpty {
            return parser.hasPrefix("parser:") ? parser : "parser:\(parser)"
        }
        return sourceId
    }

    /// Reverse of `parserId(forLocalSource:)` across the installed source list.
    static func localSourceId(forParser parserId: String, installed: [String]) -> String? {
        installed.first { Self.parserId(forLocalSource: $0) == parserId }
    }
}
