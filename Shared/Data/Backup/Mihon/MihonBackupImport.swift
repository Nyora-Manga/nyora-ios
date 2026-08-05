//
//  MihonBackupImport.swift
//  Nyora
//

import CoreData
import Foundation

extension MihonBackupManager {

    /// Restores a Mihon `.tachibk` by MERGING into the existing library.
    ///
    /// Nothing absent from the file is deleted and nothing already present is
    /// cleared, because Nyora's cloud sync uses soft-delete tombstones: a
    /// clear-then-insert import would replicate a mass deletion to every device.
    /// Favourite state is OR-merged — an import can add a library entry but never
    /// remove one.
    ///
    /// Entries whose Mihon source has no local equivalent are still imported,
    /// under a `mihon:<id>` placeholder source, so the user keeps titles, covers
    /// and reading progress.
    func importBackup(data: Data) async throws -> MihonImportResult {
        let backup = try MihonBackupCodec.decode(data)
        let installed = await SourceManager.shared.sources.map { $0.key }

        // Bridge first, source name second — the bridge binds on the actual site.
        var sourceMap: [Int64: String] = [:]
        var bridged = 0
        var unmatched: [String] = []
        for source in backup.backupSources {
            if let parserId = MihonSourceBridge.nyoraSourceId(for: source.sourceId),
               let local = MihonSourceBridge.localSourceId(forParser: parserId, installed: installed) {
                sourceMap[source.sourceId] = local
                bridged += 1
            } else if let local = Self.matchByName(source.name, installed: installed) {
                sourceMap[source.sourceId] = local
            } else if !source.name.isEmpty {
                unmatched.append(source.name)
            }
        }

        var result = MihonImportResult()
        result.sourcesMatched = sourceMap.count
        result.sourcesBridged = bridged
        result.unmatchedSources = Array(Set(unmatched)).sorted()

        let categoryOrderToTitle = Dictionary(
            backup.backupCategories.map { ($0.order, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )

        // Categories: match by title so a re-import is idempotent rather than
        // duplicating tabs.
        let created: Int = await CoreDataManager.shared.container.performBackgroundTask { context in
            let existing = Set(CoreDataManager.shared.getCategories(context: context).compactMap { $0.title })
            var added = 0
            for category in backup.backupCategories where !existing.contains(category.name) {
                _ = CoreDataManager.shared.createCategory(title: category.name, context: context)
                added += 1
            }
            if added > 0 { try? context.save() }
            return added
        }
        result.categories = created

        let counts: (manga: Int, history: Int, tracking: Int, pending: Int, missing: Int) =
            await CoreDataManager.shared.container.performBackgroundTask { context in
                var mangaCount = 0, historyCount = 0, trackingCount = 0, pendingCount = 0
                var unresolved: [(sourceId: String, mangaId: String)] = []

                for entry in backup.backupManga {
                    let memo = MihonMemo.manga(from: entry.memo)
                    // A backup Nyora itself wrote carries the original id and
                    // source, and that ALWAYS wins over the envelope's Mihon
                    // source id — the exporter translates sources, so the
                    // envelope may legitimately name a Mihon extension for an
                    // entry that is natively local.
                    let isNyoraOrigin = !memo.nyoraId.isEmpty && !memo.sourceRef.isEmpty
                    let sourceId: String
                    let mangaId: String
                    if isNyoraOrigin {
                        sourceId = memo.sourceRef
                        mangaId = memo.nyoraId
                    } else if let local = sourceMap[entry.source] {
                        sourceId = local
                        mangaId = entry.url
                        pendingCount += 1
                    } else {
                        // Colon-namespaced so it survives the sync wire format.
                        sourceId = MihonSourceIds.sourceId(entry.source)
                        mangaId = entry.url
                        pendingCount += 1
                    }
                    guard !mangaId.isEmpty else { continue }
                    if !isNyoraOrigin {
                        unresolved.append((sourceId, mangaId))
                    }

                    Self.upsertManga(entry, sourceId: sourceId, mangaId: mangaId, context: context)
                    mangaCount += 1

                    if entry.favorite,
                       !CoreDataManager.shared.hasLibraryManga(
                           sourceId: sourceId, mangaId: mangaId, context: context
                       ) {
                        Self.addLibraryEntry(
                            sourceId: sourceId,
                            mangaId: mangaId,
                            categories: entry.categories.compactMap { categoryOrderToTitle[$0] },
                            context: context
                        )
                    }

                    historyCount += Self.restoreHistory(entry, sourceId: sourceId, mangaId: mangaId, context: context)
                    trackingCount += Self.restoreTracking(entry, sourceId: sourceId, mangaId: mangaId, context: context)
                }

                // Unresolved entries are otherwise indistinguishable from the rest
                // of the library, so file them under one category the user can open
                // and work through.
                var missing = 0
                if !unresolved.isEmpty {
                    let title = Self.missingSourceCategory
                    let existing = CoreDataManager.shared.getCategories(context: context)
                    if !existing.contains(where: { $0.title == title }) {
                        _ = CoreDataManager.shared.createCategory(title: title, context: context)
                    }
                    for entry in unresolved {
                        CoreDataManager.shared.addCategoriesToManga(
                            sourceId: entry.sourceId,
                            mangaId: entry.mangaId,
                            categories: [title],
                            context: context
                        )
                        missing += 1
                    }
                }

                try? context.save()
                return (mangaCount, historyCount, trackingCount, pendingCount, missing)
            }

        result.manga = counts.manga
        result.history = counts.history
        result.tracking = counts.tracking
        result.pendingResolution = counts.pending
        result.missingSourceCount = counts.missing

        // Push the merged library so every other device converges. Sync itself is
        // untouched — this is a normal run of the existing client. A sync failure
        // (offline, signed out) must not fail an otherwise successful import.
        result.syncPushed = (try? await NyoraSyncClient.shared.syncNow()) != nil

        return result
    }

    // MARK: - Merge helpers

    /// Names that normalise to nothing (CJK-only titles) must not all collide on
    /// the empty string, so a usable ASCII stem is required.
    private static func normalise(_ name: String) -> String {
        let stripped = name.lowercased()
            .replacingOccurrences(of: #"\s*\((?:[a-z]{2,3}|all|multi)\)\s*$"#, with: "", options: .regularExpression)
        return stripped.filter { $0.isLetter || $0.isNumber }
    }

    static func matchByName(_ mihonName: String, installed: [String]) -> String? {
        let key = normalise(mihonName)
        guard key.count >= 4 else { return nil }
        return installed.first { normalise($0) == key }
    }

    fileprivate static func upsertManga(
        _ entry: MihonManga,
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext
    ) {
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "sourceId == %@ AND id == %@", sourceId, mangaId)
        request.fetchLimit = 1
        let object = (try? context.fetch(request))?.first ?? MangaObject(context: context)
        object.sourceId = sourceId
        object.id = mangaId
        object.title = entry.title
        object.author = entry.author
        object.artist = entry.artist
        object.desc = entry.desc
        object.tags = entry.genre
        object.cover = entry.thumbnailUrl
        object.url = entry.url
        object.status = Int16(entry.status)
        object.nsfw = Int16(MihonMemo.manga(from: entry.memo).isNsfw ? 2 : 0)
        object.viewer = Int16(entry.viewerFlags)
    }

    fileprivate static func addLibraryEntry(
        sourceId: String,
        mangaId: String,
        categories: [String],
        context: NSManagedObjectContext
    ) {
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "sourceId == %@ AND id == %@", sourceId, mangaId)
        request.fetchLimit = 1
        guard let manga = (try? context.fetch(request))?.first else { return }
        let library = LibraryMangaObject(context: context)
        library.manga = manga
        if !categories.isEmpty {
            CoreDataManager.shared.addCategoriesToManga(
                sourceId: sourceId,
                mangaId: mangaId,
                categories: categories,
                context: context
            )
        }
    }

    /// Mihon records history per chapter, which maps cleanly onto Aidoku's
    /// per-chapter history rows.
    fileprivate static func restoreHistory(
        _ entry: MihonManga,
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext
    ) -> Int {
        var count = 0
        let readAt = Dictionary(
            entry.history.map { ($0.url, $0.lastRead) },
            uniquingKeysWith: { first, _ in first }
        )
        for chapter in entry.chapters where chapter.read || chapter.lastPageRead > 0 {
            let date = readAt[chapter.url].map { Date(timeIntervalSince1970: Double($0) / 1000) }
            CoreDataManager.shared.setProgress(
                Int(chapter.lastPageRead),
                sourceId: sourceId,
                mangaId: mangaId,
                chapterId: chapter.url,
                dateRead: date,
                completed: chapter.read,
                context: context
            )
            count += 1
        }
        return count
    }

    fileprivate static func restoreTracking(
        _ entry: MihonManga,
        sourceId: String,
        mangaId: String,
        context: NSManagedObjectContext
    ) -> Int {
        var count = 0
        let existing = CoreDataManager.shared.getTracks(sourceId: sourceId, mangaId: mangaId, context: context)
        for track in entry.tracking {
            guard let trackerId = MihonTrackerCodec.nyoraTrackerId(for: track.syncId) else { continue }
            if existing.contains(where: { $0.trackerId == trackerId }) { continue }
            let object = TrackObject(context: context)
            object.id = String(track.remoteId)
            object.trackerId = trackerId
            object.sourceId = sourceId
            object.mangaId = mangaId
            object.title = track.title
            count += 1
        }
        return count
    }
}
