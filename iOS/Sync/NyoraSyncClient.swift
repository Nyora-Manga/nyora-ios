//
//  NyoraSyncClient.swift
//  Aidoku (iOS) — Nyora fork
//
//  Account + library sync against the self-hosted Nyora sync server
//  (https://sync.nyora.xyz): OAuth2 password flow + JWT, then a generic
//  last-write-wins upsert/select over the per-user library tables. Pushes the
//  local library to nyora_manga + nyora_favourite and pulls them back.
//

import AidokuRunner
import Foundation

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class NyoraSyncClient: ObservableObject {
    static let shared = NyoraSyncClient()

    private let base = URL(string: "https://sync.nyora.xyz")!

    private var autoSyncStarted = false
    private var debounceTask: Task<Void, Never>?

    /// Serializes `syncNow()` the way android's `SupabaseSync.syncMutex` does: onboarding's
    /// fire-and-forget kickoff, the debounced auto-sync, and a manual "Sync now" tap can all
    /// land within the same few seconds. Without this, concurrent runs could both hit a 401
    /// and race to refresh the token — the loser's `store(tokens:)` can stomp the winner's
    /// freshly-rotated refresh token and sign the user back out. Overlapping callers instead
    /// join the in-flight sync's result rather than starting a second one.
    private var inFlightSync: Task<(pushed: Int, pulled: Int), Error>?

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

    /// The bare parser enum name (e.g. "MANGADEX") for an Aidoku source key — the token android &
    /// web put in the cross-device `manga_id` `"<EnumName>|<url>"` and in `source_ref` `{"name":…}`.
    /// Nyora sources store their parser id under UserDefaults `"<sourceKey>.parserSource"`
    /// ("parser:MANGADEX"); other source types fall back to their own key.
    nonisolated static func enumName(for sourceId: String) -> String {
        if let parser = UserDefaults.standard.string(forKey: "\(sourceId).parserSource") {
            return parser.hasPrefix("parser:") ? String(parser.dropFirst("parser:".count)) : parser
        }
        return sourceId
    }

    /// Cross-device stable manga id — byte-identical to android (`"$sourceName|$url"`) and web, so
    /// history/favourites merge across platforms instead of duplicating.
    private nonisolated static func mangaId(sourceId: String, mangaKey: String) -> String {
        "\(enumName(for: sourceId))|\(mangaKey)"
    }

    /// Split `"<EnumName>|<url>"` → (enumName, url), on the FIRST `|`.
    private nonisolated static func splitMangaId(_ id: String) -> (name: String, key: String) {
        if let r = id.range(of: "|") {
            return (String(id[..<r.lowerBound]), String(id[r.upperBound...]))
        }
        return ("", id)
    }

    /// enumName ("MANGADEX") → the installed Aidoku source key ("nyora.mangadex"), for resolving
    /// pulled rows back to a local source. Built on the main actor before a CoreData background task.
    private func installedSourceMap() -> [String: String] {
        var map: [String: String] = [:]
        for source in SourceManager.shared.sources {
            let name = Self.enumName(for: source.id)
            map[name] = source.id
            // Also map the raw source id so iOS-origin rows (older composite/plain ids) still resolve.
            map[source.id] = source.id
        }
        return map
    }

    /// Build a `nyora_manga` metadata row (android/web schema) from a local MangaObject, so history
    /// and favourites carry title/cover/source and render on any device — even before the source is
    /// installed. `source_ref` is `{"name":"<EnumName>"}` (bare name), matching android's decoder.
    private nonisolated static func mangaRow(_ m: MangaObject, now: String) -> [String: Any] {
        let name = enumName(for: m.sourceId)
        let people = [m.author, m.artist]
            .compactMap { $0 }
            .flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty }
        let sourceRef = (try? String(
            data: JSONSerialization.data(withJSONObject: ["name": name]),
            encoding: .utf8
        )) ?? "{\"name\":\"\"}"
        return [
            "id": mangaId(sourceId: m.sourceId, mangaKey: m.id),
            "title": m.title,
            "url": m.url ?? "",
            "public_url": m.url ?? "",
            "cover_url": m.cover ?? "",
            "large_cover_url": m.cover ?? "",
            "authors": jsonArrayString(people),
            "tags": jsonArrayString(m.tags ?? []),
            "description": m.desc ?? "",
            "is_nsfw": m.nsfw != 0,
            "content_rating": (m.nsfw != 0 ? "ADULT" : NSNull()) as Any,
            "source_ref": sourceRef,
            "updated_at": now
        ]
    }

    private nonisolated static func jsonArrayString(_ arr: [String]) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: arr), encoding: .utf8)) ?? "[]"
    }

    @discardableResult
    func pushLibrary() async throws -> Int {
        let now = Self.iso.string(from: Date())
        var mangaRows: [[String: Any]] = []
        var favRows: [[String: Any]] = []

        let library = CoreDataManager.shared.getLibraryManga()
        for entry in library {
            guard let m = entry.manga else { continue }
            mangaRows.append(Self.mangaRow(m, now: now))
            favRows.append([
                "manga_id": Self.mangaId(sourceId: m.sourceId, mangaKey: m.id),
                "sort_key": 0,
                "updated_at": Self.iso.string(from: entry.dateAdded),
                "added_at": Self.iso.string(from: entry.dateAdded)
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
        let sourceMap = installedSourceMap()

        var added = 0
        await CoreDataManager.shared.container.performBackgroundTask { context in
            for fav in favRows {
                guard
                    let mid = fav["manga_id"] as? String,
                    (fav["deleted_at"] as? String) == nil
                else { continue }
                let (name, key) = Self.splitMangaId(mid)
                // Resolve the cross-device enum name ("MANGADEX") to an installed source; skip if
                // the source isn't installed (can't render a readable library entry for it).
                guard let sourceId = sourceMap[name], !key.isEmpty else { continue }
                if CoreDataManager.shared.hasLibraryManga(sourceId: sourceId, mangaId: key, context: context) {
                    continue
                }
                let row = mangaById[mid]
                let manga = AidokuRunner.Manga(
                    sourceKey: sourceId,
                    key: key,
                    title: (row?["title"] as? String) ?? "",
                    cover: (row?["cover_url"] as? String) ?? (row?["large_cover_url"] as? String),
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
        let (historyRows, mangaRows): ([[String: Any]], [[String: Any]]) =
            await CoreDataManager.shared.container.performBackgroundTask { context in
                var history: [[String: Any]] = []
                var manga: [[String: Any]] = []
                var seenManga = Set<String>()
                for h in CoreDataManager.shared.getHistory(context: context) {
                    guard !h.sourceId.isEmpty, !h.mangaId.isEmpty, !h.chapterId.isEmpty else { continue }
                    let mid = Self.mangaId(sourceId: h.sourceId, mangaKey: h.mangaId)
                    let total = Int(h.total)
                    let page = max(Int(h.progress), 0)
                    let percent: Double = h.completed
                        ? 1.0
                        : (total > 0 && page > 0 ? min(Double(page) / Double(total), 1.0) : 0.0)
                    history.append([
                        "manga_id": mid,
                        "source_id": Self.enumName(for: h.sourceId),
                        "chapter_id": h.chapterId,
                        "chapter_title": h.chapter?.title ?? "",
                        "page": page,
                        "scroll": h.scrollPosition?.doubleValue ?? 0.0,
                        "percent": percent,
                        "chapters_count": 0,
                        "updated_at": h.dateRead.map { Self.iso.string(from: $0) } ?? now
                    ])
                    // Carry each history item's manga metadata so it renders (title/cover/source)
                    // on any device — even one where the manga isn't in the library.
                    if !seenManga.contains(mid),
                       let m = CoreDataManager.shared.getManga(sourceId: h.sourceId, mangaId: h.mangaId, context: context) {
                        seenManga.insert(mid)
                        manga.append(Self.mangaRow(m, now: now))
                    }
                }
                return (history, manga)
            }
        let a = try await upsert(table: "nyora_manga", rows: mangaRows)
        let b = try await upsert(table: "nyora_history", rows: historyRows)
        return max(a, b)
    }

    /// Pulls `nyora_history` rows into local `HistoryObject`s, honoring soft-delete
    /// tombstones. The source is taken from the `source_id` column, falling back to the
    /// prefix of the composite `manga_id`.
    @discardableResult
    func pullHistory() async throws -> Int {
        let rows = try await select(table: "nyora_history", since: nil)
        guard !rows.isEmpty else { return 0 }
        // Pull manga metadata too, so synced history shows title/cover without re-fetching the source.
        let mangaRows = try await select(table: "nyora_manga", since: nil)
        var mangaById: [String: [String: Any]] = [:]
        for row in mangaRows where row["id"] is String { mangaById[row["id"] as! String] = row }
        let sourceMap = installedSourceMap()

        var changed = 0
        await CoreDataManager.shared.container.performBackgroundTask { context in
            for row in rows {
                guard
                    let mid = row["manga_id"] as? String, !mid.isEmpty,
                    let chapterId = row["chapter_id"] as? String, !chapterId.isEmpty
                else { continue }
                let (name, key) = Self.splitMangaId(mid)
                let resolveName = name.isEmpty ? ((row["source_id"] as? String) ?? "") : name
                guard let sourceId = sourceMap[resolveName], !key.isEmpty else { continue }

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

                // Seed the manga's metadata so History renders it without the source re-fetch.
                if !CoreDataManager.shared.hasManga(sourceId: sourceId, mangaId: key, context: context),
                   let mrow = mangaById[mid] {
                    let seed = AidokuRunner.Manga(
                        sourceKey: sourceId,
                        key: key,
                        title: (mrow["title"] as? String) ?? "",
                        cover: (mrow["cover_url"] as? String) ?? (mrow["large_cover_url"] as? String),
                        url: (mrow["url"] as? String).flatMap { URL(string: $0) }
                    )
                    _ = CoreDataManager.shared.getOrCreateManga(seed, context: context)
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
        if changed > 0 {
            NotificationCenter.default.post(name: .updateHistory, object: nil)
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

        let sourceMap = installedSourceMap()
        var changed = 0
        await CoreDataManager.shared.container.performBackgroundTask { context in
            for row in rows {
                guard
                    let mid = row["manga_id"] as? String, !mid.isEmpty,
                    let title = row["category_id"] as? String, !title.isEmpty
                else { continue }
                let (name, key) = Self.splitMangaId(mid)
                guard let sourceId = sourceMap[name], !key.isEmpty else { continue }
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

        let sourceMap = installedSourceMap()
        var changed = 0
        for row in rows {
            guard
                let mid = row["manga_id"] as? String, !mid.isEmpty,
                let mode = row["reader_mode"] as? String, !mode.isEmpty
            else { continue }
            let (name, key) = Self.splitMangaId(mid)
            guard let sourceId = sourceMap[name], !key.isEmpty else { continue }
            UserDefaults.standard.set(mode, forKey: Self.readingModeKey(sourceId: sourceId, mangaKey: key))
            changed += 1
        }
        return changed
    }

    // MARK: - Bookmarks push / pull

    /// Pushes page bookmarks (`NyoraBookmarkStore`) to `nyora_bookmark`, plus each bookmark's manga
    /// metadata to `nyora_manga`, so a saved page shows title/cover on any device.
    @discardableResult
    func pushBookmarks() async throws -> Int {
        let now = Self.iso.string(from: Date())
        let bookmarks = NyoraBookmarkStore.shared.bookmarks
        guard !bookmarks.isEmpty else { return 0 }

        var bookmarkRows: [[String: Any]] = []
        var mangaRows: [[String: Any]] = []
        var seenManga = Set<String>()
        for bm in bookmarks {
            let mid = Self.mangaId(sourceId: bm.sourceId, mangaKey: bm.mangaId)
            bookmarkRows.append([
                "id": "\(mid):\(bm.chapterId):\(bm.page)",
                "manga_id": mid,
                "chapter_id": bm.chapterId,
                "chapter_title": bm.chapterTitle ?? "",
                "page": bm.page,
                "scroll": 0,
                "note": bm.note ?? "",
                "image_url": bm.imageUrl ?? "",
                "percent": 0,
                "created_at": Self.iso.string(from: bm.createdAt),
                "updated_at": now
            ])
            if !seenManga.contains(mid) {
                seenManga.insert(mid)
                let name = Self.enumName(for: bm.sourceId)
                let sourceRef = (try? String(
                    data: JSONSerialization.data(withJSONObject: ["name": name]),
                    encoding: .utf8
                )) ?? "{\"name\":\"\"}"
                mangaRows.append([
                    "id": mid,
                    "title": bm.mangaTitle,
                    "url": bm.mangaId,
                    "public_url": bm.mangaId,
                    "cover_url": bm.mangaCover ?? "",
                    "large_cover_url": bm.mangaCover ?? "",
                    "source_ref": sourceRef,
                    "updated_at": now
                ])
            }
        }
        let a = try await upsert(table: "nyora_manga", rows: mangaRows)
        let b = try await upsert(table: "nyora_bookmark", rows: bookmarkRows)
        return max(a, b)
    }

    /// Pulls `nyora_bookmark` into the local store, resolving the source and title/cover, honoring
    /// soft-delete tombstones.
    @discardableResult
    func pullBookmarks() async throws -> Int {
        let rows = try await select(table: "nyora_bookmark", since: nil)
        guard !rows.isEmpty else { return 0 }
        let mangaRows = try await select(table: "nyora_manga", since: nil)
        var mangaById: [String: [String: Any]] = [:]
        for row in mangaRows where row["id"] is String { mangaById[row["id"] as! String] = row }
        let sourceMap = installedSourceMap()

        var merged: [NyoraBookmark] = []
        var deletedIds = Set<String>()
        for row in rows {
            guard
                let mid = row["manga_id"] as? String, !mid.isEmpty,
                let chapterId = row["chapter_id"] as? String, !chapterId.isEmpty,
                let page = (row["page"] as? NSNumber)?.intValue
            else { continue }
            let (name, key) = Self.splitMangaId(mid)
            guard let sourceId = sourceMap[name], !key.isEmpty else { continue }
            let localId = "\(sourceId)\u{1}\(key)\u{1}\(chapterId)\u{1}\(page)"

            if (row["deleted_at"] as? String).map({ !$0.isEmpty }) ?? false {
                deletedIds.insert(localId)
                continue
            }
            let mrow = mangaById[mid]
            let created = (row["created_at"] as? String).flatMap { Self.iso.date(from: $0) } ?? Date()
            merged.append(NyoraBookmark(
                sourceId: sourceId,
                mangaId: key,
                mangaTitle: (mrow?["title"] as? String) ?? key,
                mangaCover: (mrow?["cover_url"] as? String) ?? (mrow?["large_cover_url"] as? String),
                chapterId: chapterId,
                chapterTitle: (row["chapter_title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                page: page,
                note: (row["note"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                imageUrl: (row["image_url"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                createdAt: created
            ))
        }
        NyoraBookmarkStore.shared.mergeIn(merged)
        NyoraBookmarkStore.shared.removeIDs(deletedIds)
        return merged.count
    }

    /// Runs a full push/pull cycle, coalescing overlapping callers onto a single in-flight
    /// task (see `inFlightSync`). Safe to call from multiple sites concurrently.
    @discardableResult
    func syncNow() async throws -> (pushed: Int, pulled: Int) {
        if let inFlightSync {
            return try await inFlightSync.value
        }
        let task = Task { try await self.performSync() }
        inFlightSync = task
        defer { inFlightSync = nil }
        return try await task.value
    }

    private func performSync() async throws -> (pushed: Int, pulled: Int) {
        // Pull first (LWW: remote → local), then push local state back.
        var pulled = 0
        var pushed = 0

        pulled += try await pullLibrary()
        pulled += try await pullCategories()
        pulled += try await pullMangaCategories()
        pulled += try await pullHistory()
        pulled += try await pullBookmarks()
        pulled += try await pullSourcePrefs()
        pulled += try await pullMangaPrefs()
        pulled += try await pullTracking()

        pushed += try await pushLibrary()
        pushed += try await pushCategories()
        pushed += try await pushMangaCategories()
        pushed += try await pushHistory()
        pushed += try await pushBookmarks()
        pushed += try await pushSourcePrefs()
        pushed += try await pushMangaPrefs()
        pushed += try await pushTracking()

        return (pushed, pulled)
    }

    // MARK: - Automatic sync

    /// Start syncing automatically: shortly after the app foregrounds, and (debounced) whenever the
    /// library or history changes. Mirrors android's on-change + periodic worker so reading a chapter
    /// or favouriting a title actually propagates without pressing "Sync now". Idempotent.
    func startAutoSync() {
        guard !autoSyncStarted else { return }
        autoSyncStarted = true
        let center = NotificationCenter.default
        for name in [Notification.Name.updateLibrary, .updateHistory, .historySet, .nyoraBookmarksChanged] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleAutoSync() }
            }
        }
        #if canImport(UIKit)
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleAutoSync(delay: 3) }
        }
        #endif
    }

    /// Debounce a full `syncNow()` so a burst of changes coalesces into one round-trip.
    private func scheduleAutoSync(delay: TimeInterval = 20) {
        guard isSignedIn else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.isSignedIn else { return }
            _ = try? await self.syncNow()
        }
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
