//
//  MihonExportSnapshot.swift
//  Nyora
//

import Foundation

/// A dependency-free view of the library, and the pure mapping from it to the
/// Mihon schema.
///
/// The mapping is the part that decides whether an exported file is genuinely a
/// Mihon backup — chapter identity, per-manga category ORDER references, the
/// favourite flag against a schema default of true, and translating a local
/// source to its Mihon equivalent. Keeping it free of CoreData and AidokuRunner
/// means it can be executed and diffed against the JVM implementation directly,
/// rather than only inside a running app.
struct MihonExportSnapshot {
    struct Manga {
        var sourceId: String
        var mangaId: String
        var title: String
        var author: String?
        var artist: String?
        var desc: String?
        var tags: [String] = []
        var cover: String?
        var url: String?
        var status: Int = 0
        var nsfw: Int = 0
        var viewer: Int = 0
        var lang: String = ""
        var inLibrary: Bool = false
        var categories: [String] = []
        var chapters: [Chapter] = []
        var history: [History] = []
        var tracks: [Track] = []
    }

    struct Chapter {
        var chapterId: String
        var title: String?
        var scanlator: String?
        var chapterNumber: Float = -1
        var volume: Int = -1
        var sourceOrder: Int = 0
        var dateUploaded: Date?
    }

    struct History {
        var chapterId: String
        var progress: Int = 0
        var completed: Bool = false
        var dateRead: Date
    }

    struct Track {
        var trackerId: String
        var remoteId: String
        var title: String?
    }

    /// Category titles in display order — Mihon references them positionally.
    var categories: [String] = []
    var manga: [Manga] = []
}

enum MihonBackupConverter {

    /// Maps the snapshot onto the Mihon schema.
    ///
    /// `parserId` resolves a local source id to its Nyora parser id; injected so
    /// the mapping stays testable without UserDefaults.
    static func convert(
        _ snapshot: MihonExportSnapshot,
        parserId: (String) -> String = MihonSourceBridge.parserId(forLocalSource:)
    ) -> MihonBackup {
        // Mihon addresses a manga's categories by ORDER, not by id or name.
        var orderByTitle: [String: Int64] = [:]
        var backupCategories: [MihonCategory] = []
        for (index, title) in snapshot.categories.enumerated() {
            orderByTitle[title] = Int64(index)
            backupCategories.append(MihonCategory(name: title, order: Int64(index), id: Int64(index)))
        }

        var sourceNames: [Int64: String] = [:]
        var out: [MihonManga] = []

        for manga in snapshot.manga {
            let (sourceId, sourceName) = mihonSource(for: manga, parserId: parserId)
            if let sourceName {
                sourceNames[sourceId] = sourceName
            } else if sourceNames[sourceId] == nil {
                sourceNames[sourceId] = manga.sourceId
            }

            let progressByChapter = Dictionary(
                manga.history.map { ($0.chapterId, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            let chapters: [MihonChapter] = manga.chapters
                .sorted { $0.sourceOrder < $1.sourceOrder }
                .map { chapter in
                    let progress = progressByChapter[chapter.chapterId]
                    var memo = NyoraChapterMemo()
                    memo.nyoraChapterId = chapter.chapterId
                    memo.volume = chapter.volume
                    return MihonChapter(
                        // Mihon keys chapters by url; Aidoku's chapter id IS its
                        // source-relative key, so it is the correct value here.
                        url: chapter.chapterId,
                        name: chapter.title ?? "",
                        scanlator: chapter.scanlator,
                        read: progress?.completed ?? false,
                        bookmark: false,
                        lastPageRead: Int64(progress?.progress ?? 0),
                        dateUpload: Int64((chapter.dateUploaded?.timeIntervalSince1970 ?? 0) * 1000),
                        chapterNumber: chapter.chapterNumber,
                        sourceOrder: Int64(chapter.sourceOrder),
                        memo: MihonMemo.encode(memo)
                    )
                }

            var memo = NyoraMangaMemo()
            memo.nyoraId = manga.mangaId
            memo.sourceRef = manga.sourceId
            memo.publicUrl = manga.url ?? ""
            memo.isNsfw = manga.nsfw > 0

            let latest = manga.history.max { $0.dateRead < $1.dateRead }

            out.append(MihonManga(
                source: sourceId,
                url: manga.url ?? manga.mangaId,
                title: manga.title,
                artist: manga.artist,
                author: manga.author,
                desc: manga.desc,
                genre: manga.tags,
                status: manga.status,
                thumbnailUrl: manga.cover,
                chapters: chapters,
                categories: manga.categories.compactMap { orderByTitle[$0] },
                tracking: manga.tracks.compactMap { track in
                    guard let syncId = MihonTrackerCodec.mihonTrackerId(for: track.trackerId) else { return nil }
                    return MihonTracking(
                        syncId: syncId,
                        title: track.title ?? "",
                        mediaId: Int64(track.remoteId) ?? 0
                    )
                },
                // Mihon also backs up entries read but never added to the library,
                // flagged by favorite=false. The schema default is TRUE, so this
                // only survives because the writer emits non-default values.
                favorite: manga.inLibrary,
                viewerFlags: manga.viewer,
                history: latest.map {
                    [MihonHistory(
                        url: $0.chapterId,
                        lastRead: Int64($0.dateRead.timeIntervalSince1970 * 1000)
                    )]
                } ?? [],
                initialized: !chapters.isEmpty,
                memo: MihonMemo.encode(memo)
            ))
        }

        return MihonBackup(
            backupManga: out,
            backupCategories: backupCategories,
            backupSources: sourceNames
                .map { MihonSource(name: $0.value, sourceId: $0.key) }
                .sorted { $0.sourceId < $1.sourceId }
        )
    }

    /// Stable positive id for a local source with no Mihon equivalent. Mihon
    /// reports it as "source not installed" — a warning, not an error — and still
    /// restores the library and all reading progress.
    static func syntheticSourceId(_ name: String) -> Int64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325          // FNV-1a, 64-bit
        for byte in Array(name.lowercased().utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        return Int64(bitPattern: hash) & Int64.max
    }

    /// Mihon source id to write for a manga, and the name to declare for it.
    ///
    /// 1. Still-unresolved Mihon import -> keep the original id so a round trip
    ///    lands on exactly the same row.
    /// 2. Local source with a Mihon equivalent -> translate to that extension's
    ///    real id, so restoring in Mihon binds to an installable source.
    /// 3. Otherwise -> a deterministic synthetic id; Mihon reports "source not
    ///    installed", a warning, and still restores library and progress.
    static func mihonSource(
        for manga: MihonExportSnapshot.Manga,
        parserId: (String) -> String
    ) -> (id: Int64, name: String?) {
        if let existing = MihonSourceIds.mihonSourceId(from: manga.sourceId) {
            return (existing, nil)
        }
        let parser = parserId(manga.sourceId)
        if let translated = MihonSourceBridge.mihonSource(for: parser, lang: manga.lang),
           translated.sourceId != 0 {
            return (translated.sourceId, translated.name)
        }
        return (syntheticSourceId(parser), nil)
    }
}
