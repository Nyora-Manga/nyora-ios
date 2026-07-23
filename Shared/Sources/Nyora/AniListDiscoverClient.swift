//
//  AniListDiscoverClient.swift
//  Aidoku (iOS) — Nyora fork
//
//  Discover feed source, ported 1:1 from nyora-web (web/core/discover-feed.js +
//  screens/discover.js). AniList is the PRIMARY source: a single GraphQL POST to
//  https://graphql.anilist.co builds the whole feed (trending + country/genre rails).
//  MangaBaka is the FALLBACK, used only on a cold start when AniList is unreachable
//  and there is no cache (mirrors the web app's fetch order).
//
//  Discover entries are metadata only — not tied to a readable source. Tapping one
//  runs a universal search of its title across the installed sources.
//

import Foundation

// MARK: - Models (the neutral "AniList-shaped" discover item both sources map into)

/// One discover entry (an AniList `Media`, or a MangaBaka series mapped into the same shape).
struct DiscoverItem: Identifiable, Sendable, Hashable {
    let id: String          // "anilist:123" / a MangaBaka id
    let title: String
    let cover: String?
    let banner: String?     // AniList bannerImage; nil for MangaBaka (hero falls back to cover)
    let genres: [String]
    let score: Int?         // averageScore, 0…100
}

/// One ordered feed section (a Discover rail; the first is "trending" → hero + rail).
struct DiscoverSection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [DiscoverItem]
}

/// AniList-primary, MangaBaka-fallback Discover feed client.
actor AniListDiscoverClient {
    static let shared = AniListDiscoverClient()

    /// Synthetic source key marking a discover entry as metadata, not an installed reader source.
    static let sourceKey = "anilist-discover"

    // Cache: served as-is while fresh; painted (and revalidated) while within maxAge (web parity).
    private var cache: (at: Date, sections: [DiscoverSection])?
    private static let freshTTL: TimeInterval = 15 * 60          // 15 minutes
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60   // 7 days

    /// Rail definitions in render order — exactly the 7 aliased AniList pages the web app queries.
    private struct RailDef {
        let key: String
        let title: String
        let filter: String   // extra `media(...)` args, e.g. `countryOfOrigin: KR, `
        let sort: String     // AniList MediaSort
    }
    private static let rails: [RailDef] = [
        RailDef(key: "trending", title: "Trending now", filter: "", sort: "TRENDING_DESC"),
        RailDef(key: "manhwa", title: "Popular Manhwa", filter: "countryOfOrigin: KR, ", sort: "POPULARITY_DESC"),
        RailDef(key: "manhua", title: "Popular Manhua", filter: "countryOfOrigin: CN, ", sort: "POPULARITY_DESC"),
        RailDef(key: "manga", title: "Popular Manga", filter: "countryOfOrigin: JP, ", sort: "POPULARITY_DESC"),
        RailDef(key: "action", title: "Action", filter: "genre: \"Action\", ", sort: "TRENDING_DESC"),
        RailDef(key: "romance", title: "Romance", filter: "genre: \"Romance\", ", sort: "TRENDING_DESC"),
        RailDef(key: "fantasy", title: "Fantasy", filter: "genre: \"Fantasy\", ", sort: "TRENDING_DESC"),
    ]

    enum DiscoverError: Error { case badStatus(Int); case empty }

    /// The full ordered Discover feed. AniList first (cached 15 min fresh / 7 day stale-while-revalidate);
    /// MangaBaka only as a cold-start fallback.
    func feed() async throws -> [DiscoverSection] {
        if let cache, Date().timeIntervalSince(cache.at) < Self.freshTTL {
            return cache.sections
        }
        do {
            let byKey = try await fetchAniList()
            let sections = assemble(byKey)
            if sections.contains(where: { !$0.items.isEmpty }) {
                cache = (Date(), sections)
                return sections
            }
            // AniList answered but empty — fall through to stale cache / MangaBaka.
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let stale = staleCache() { return stale }
        }
        if let stale = staleCache() { return stale }

        // Cold start with AniList down → MangaBaka fallback.
        let sections = try await fetchMangaBakaFallback()
        guard sections.contains(where: { !$0.items.isEmpty }) else { throw DiscoverError.empty }
        return sections
    }

    private func staleCache() -> [DiscoverSection]? {
        guard let cache, Date().timeIntervalSince(cache.at) < Self.maxAge else { return nil }
        return cache.sections
    }

    private func assemble(_ byKey: [String: [DiscoverItem]]) -> [DiscoverSection] {
        Self.rails.compactMap { def in
            let items = byKey[def.key] ?? []
            guard !items.isEmpty else { return nil }
            return DiscoverSection(id: def.key, title: def.title, items: items)
        }
    }

    // MARK: - AniList (primary)

    private func fetchAniList() async throws -> [String: [DiscoverItem]] {
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["query": Self.buildQuery()])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DiscoverError.badStatus(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(AniListResponse.self, from: data)
        guard let payload = decoded.data else { throw DiscoverError.empty }

        var out: [String: [DiscoverItem]] = [:]
        for def in Self.rails {
            out[def.key] = (payload.page(def.key)?.media ?? []).compactMap { $0.toItem() }
        }
        return out
    }

    /// The 7-alias AniList query — `type: MANGA, isAdult: false`, `perPage: 30`, filters/sorts inlined.
    private static func buildQuery() -> String {
        let fields = "id title { romaji english native } coverImage { large extraLarge } "
            + "bannerImage genres averageScore countryOfOrigin"
        let pages = rails.map { def in
            "\(def.key): Page(perPage: 30) { media(type: MANGA, isAdult: false, \(def.filter)sort: \(def.sort)) { \(fields) } }"
        }.joined(separator: "\n  ")
        return "query {\n  \(pages)\n}"
    }

    // MARK: - MangaBaka (fallback)

    /// Reuse the proven search-based MangaBaka client, mapped into the discover shape.
    private func fetchMangaBakaFallback() async throws -> [DiscoverSection] {
        let sections = try await MangaBakaDiscoverClient.shared.feed()
        return sections.map { section in
            DiscoverSection(
                id: section.id,
                title: section.title,
                items: section.manga.map { manga in
                    DiscoverItem(
                        id: manga.key,
                        title: manga.title,
                        cover: manga.cover,
                        banner: nil,
                        genres: manga.tags ?? [],
                        score: nil
                    )
                }
            )
        }
    }
}

