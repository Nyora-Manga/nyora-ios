//
//  MihonSourceIds.swift
//  Nyora
//

import Foundation

/// Namespacing rules shared with the JVM implementation.
///
/// Two namespaces meet during a Mihon import and mixing them corrupts data on the
/// first sync round trip:
///
///  - a **source ref name** is what the shared model carries — `MIHON_<id>`.
///  - a **source id** is what rows store and what the sync wire format
///    normalises — colon-namespaced (`parser:X`, `mihon:X`).
///
/// The sync layer re-adds a `parser:` prefix to any id without a colon, so
/// storing `MIHON_123` as a source id comes back as `parser:MIHON_123`.
enum MihonSourceIds {
    static let sourceIdPrefix = "mihon:"
    static let sourceRefPrefix = "MIHON_"

    /// Row source id for an unresolved Mihon entry — colon-namespaced, sync-safe.
    static func sourceId(_ mihonSourceId: Int64) -> String { "\(sourceIdPrefix)\(mihonSourceId)" }

    static func isUnresolved(_ sourceId: String) -> Bool { sourceId.hasPrefix(sourceIdPrefix) }

    /// The Mihon source id carried by an unresolved row, if any.
    static func mihonSourceId(from sourceId: String) -> Int64? {
        guard isUnresolved(sourceId) else { return nil }
        return Int64(sourceId.dropFirst(sourceIdPrefix.count))
    }
}

/// Mihon `syncId` <-> Nyora tracker ids, and the per-tracker status codes.
///
/// The status integers are NOT shared across trackers: MyAnimeList uses 6/7 for
/// plan-to-read/rereading where AniList and MangaBaka use 5/6.
enum MihonTrackerCodec {
    static let myAnimeList = 1
    static let aniList = 2
    static let mangaBaka = 11

    private static let malToNyora: [Int: String] = [
        1: "reading", 2: "completed", 3: "paused", 4: "dropped", 6: "planning", 7: "rereading",
    ]
    private static let aniListToNyora: [Int: String] = [
        1: "reading", 2: "completed", 3: "paused", 4: "dropped", 5: "planning", 6: "rereading",
    ]

    static func mihonTrackerId(for nyoraTrackerId: String) -> Int? {
        switch nyoraTrackerId.lowercased() {
        case "anilist": return aniList
        case "myanimelist", "mal": return myAnimeList
        case "mangabaka": return mangaBaka
        default: return nil
        }
    }

    static func nyoraTrackerId(for syncId: Int) -> String? {
        switch syncId {
        case aniList: return "anilist"
        case myAnimeList: return "myanimelist"
        case mangaBaka: return "mangabaka"
        default: return nil
        }
    }

    static func nyoraStatus(syncId: Int, status: Int) -> String {
        let table = syncId == myAnimeList ? malToNyora : aniListToNyora
        return table[status] ?? "reading"
    }

    static func mihonStatus(syncId: Int, status: String) -> Int {
        let table = syncId == myAnimeList ? malToNyora : aniListToNyora
        return table.first { $0.value == status.lowercased() }?.key ?? 1
    }
}
