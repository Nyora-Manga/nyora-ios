//
//  NyoraSyncClient.swift
//  Aidoku (iOS) — Nyora fork
//
//  Account + library sync against the self-hosted Nyora sync server
//  (https://stream.hasanraza.tech): OAuth2 password flow + JWT, then a generic
//  last-write-wins upsert/select over the per-user library tables. Pushes the
//  local library to nyora_manga + nyora_favourite and pulls them back.
//

import AidokuRunner
import Foundation

@MainActor
final class NyoraSyncClient: ObservableObject {
    static let shared = NyoraSyncClient()

    private let base = URL(string: "https://stream.hasanraza.tech")!

    private enum Keys {
        static let access = "nyora.sync.access"
        static let refresh = "nyora.sync.refresh"
        static let email = "nyora.sync.email"
        static let lastPull = "nyora.sync.lastPull"
    }

    @Published private(set) var email: String?

    private init() {
        email = UserDefaults.standard.string(forKey: Keys.email)
    }

    var isSignedIn: Bool { UserDefaults.standard.string(forKey: Keys.access) != nil }

    private var access: String? { UserDefaults.standard.string(forKey: Keys.access) }
    private var refresh: String? { UserDefaults.standard.string(forKey: Keys.refresh) }

    // MARK: - Token model

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let user_id: String?
    }

    enum SyncError: LocalizedError {
        case http(Int, String)
        case notSignedIn
        case badResponse

        var errorDescription: String? {
            switch self {
                case let .http(code, msg): "Server error \(code): \(msg)"
                case .notSignedIn: "Not signed in."
                case .badResponse: "Unexpected server response."
            }
        }
    }

    // MARK: - Auth

    func register(email: String, password: String) async throws {
        let url = base.appendingPathComponent("auth/register")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let tokens = try await send(req, decode: TokenResponse.self)
        store(tokens: tokens, email: email)
    }

    func signIn(email: String, password: String) async throws {
        let tokens = try await passwordGrant(email: email, password: password)
        store(tokens: tokens, email: email)
    }

    func signOut() {
        for key in [Keys.access, Keys.refresh, Keys.email, Keys.lastPull] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        email = nil
    }

    private func passwordGrant(email: String, password: String) async throws -> TokenResponse {
        try await tokenForm([
            "grant_type": "password",
            "username": email,
            "password": password
        ])
    }

    private func refreshGrant() async throws -> TokenResponse {
        guard let refresh else { throw SyncError.notSignedIn }
        return try await tokenForm([
            "grant_type": "refresh_token",
            "refresh_token": refresh
        ])
    }

    private func tokenForm(_ fields: [String: String]) async throws -> TokenResponse {
        let url = base.appendingPathComponent("auth/token")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        return try await send(req, decode: TokenResponse.self)
    }

    private func store(tokens: TokenResponse, email: String) {
        UserDefaults.standard.set(tokens.access_token, forKey: Keys.access)
        UserDefaults.standard.set(tokens.refresh_token, forKey: Keys.refresh)
        UserDefaults.standard.set(email, forKey: Keys.email)
        self.email = email
    }

    // MARK: - Generic sync wire

    /// POST /functions/v1/nyora-sync with the bearer token; refreshes once on 401.
    private func syncRequest(_ payload: [String: Any], retry: Bool = true) async throws -> [String: Any] {
        guard let access else { throw SyncError.notSignedIn }
        let url = base.appendingPathComponent("functions/v1/nyora-sync")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 401, retry {
            let tokens = try await refreshGrant()
            store(tokens: tokens, email: email ?? "")
            return try await syncRequest(payload, retry: false)
        }
        guard (200..<300).contains(code) else {
            throw SyncError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @discardableResult
    func upsert(table: String, rows: [[String: Any]]) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        let res = try await syncRequest(["action": "upsert", "table": table, "rows": rows])
        return res["count"] as? Int ?? 0
    }

    func select(table: String, since: String?) async throws -> [[String: Any]] {
        var payload: [String: Any] = ["action": "select", "table": table]
        if let since { payload["since"] = since }
        let res = try await syncRequest(payload)
        return res["data"] as? [[String: Any]] ?? []
    }

    // MARK: - Library push / pull

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// manga_id used on the server — globally unique across Aidoku sources.
    private nonisolated static func mangaId(sourceId: String, mangaKey: String) -> String {
        "\(sourceId)\u{1}\(mangaKey)"
    }

    private nonisolated static func splitMangaId(_ id: String) -> (sourceId: String, key: String) {
        if let r = id.range(of: "\u{1}") {
            return (String(id[..<r.lowerBound]), String(id[r.upperBound...]))
        }
        return ("", id)
    }

    @discardableResult
    func pushLibrary() async throws -> Int {
        let now = Self.iso.string(from: Date())
        var mangaRows: [[String: Any]] = []
        var favRows: [[String: Any]] = []

        let library = CoreDataManager.shared.getLibraryManga()
        for entry in library {
            guard let m = entry.manga else { continue }
            let mid = Self.mangaId(sourceId: m.sourceId, mangaKey: m.id)
            mangaRows.append([
                "id": mid,
                "title": m.title,
                "url": m.url ?? "",
                "cover_url": m.cover ?? "",
                "authors": jsonArray(m.author.map { [$0] } ?? []),
                "tags": jsonArray(m.tags ?? []),
                "description": m.desc ?? "",
                "is_nsfw": m.nsfw != 0,
                "source_ref": "{\"sourceKey\":\(jsonString(m.sourceId))}",
                "updated_at": now
            ])
            favRows.append([
                "manga_id": mid,
                "added_at": Self.iso.string(from: entry.dateAdded),
                "sort_key": 0,
                "updated_at": now
            ])
        }

        let a = try await upsert(table: "nyora_manga", rows: mangaRows)
        let b = try await upsert(table: "nyora_favourite", rows: favRows)
        return max(a, b)
    }

    @discardableResult
    func pullLibrary() async throws -> Int {
        // Pull manga details first so we can reconstruct entries.
        let mangaRows = try await select(table: "nyora_manga", since: nil)
        var mangaById: [String: [String: Any]] = [:]
        for row in mangaRows {
            if let id = row["id"] as? String { mangaById[id] = row }
        }
        let favRows = try await select(table: "nyora_favourite", since: nil)

        var added = 0
        await CoreDataManager.shared.container.performBackgroundTask { context in
            for fav in favRows {
                guard
                    let mid = fav["manga_id"] as? String,
                    (fav["deleted_at"] as? String) == nil
                else { continue }
                let (sourceId, key) = Self.splitMangaId(mid)
                guard !sourceId.isEmpty, SourceManager.shared.source(for: sourceId) != nil else { continue }
                if CoreDataManager.shared.hasLibraryManga(sourceId: sourceId, mangaId: key, context: context) {
                    continue
                }
                let row = mangaById[mid]
                let manga = AidokuRunner.Manga(
                    sourceKey: sourceId,
                    key: key,
                    title: (row?["title"] as? String) ?? "",
                    cover: row?["cover_url"] as? String,
                    url: (row?["url"] as? String).flatMap { URL(string: $0) }
                )
                CoreDataManager.shared.addToLibrary(manga: manga, chapters: [], context: context)
                added += 1
            }
            try? context.save()
        }
        UserDefaults.standard.set(Self.iso.string(from: Date()), forKey: Keys.lastPull)
        return added
    }

    // MARK: - Tracking push / pull

    /// iOS TrackStatus.rawValue -> canonical status string (see NYORA_TRACKING_SCHEMA.md §2).
    private nonisolated static func canonicalStatus(_ rawValue: Int) -> String {
        switch rawValue {
            case 1: "reading"
            case 2: "planning"
            case 3: "completed"
            case 4: "paused"
            case 5: "dropped"
            case 6: "rereading"
            default: "" // .none (7) / unknown -> no status
        }
    }

    /// Pushes linked trackers (CoreData `TrackObject`) plus their live `TrackState`
    /// to `nyora_tracking` using the canonical snake_case schema + LWW `updated_at`.
    ///
    /// The server upserts the full row (missing keys become column defaults), so every
    /// canonical column is emitted. When a tracker is logged in but its live state can't
    /// be fetched (transient/network error), that row is skipped this cycle rather than
    /// clobbering richer remote state with zero defaults.
    @discardableResult
    func pushTracking() async throws -> Int {
        let now = Self.iso.string(from: Date())

        let items: [TrackItem] = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getTracks(context: context).map { $0.toItem() }
        }
        guard !items.isEmpty else { return 0 }

        var rows: [[String: Any]] = []
        for item in items {
            // Base link fields — always present.
            var row: [String: Any] = [
                "tracker_id": item.trackerId,
                "remote_id": item.id,
                "source_id": item.sourceId,
                "manga_id": item.mangaId,
                "title": item.title ?? "",
                "chapter_offset": item.chapterOffset,
                "comment": "",
                // canonical state defaults (overwritten below if we have live state)
                "status": "",
                "score": 0.0,
                "last_read_chapter": 0.0,
                "last_read_volume": 0,
                "total_chapters": 0,
                "total_volumes": 0,
                "started_at": "",
                "finished_at": "",
                "updated_at": now
            ]

            // Fetch live state from the tracker service, if reachable.
            if let tracker = TrackerManager.getTracker(id: item.trackerId), tracker.isLoggedIn {
                let state: TrackState
                do {
                    state = try await tracker.getState(trackId: item.id)
                } catch {
                    // Don't overwrite good remote state with empty defaults on a transient failure.
                    continue
                }
                if let status = state.status {
                    row["status"] = Self.canonicalStatus(status.rawValue)
                }
                row["score"] = Double(state.score ?? 0)
                row["last_read_chapter"] = Double(state.lastReadChapter ?? 0)
                row["last_read_volume"] = state.lastReadVolume ?? 0
                row["total_chapters"] = state.totalChapters ?? 0
                row["total_volumes"] = state.totalVolumes ?? 0
                if let d = state.startReadDate { row["started_at"] = Self.iso.string(from: d) }
                if let d = state.finishReadDate { row["finished_at"] = Self.iso.string(from: d) }
            }

            rows.append(row)
        }

        return try await upsert(table: "nyora_tracking", rows: rows)
    }

    /// Pulls `nyora_tracking` rows and reconstructs the local tracker links
    /// (`TrackObject`). Restores missing links for trackers this platform recognizes,
    /// and honors soft-delete tombstones by removing the local link. The live state
    /// itself lives on the tracker service and is refreshed separately.
    @discardableResult
    func pullTracking() async throws -> Int {
        let rows = try await select(table: "nyora_tracking", since: nil)
        guard !rows.isEmpty else { return 0 }

        var changed = 0
        await CoreDataManager.shared.container.performBackgroundTask { context in
            for row in rows {
                guard
                    let trackerId = row["tracker_id"] as? String, !trackerId.isEmpty,
                    let sourceId = row["source_id"] as? String,
                    let mangaId = row["manga_id"] as? String, !mangaId.isEmpty
                else { continue }

                let deleted = (row["deleted_at"] as? String).map { !$0.isEmpty } ?? false
                let exists = CoreDataManager.shared.hasTrack(
                    trackerId: trackerId,
                    sourceId: sourceId,
                    mangaId: mangaId,
                    context: context
                )

                if deleted {
                    if exists {
                        CoreDataManager.shared.removeTrack(
                            trackerId: trackerId,
                            sourceId: sourceId,
                            mangaId: mangaId,
                            context: context
                        )
                        changed += 1
                    }
                    continue
                }

                if exists { continue }
                // Only restore links for trackers available on this platform.
                guard TrackerManager.getTracker(id: trackerId) != nil else { continue }
                let remoteId = (row["remote_id"] as? String) ?? ""
                guard !remoteId.isEmpty else { continue }

                CoreDataManager.shared.createTrack(
                    id: remoteId,
                    trackerId: trackerId,
                    sourceId: sourceId,
                    mangaId: mangaId,
                    title: row["title"] as? String,
                    chapterOffset: (row["chapter_offset"] as? Int) ?? 0,
                    context: context
                )
                changed += 1
            }
            try? context.save()
        }

        if changed > 0 {
            NotificationCenter.default.post(name: .updateTrackers, object: nil)
        }
        return changed
    }

    // MARK: - History push / pull

    /// Pushes local reading history (`HistoryObject`) to `nyora_history`.
    /// `manga_id` is the same globally-unique composite used by the library sync,
    /// and `source_id` is stored alongside so pulls can resolve the source directly.
    @discardableResult
    func pushHistory() async throws -> Int {
        let now = Self.iso.string(from: Date())
        let rows: [[String: Any]] = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getHistory(context: context).compactMap { h in
                guard !h.sourceId.isEmpty, !h.mangaId.isEmpty, !h.chapterId.isEmpty else { return nil }
                let mid = Self.mangaId(sourceId: h.sourceId, mangaKey: h.mangaId)
                let total = Int(h.total)
                let page = max(Int(h.progress), 0)
                let percent: Double = h.completed
                    ? 1.0
                    : (total > 0 && page > 0 ? min(Double(page) / Double(total), 1.0) : 0.0)
                return [
                    "manga_id": mid,
                    "source_id": h.sourceId,
                    "chapter_id": h.chapterId,
                    "chapter_title": h.chapter?.title ?? "",
                    "page": page,
                    "scroll": h.scrollPosition?.doubleValue ?? 0.0,
                    "percent": percent,
                    "chapters_count": 0,
                    "updated_at": h.dateRead.map { Self.iso.string(from: $0) } ?? now
                ]
            }
        }
        return try await upsert(table: "nyora_history", rows: rows)
    }

    /// Pulls `nyora_history` rows into local `HistoryObject`s, honoring soft-delete
    /// tombstones. The source is taken from the `source_id` column, falling back to the
    /// prefix of the composite `manga_id`.
    @discardableResult
    func pullHistory() async throws -> Int {
        let rows = try await select(table: "nyora_history", since: nil)
        guard !rows.isEmpty else { return 0 }

        var changed = 0
        await CoreDataManager.shared.container.performBackgroundTask { context in
            for row in rows {
                guard
                    let mid = row["manga_id"] as? String, !mid.isEmpty,
                    let chapterId = row["chapter_id"] as? String, !chapterId.isEmpty
                else { continue }
                let (splitSource, key) = Self.splitMangaId(mid)
                let sourceId = (row["source_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? splitSource
                guard !sourceId.isEmpty, !key.isEmpty else { continue }

                let deleted = (row["deleted_at"] as? String).map { !$0.isEmpty } ?? false
                let existing = CoreDataManager.shared.getHistory(
                    sourceId: sourceId,
                    mangaId: key,
                    chapterId: chapterId,
                    context: context
                )

                if deleted {
                    if let existing {
                        context.delete(existing)
                        changed += 1
                    }
                    continue
                }

                let obj = existing ?? CoreDataManager.shared.getOrCreateHistory(
                    sourceId: sourceId,
                    mangaId: key,
                    chapterId: chapterId,
                    context: context
                )
                let percent = (row["percent"] as? Double) ?? 0
                obj.progress = Int16((row["page"] as? Int) ?? 0)
                obj.completed = percent >= 1.0
                if let scroll = row["scroll"] as? Double {
                    obj.scrollPosition = NSNumber(value: scroll)
                }
                if let updated = row["updated_at"] as? String, let d = Self.iso.date(from: updated) {
                    obj.dateRead = d
                }
                changed += 1
            }
            try? context.save()
        }
        return changed
    }

    // MARK: - Category push / pull

    /// Pushes user categories (`CategoryObject`, excluding library filter groups) to
    /// `nyora_category`. iOS keys categories by title, so the canonical `id` == `title`.
    @discardableResult
    func pushCategories() async throws -> Int {
        let now = Self.iso.string(from: Date())
        let rows: [[String: Any]] = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getCategories(sorted: true, context: context)
                .filter { !$0.group }
                .compactMap { cat in
                    guard let title = cat.title, !title.isEmpty else { return nil }
                    return [
                        "id": title,
                        "title": title,
                        "sort_key": Int(cat.sort),
                        "updated_at": now
                    ]
                }
        }
        return try await upsert(table: "nyora_category", rows: rows)
    }

    /// Pulls `nyora_category` rows, creating missing categories (by title) and applying
    /// their sort order, and removing categories tombstoned via `deleted_at`.
    @discardableResult
    func pullCategories() async throws -> Int {
        let rows = try await select(table: "nyora_category", since: nil)
        guard !rows.isEmpty else { return 0 }

        var changed = 0
        await CoreDataManager.shared.container.performBackgroundTask { context in
            for row in rows {
                let id = (row["id"] as? String) ?? ""
                let title = (row["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
                guard !title.isEmpty else { continue }

                let deleted = (row["deleted_at"] as? String).map { !$0.isEmpty } ?? false
                if deleted {
                    if CoreDataManager.shared.hasCategory(title: title, context: context) {
                        CoreDataManager.shared.removeCategory(title: title, context: context)
                        changed += 1
                    }
                    continue
                }

                let object = CoreDataManager.shared.getCategory(title: title, context: context)
                    ?? CoreDataManager.shared.createCategory(title: title, context: context)
                if let sortKey = row["sort_key"] as? Int {
                    object.sort = Int16(sortKey)
                }
                changed += 1
            }
            try? context.save()
        }
        if changed > 0 {
            NotificationCenter.default.post(name: .updateCategories, object: nil)
        }
        return changed
    }

    // MARK: - Manga↔category links push / pull

    /// Pushes library manga → category assignments to `nyora_manga_category`
    /// (`category_id` == category title, matching `pushCategories`).
    @discardableResult
    func pushMangaCategories() async throws -> Int {
        let now = Self.iso.string(from: Date())
        let rows: [[String: Any]] = await CoreDataManager.shared.container.performBackgroundTask { context in
            var rows: [[String: Any]] = []
            for entry in CoreDataManager.shared.getLibraryManga(context: context) {
                guard let m = entry.manga else { continue }
                let mid = Self.mangaId(sourceId: m.sourceId, mangaKey: m.id)
                let categories = (entry.categories?.allObjects as? [CategoryObject]) ?? []
                for cat in categories where !cat.group {
                    guard let title = cat.title, !title.isEmpty else { continue }
                    rows.append([
                        "manga_id": mid,
                        "category_id": title,
                        "updated_at": now
                    ])
                }
            }
            return rows
        }
        return try await upsert(table: "nyora_manga_category", rows: rows)
    }

    /// Pulls `nyora_manga_category` rows, adding/removing category links on library manga.
    /// Assignments to manga not yet in the library are skipped (the library pull, which
    /// runs first, materializes those entries).
    @discardableResult
    func pullMangaCategories() async throws -> Int {
        let rows = try await select(table: "nyora_manga_category", since: nil)
        guard !rows.isEmpty else { return 0 }

        var changed = 0
        await CoreDataManager.shared.container.performBackgroundTask { context in
            for row in rows {
                guard
                    let mid = row["manga_id"] as? String, !mid.isEmpty,
                    let title = row["category_id"] as? String, !title.isEmpty
                else { continue }
                let (sourceId, key) = Self.splitMangaId(mid)
                guard !sourceId.isEmpty, !key.isEmpty else { continue }
                guard let libraryObject = CoreDataManager.shared.getLibraryManga(
                    sourceId: sourceId,
                    mangaId: key,
                    context: context
                ) else { continue }

                let deleted = (row["deleted_at"] as? String).map { !$0.isEmpty } ?? false
                if deleted {
                    if let cat = CoreDataManager.shared.getCategory(title: title, context: context) {
                        libraryObject.removeFromCategories(cat)
                        changed += 1
                    }
                    continue
                }

                let cat = CoreDataManager.shared.getCategory(title: title, context: context)
                    ?? CoreDataManager.shared.createCategory(title: title, context: context)
                libraryObject.addToCategories(cat)
                changed += 1
            }
            try? context.save()
        }
        return changed
    }

    // MARK: - Source prefs push / pull

    /// Pushes per-source preferences to `nyora_source_prefs`. On iOS the only persisted
    /// source pref is the browse pin state; installed sources are always "enabled".
    @discardableResult
    func pushSourcePrefs() async throws -> Int {
        let now = Self.iso.string(from: Date())
        let pinned = Set(UserDefaults.standard.stringArray(forKey: "Browse.pinnedList") ?? [])
        let rows: [[String: Any]] = SourceManager.shared.sources.map { source in
            [
                "source_id": source.id,
                "is_pinned": pinned.contains(source.id),
                "is_enabled": true,
                "updated_at": now
            ]
        }
        return try await upsert(table: "nyora_source_prefs", rows: rows)
    }

    /// Pulls `nyora_source_prefs`, merging remote pin state into the local browse pin list.
    @discardableResult
    func pullSourcePrefs() async throws -> Int {
        let rows = try await select(table: "nyora_source_prefs", since: nil)
        guard !rows.isEmpty else { return 0 }

        var pinned = Set(UserDefaults.standard.stringArray(forKey: "Browse.pinnedList") ?? [])
        var changed = 0
        for row in rows {
            guard let sourceId = row["source_id"] as? String, !sourceId.isEmpty else { continue }
            let isPinned = row["is_pinned"] as? Bool ?? false
            if isPinned, !pinned.contains(sourceId) {
                pinned.insert(sourceId)
                changed += 1
            } else if !isPinned, pinned.contains(sourceId) {
                pinned.remove(sourceId)
                changed += 1
            }
        }
        if changed > 0 {
            UserDefaults.standard.set(Array(pinned), forKey: "Browse.pinnedList")
            NotificationCenter.default.post(name: .updateSourceList, object: nil)
        }
        return changed
    }

    // MARK: - Per-manga reader prefs push / pull

    /// Per-manga reading-mode override key (see `ReaderViewController`).
    private nonisolated static func readingModeKey(sourceId: String, mangaKey: String) -> String {
        "Reader.readingMode.\(sourceId).\(mangaKey)"
    }

    /// Pushes per-manga reader preferences to `nyora_manga_prefs`. iOS persists a per-manga
    /// reading-mode override in `UserDefaults`; the color-adjustment columns are reader-global
    /// on iOS and emitted as canonical defaults.
    @discardableResult
    func pushMangaPrefs() async throws -> Int {
        let now = Self.iso.string(from: Date())
        let pairs: [(source: String, key: String)] = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getLibraryManga(context: context).compactMap { entry in
                guard let m = entry.manga else { return nil }
                return (m.sourceId, m.id)
            }
        }
        var rows: [[String: Any]] = []
        for pair in pairs {
            let key = Self.readingModeKey(sourceId: pair.source, mangaKey: pair.key)
            // Only sync explicit overrides (a registered default returns nil for object(forKey:)).
            guard
                let mode = UserDefaults.standard.object(forKey: key) as? String,
                !mode.isEmpty, mode != "default"
            else { continue }
            rows.append([
                "manga_id": Self.mangaId(sourceId: pair.source, mangaKey: pair.key),
                "reader_mode": mode,
                "brightness": 0.0,
                "contrast": 1.0,
                "saturation": 1.0,
                "hue": 0.0,
                "palette": "",
                "updated_at": now
            ])
        }
        return try await upsert(table: "nyora_manga_prefs", rows: rows)
    }

    /// Pulls `nyora_manga_prefs`, applying the per-manga reading-mode override locally.
    @discardableResult
    func pullMangaPrefs() async throws -> Int {
        let rows = try await select(table: "nyora_manga_prefs", since: nil)
        guard !rows.isEmpty else { return 0 }

        var changed = 0
        for row in rows {
            guard
                let mid = row["manga_id"] as? String, !mid.isEmpty,
                let mode = row["reader_mode"] as? String, !mode.isEmpty
            else { continue }
            let (sourceId, key) = Self.splitMangaId(mid)
            guard !sourceId.isEmpty, !key.isEmpty else { continue }
            UserDefaults.standard.set(mode, forKey: Self.readingModeKey(sourceId: sourceId, mangaKey: key))
            changed += 1
        }
        return changed
    }

    @discardableResult
    func syncNow() async throws -> (pushed: Int, pulled: Int) {
        // Pull first (LWW: remote → local), then push local state back.
        // NOTE: iOS has no page-bookmark model, so `nyora_bookmark` is intentionally
        // not synced from this client (Android owns that table).
        var pulled = 0
        var pushed = 0

        pulled += try await pullLibrary()
        pulled += try await pullCategories()
        pulled += try await pullMangaCategories()
        pulled += try await pullHistory()
        pulled += try await pullSourcePrefs()
        pulled += try await pullMangaPrefs()
        pulled += try await pullTracking()

        pushed += try await pushLibrary()
        pushed += try await pushCategories()
        pushed += try await pushMangaCategories()
        pushed += try await pushHistory()
        pushed += try await pushSourcePrefs()
        pushed += try await pushMangaPrefs()
        pushed += try await pushTracking()

        return (pushed, pulled)
    }

    // MARK: - Helpers

    private func send<T: Decodable>(_ request: URLRequest, decode: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            var msg = String(data: data, encoding: .utf8) ?? ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = obj["detail"] as? String {
                msg = detail
            }
            throw SyncError.http(code, msg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func jsonArray(_ arr: [String]) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: arr), encoding: .utf8)) ?? "[]"
    }

    private func jsonString(_ s: String) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: [s]), encoding: .utf8))
            .map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }
}
