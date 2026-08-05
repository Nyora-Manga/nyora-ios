//
//  MihonBackupManager.swift
//  Nyora
//

import CoreData
import Foundation

struct MihonImportResult {
    var manga = 0
    var categories = 0
    var history = 0
    var tracking = 0
    /// Mihon sources bound to a local source (bridge hits plus name matches).
    var sourcesMatched = 0
    /// Of those, how many came from the offline domain bridge rather than a name guess.
    var sourcesBridged = 0
    /// Mihon source names this device has no source for; their entries still imported.
    var unmatchedSources: [String] = []
    /// Entries left pointing at a Mihon source, awaiting resolution.
    var pendingResolution = 0
    /// Entries filed under the "Missing Source" category for manual migration.
    var missingSourceCount = 0
    /// True when a cloud sync run succeeded; false when signed out or offline.
    var syncPushed = false
}

/// Mihon `.tachibk` backup and restore, mirroring the JVM implementation in
/// nyora-shared: same schema, source bridge, namespacing and merge semantics.
///
/// Two rules differ from Aidoku's own backup path:
///
///  - Import merges. `BackupManager.restore` clears the manga, library, category
///    and history tables first; because cloud sync uses soft-delete tombstones,
///    a clear-then-insert would replicate a mass deletion to every device.
///  - Row source ids are colon-namespaced (`mihon:<id>`), since the sync wire
///    format re-prefixes any id without a colon.
actor MihonBackupManager {
    static let shared = MihonBackupManager()

    static let fileExtension = "tachibk"

    /// Title of the category collecting entries with no matching Nyora source.
    /// Kept in step with the JVM importer so a library synced between platforms
    /// shows one bucket, not two.
    static let missingSourceCategory = "Missing Source"

    // MARK: - Export

    /// Builds a `.tachibk` from the current library.
    ///
    /// Local sources are translated to their Mihon equivalents where one exists,
    /// so restoring this file in Mihon lands on an extension the user can install
    /// rather than an unknown source.
    func export() async throws -> Data {
        let backup = await BackupManager.shared.createBackup(options: .init(
            libraryEntries: true,
            history: true,
            chapters: true,
            tracking: true,
            readingSessions: false,   // Nyora-only, no Mihon representation
            updates: false,           // recomputed from chapters on restore
            categories: true,
            settings: false,          // app settings do not translate across apps
            sourceLists: false,
            sensitiveSettings: false  // never export credentials
        ))
        let mihon = await Self.convert(backup: backup)
        let data = try MihonBackupCodec.encode(mihon)
        // Prove the file is readable before it ever reaches the user.
        try MihonBackupCodec.verify(data)
        return data
    }

    /// Adapts Aidoku's in-memory backup into the dependency-free snapshot the
    /// pure converter consumes. Deliberately mechanical: all mapping decisions
    /// live in `MihonBackupConverter`, where they can be executed and diffed
    /// against the JVM implementation.
    static func convert(backup: Backup) async -> MihonBackup {
        MihonBackupConverter.convert(snapshot(from: backup))
    }

    static func snapshot(from backup: Backup) -> MihonExportSnapshot {
        let chaptersByManga = Dictionary(grouping: backup.chapters ?? []) { ChapterKey($0.sourceId, $0.mangaId) }
        let historyByManga = Dictionary(grouping: backup.history ?? []) { ChapterKey($0.sourceId, $0.mangaId) }
        let tracksByManga = Dictionary(grouping: backup.trackItems ?? []) { ChapterKey($0.sourceId, $0.mangaId) }
        let libraryByKey = Dictionary(
            (backup.library ?? []).map { (ChapterKey($0.sourceId, $0.mangaId), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var out = MihonExportSnapshot()
        out.categories = (backup.categories ?? [])
            .sorted { ($0.sort ?? 0) < ($1.sort ?? 0) }
            .compactMap { $0.title }

        out.manga = (backup.manga ?? []).map { manga in
            let key = ChapterKey(manga.sourceId, manga.id)
            return MihonExportSnapshot.Manga(
                sourceId: manga.sourceId,
                mangaId: manga.id,
                title: manga.title,
                author: manga.author,
                artist: manga.artist,
                desc: manga.desc,
                tags: manga.tags ?? [],
                cover: manga.cover,
                url: manga.url,
                status: manga.status,
                nsfw: manga.nsfw,
                viewer: manga.viewer,
                lang: manga.langFilter ?? "",
                inLibrary: libraryByKey[key] != nil,
                categories: libraryByKey[key]?.categories ?? [],
                chapters: (chaptersByManga[key] ?? []).map {
                    MihonExportSnapshot.Chapter(
                        chapterId: $0.id,
                        title: $0.title,
                        scanlator: $0.scanlator,
                        chapterNumber: Float($0.chapter ?? -1),
                        volume: Int($0.volume ?? -1),
                        sourceOrder: $0.sourceOrder ?? 0,
                        dateUploaded: $0.dateUploaded
                    )
                },
                history: (historyByManga[key] ?? []).map {
                    MihonExportSnapshot.History(
                        chapterId: $0.chapterId,
                        progress: $0.progress ?? 0,
                        completed: $0.completed,
                        dateRead: $0.dateRead
                    )
                },
                tracks: (tracksByManga[key] ?? []).map {
                    MihonExportSnapshot.Track(
                        trackerId: $0.trackerId,
                        remoteId: $0.id,
                        title: $0.title
                    )
                }
            )
        }
        return out
    }

    struct ChapterKey: Hashable {
        let sourceId: String
        let mangaId: String
        init(_ sourceId: String, _ mangaId: String) {
            self.sourceId = sourceId
            self.mangaId = mangaId
        }
    }
}