// MARK: - AniList wire models (aliased Page fields)

private struct AniListResponse: Decodable {
    let data: DataObject?

    struct DataObject: Decodable {
        let trending: Page?
        let manhwa: Page?
        let manhua: Page?
        let manga: Page?
        let action: Page?
        let romance: Page?
        let fantasy: Page?

        func page(_ key: String) -> Page? {
            switch key {
                case "trending": trending
                case "manhwa": manhwa
                case "manhua": manhua
                case "manga": manga
                case "action": action
                case "romance": romance
                case "fantasy": fantasy
                default: nil
            }
        }
    }

    struct Page: Decodable { let media: [Media]? }

    struct Media: Decodable {
        let id: Int
        let title: Title?
        let coverImage: CoverImage?
        let bannerImage: String?
        let genres: [String]?
        let averageScore: Int?

        struct Title: Decodable {
            let romaji: String?
            let english: String?
            let native: String?
        }
        struct CoverImage: Decodable {
            let large: String?
            let extraLarge: String?
        }

        private var preferredTitle: String {
            title?.english ?? title?.romaji ?? title?.native ?? "Untitled"
        }
        private var bestCover: String? {
            coverImage?.extraLarge ?? coverImage?.large
        }

        /// Drop entries without a usable cover (web `mediaUsable`).
        func toItem() -> DiscoverItem? {
            guard let cover = bestCover, !cover.isEmpty else { return nil }
            return DiscoverItem(
                id: "anilist:\(id)",
                title: preferredTitle,
                cover: cover,
                banner: bannerImage,
                genres: genres ?? [],
                score: averageScore
            )
        }
    }
}
