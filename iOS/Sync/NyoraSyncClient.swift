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

    @discardableResult
    func syncNow() async throws -> (pushed: Int, pulled: Int) {
        let pulled = try await pullLibrary()
        let pushed = try await pushLibrary()
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
