//
//  AniListClient.swift
//  Aidoku (iOS) — Nyora fork
//
//  NX-002 — AniList feed for Discover.
//
//  A tiny, auth-free client for the AniList GraphQL API (https://graphql.anilist.co).
//  It powers the Nyora Discover surface with a rich multi-rail feed — Trending,
//  Popular, Top Rated and several genre rails — fetched in a SINGLE request via
//  GraphQL field aliases (so it stays one network call, no rate-limit risk).
//  Entries are mapped into `AidokuRunner.Manga` so the existing Discover
//  hero/rail/pager views render them directly. Covers come from AniList's open
//  CDN (s4.anilist.co) so they load without per-source image request handling.
//
//  These entries are NOT tied to a real reader source (their `sourceKey` is the
//  synthetic ``AniListClient/sourceKey``): tapping one runs a universal search of
//  its title across the installed sources to find a readable copy.
//

import AidokuRunner
import Foundation

/// Auth-free AniList GraphQL client feeding the Discover screen.
actor AniListClient {
    static let shared = AniListClient()

    /// Synthetic source key marking a manga as an AniList catalogue entry rather
    /// than an installed reader source.
    static let sourceKey = "anilist"

    private let endpoint = URL(string: "https://graphql.anilist.co")!

    /// One ordered feed section (a Discover rail / the trending pager).
    struct Section: Sendable, Identifiable {
        let id: String
        let title: String
        let manga: [AidokuRunner.Manga]
    }

    /// In-memory cache so re-entering Discover doesn't re-hit the network.
    private var feedCache: [Section]?

    /// The ordered set of Discover sections. `alias` is the GraphQL field alias,
    /// `args` the `media(...)` filter. First entry ("trending") becomes the
    /// hero + pager; the rest render as horizontal rails.
    private static let spec: [(alias: String, title: String, args: String)] = [
        ("trending", "Trending", "sort: TRENDING_DESC"),
        ("popular", "Popular", "sort: POPULARITY_DESC"),
        ("topRated", "Top Rated", "sort: SCORE_DESC"),
        ("action", "Action", "genre_in: [\"Action\"], sort: POPULARITY_DESC"),
        ("romance", "Romance", "genre_in: [\"Romance\"], sort: POPULARITY_DESC"),
        ("fantasy", "Fantasy", "genre_in: [\"Fantasy\"], sort: POPULARITY_DESC"),
        ("comedy", "Comedy", "genre_in: [\"Comedy\"], sort: POPULARITY_DESC"),
        ("adventure", "Adventure", "genre_in: [\"Adventure\"], sort: POPULARITY_DESC"),
        ("drama", "Drama", "genre_in: [\"Drama\"], sort: POPULARITY_DESC")
    ]

    private static let mediaFields =
        "id title { english romaji } coverImage { large } genres description(asHtml: false) siteUrl"

    /// The full ordered Discover feed (Trending, Popular, Top Rated, genres…).
    func feed() async throws -> [Section] {
        if let feedCache { return feedCache }
        let sections = try await fetchFeed()
        feedCache = sections
        return sections
    }

    // MARK: - Networking

    private func buildQuery() -> String {
        let blocks = Self.spec.map { spec in
            "\(spec.alias): Page(page: 1, perPage: 15) { "
                + "media(type: MANGA, isAdult: false, \(spec.args)) { \(Self.mediaFields) } }"
        }.joined(separator: "\n  ")
        return "query {\n  \(blocks)\n}"
    }

    /// Fetch with a few retries — AniList rate-limits (~90 req/min → 429) and the
    /// odd network blip would otherwise surface as "Unknown Error" on Discover.
    private func fetchFeed() async throws -> [Section] {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await performFeedFetch()
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 800_000_000)
            }
        }
        throw lastError ?? AniListError.badStatus(-1)
    }

    private func performFeedFetch() async throws -> [Section] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": buildQuery()])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AniListError.badStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(FeedResponse.self, from: data)
        // Preserve the spec order; drop any section that came back empty.
        return Self.spec.compactMap { spec in
            guard let page = decoded.data[spec.alias] else { return nil }
            let manga = page.media.compactMap { $0.toManga() }
            return manga.isEmpty ? nil : Section(id: spec.alias, title: spec.title, manga: manga)
        }
    }

    enum AniListError: Error {
        case badStatus(Int)
    }
}

// MARK: - Response mapping

private struct FeedResponse: Decodable {
    /// Keyed by the section alias (trending, popular, action, …).
    let data: [String: Page]

    struct Page: Decodable {
        let media: [Media]
    }

    struct Media: Decodable {
        let id: Int
        let title: Title
        let coverImage: CoverImage?
        let genres: [String]?
        let description: String?
        let siteUrl: String?

        struct Title: Decodable {
            let english: String?
            let romaji: String?
        }

        struct CoverImage: Decodable {
            let large: String?
        }

        /// Map an AniList media node into an `AidokuRunner.Manga`. Returns nil when
        /// there is no usable title, so the feed never shows blank cards.
        func toManga() -> AidokuRunner.Manga? {
            let name = title.english ?? title.romaji
            guard let name, !name.isEmpty else { return nil }
            return AidokuRunner.Manga(
                sourceKey: AniListClient.sourceKey,
                key: String(id),
                title: name,
                cover: coverImage?.large,
                description: description?.strippedAniListDescription,
                url: siteUrl.flatMap { URL(string: $0) },
                tags: genres
            )
        }
    }
}

private extension String {
    /// AniList descriptions carry lightweight HTML (`<br>`, `<i>`, `<b>`, source
    /// notes). Strip tags and collapse whitespace so cards get clean plain text.
    var strippedAniListDescription: String {
        let withoutTags = replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let collapsed = withoutTags.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
