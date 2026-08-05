//
//  MihonMemo.swift
//  Nyora
//

import Foundation

/// Nyora-only fields carried inside Mihon's per-row `memo` extension bag
/// (`MihonManga` tag 112 / `MihonChapter` tag 13).
///
/// Mihon stores `memo` as an opaque JSON object and copies it through backup and
/// restore untouched, so Nyora -> Mihon -> Nyora round-trips without loss while a
/// stock Mihon install simply ignores the contents. Field names match the JVM
/// `NyoraMangaMemo` exactly — this is a cross-platform wire contract.
struct NyoraMangaMemo: Codable, Equatable {
    var nyoraId = ""
    var sourceRef = ""
    var altTitles: [String] = []
    var publicUrl = ""
    var largeCoverUrl = ""
    var contentRating = ""
    var state = ""
    var rating: Float = -1
    var isNsfw = false
    var unresolved = false
    var originSourceName = ""
    var readerMode = ""
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var hue: Double = 0
    var palette = ""
}

struct NyoraChapterMemo: Codable, Equatable {
    var nyoraChapterId = ""
    var scroll: Float = 0
    var percent: Float = 0
    var branch = ""
    var volume = 0
    var pageBookmarks: [NyoraPageBookmark] = []
}

struct NyoraPageBookmark: Codable, Equatable {
    var page = 0
    var note = ""
    var scroll: Float = 0
    var percent: Float = 0
    var createdAt: Int64 = 0
}

enum MihonMemo {
    /// Mihon's memo columns default to an encoded empty JSON object, never null.
    static let emptyBytes = Data("{}".utf8)

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? emptyBytes
    }

    /// A memo written by Mihon or another fork decodes to defaults rather than
    /// throwing — an unreadable extension bag must never fail a restore.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data?, fallback: T) -> T {
        guard let data, !data.isEmpty else { return fallback }
        return (try? JSONDecoder().decode(type, from: data)) ?? fallback
    }

    static func manga(from data: Data?) -> NyoraMangaMemo {
        decode(NyoraMangaMemo.self, from: data, fallback: NyoraMangaMemo())
    }

    static func chapter(from data: Data?) -> NyoraChapterMemo {
        decode(NyoraChapterMemo.self, from: data, fallback: NyoraChapterMemo())
    }
}
