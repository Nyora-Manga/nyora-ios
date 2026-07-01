//
//  AniListClient.swift
//  Aidoku (iOS) — Nyora fork
//
//  NX-002 — AniList feed for Discover.
//
//  A tiny, auth-free client for the AniList GraphQL API (https://graphql.anilist.co).
//  It powers the Nyora Discover surface: a "Trending" and a "Popular" manga list
//  sourced from AniList rather than from an installed reader source. Entries are
//  mapped into `AidokuRunner.Manga` so the existing Discover hero/rail/pager views
//  can render them directly. Covers come from AniList's open CDN (s4.anilist.co)
//  so they load without any per-source image request modification.
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
    /// than an installed reader source. Discover uses this to route taps through
    /// a universal search instead of opening the (non-existent) source directly.
    static let sourceKey = "anilist"

    private let endpoint = URL(string: "https://graphql.anilist.co")!

    /// Simple in-memory cache so re-entering Discover doesn't re-hit the network.
    private var trendingCache: [AidokuRunner.Manga]?
    private var popularCache: [AidokuRunner.Manga]?

    /// Top trending manga (AniList `TRENDING_DESC`).
    func trending() async throws -> [AidokuRunner.Manga] {
        if let trendingCache { return trendingCache }
        let result = try await fetch(sort: "TRENDING_DESC")
        trendingCache = result
        return result
    }

    /// Most popular manga (AniList `POPULARITY_DESC`).
    func popular() async throws -> [AidokuRunner.Manga] {
        if let popularCache { return popularCache }
        let result = try await fetch(sort: "POPULARITY_DESC")
        popularCache = result
        return result
    }

    // MARK: - Networking

    private static let query = """
    query ($sort: [MediaSort]) {
      Page(page: 1, perPage: 25) {
        media(type: MANGA, sort: $sort, isAdult: false) {
          id
          title { english romaji }
          coverImage { large }
          genres
          description(asHtml: false)
          siteUrl
        }
      }
    }
    """

    private func fetch(sort: String) async throws -> [AidokuRunner.Manga] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "query": Self.query,
            "variables": ["sort": [sort]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AniListError.badStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(AniListResponse.self, from: data)
        return decoded.data.page.media.compactMap { $0.toManga() }
    }

    enum AniListError: Error {
        case badStatus(Int)
    }
}

// MARK: - Response mapping

private struct AniListResponse: Decodable {
    let data: DataField

    struct DataField: Decodable {
        let page: Page

        enum CodingKeys: String, CodingKey {
            case page = "Page"
        }
    }

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
    /// notes). Strip tags and collapse whitespace so the recommendation card gets
    /// clean plain text.
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
