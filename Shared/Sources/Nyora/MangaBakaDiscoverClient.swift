//
//  MangaBakaDiscoverClient.swift
//  Aidoku (iOS) — Nyora fork
//
//  NX-002 — MangaBaka feed for Discover.
//
//  A tiny, auth-free client for the MangaBaka series database
//  (https://api.mangabaka.dev). It powers the Nyora Discover surface with a rich
//  multi-rail feed — Trending, Top Rated, Popular Manhwa and several genre rails.
//  MangaBaka's public API is search-first (there is NO trending/sort endpoint —
//  `sort=` is rejected), so each rail is a broad/filtered `series/search` that we
//  rank CLIENT-SIDE by popularity (or rating) and trim to the best entries.
//  Entries are mapped into `AidokuRunner.Manga` so the existing Discover
//  hero/rail/pager views render them directly. Covers come from MangaBaka's open
//  CDN so they load without per-source image request handling.
//
//  These entries are NOT tied to a real reader source (their `sourceKey` is the
//  synthetic ``MangaBakaDiscoverClient/sourceKey``): tapping one runs a universal
//  search of its title across the installed sources to find a readable copy.
//
//  NOTE: this is the discovery/suggestions data source only. The MangaBaka
//  *tracker* (Shared/Tracking/Trackers/mangabaka) is a separate, authenticated
//  surface with its own models — the `MangaBakaSeries`/`MangaBakaResponse` types
//  there have a different shape, so this file uses its own private Codable structs.
//

import AidokuRunner
import Foundation

/// Auth-free MangaBaka search client feeding the Discover screen.
actor MangaBakaDiscoverClient {
    static let shared = MangaBakaDiscoverClient()

    /// Synthetic source key marking a manga as a MangaBaka catalogue entry rather
    /// than an installed reader source.
    static let sourceKey = "mangabaka-discover"

    private let searchEndpoint = URL(string: "https://api.mangabaka.dev/v1/series/search")!

    /// A broad query token — MangaBaka search requires `q`, so this matches the
    /// bulk of the catalogue; we then rank the results ourselves.
    private static let broadQuery = "a"

    /// How a rail is ranked client-side (MangaBaka has no server-side sort).
    private enum SortBy {
        case popularity
        case rating
    }

    /// One ordered feed section (a Discover rail / the trending pager).
    struct Section: Sendable, Identifiable {
        let id: String
        let title: String
        let manga: [AidokuRunner.Manga]
    }

    /// One rail's MangaBaka search parameters.
    private struct RailSpec {
        let id: String
        let title: String
        let type: String
        let genre: String?
        let sortBy: SortBy
    }

    /// In-memory cache so re-entering Discover doesn't re-hit the network.
    private var feedCache: [Section]?

    /// The ordered set of Discover rails (mirrors the web Discover swap). The
    /// first entry ("trending") becomes the hero + pager; the rest render as
    /// horizontal rails. `type`/`genre` map to MangaBaka search filters; `sortBy`
    /// is the client-side ranking applied to the returned page.
    private static let spec: [RailSpec] = [
        RailSpec(id: "trending", title: "Trending", type: "manga", genre: nil, sortBy: .popularity),
        RailSpec(id: "topRated", title: "Top Rated", type: "manga", genre: nil, sortBy: .rating),
        RailSpec(id: "manhwa", title: "Popular Manhwa", type: "manhwa", genre: nil, sortBy: .popularity),
        RailSpec(id: "action", title: "Action", type: "manga", genre: "Action", sortBy: .popularity),
        RailSpec(id: "romance", title: "Romance", type: "manga", genre: "Romance", sortBy: .popularity),
        RailSpec(id: "fantasy", title: "Fantasy", type: "manga", genre: "Fantasy", sortBy: .popularity),
        RailSpec(id: "comedy", title: "Comedy", type: "manga", genre: "Comedy", sortBy: .popularity)
    ]

    /// The full ordered Discover feed (Trending, Top Rated, Popular Manhwa, genres…).
    func feed() async throws -> [Section] {
        if let feedCache { return feedCache }
        let sections = try await fetchFeed()
        // Every rail failing (offline / rate-limited) surfaces as an error + Retry
        // rather than a silent empty screen.
        guard !sections.isEmpty else { throw MangaBakaDiscoverError.empty }
        feedCache = sections
        return sections
    }

    // MARK: - Networking

    /// Fetch every rail concurrently. A single rail failing (network / rate) is
    /// swallowed to `[]` so the rest of the feed still renders; empty rails are
    /// dropped while preserving `spec` order.
    private func fetchFeed() async throws -> [Section] {
        let results: [String: [AidokuRunner.Manga]] = await withTaskGroup(
            of: (String, [AidokuRunner.Manga]).self
        ) { group in
            for spec in Self.spec {
                group.addTask {
                    let manga = (try? await Self.fetchRail(spec)) ?? []
                    return (spec.id, manga)
                }
            }
            var map: [String: [AidokuRunner.Manga]] = [:]
            for await (id, manga) in group {
                map[id] = manga
            }
            return map
        }

        // The per-rail tasks swallow cancellation to `[]` (via `try?`), which would
        // otherwise masquerade as an "empty" feed and surface a bogus error. If the
        // surrounding task was cancelled (e.g. the Discover view is briefly torn down
        // during the onboarding→main transition), throw `CancellationError` so the
        // caller can distinguish "cancelled, retry" from "genuinely empty".
        try Task.checkCancellation()

        return Self.spec.compactMap { spec in
            guard let manga = results[spec.id], !manga.isEmpty else { return nil }
            return Section(id: spec.id, title: spec.title, manga: manga)
        }
    }

    /// One MangaBaka search → a quality-filtered, client-side-ranked rail.
    private static func fetchRail(_ spec: RailSpec) async throws -> [AidokuRunner.Manga] {
        var components = URLComponents(string: "https://api.mangabaka.dev/v1/series/search")!
        var items = [
            URLQueryItem(name: "q", value: broadQuery),
            URLQueryItem(name: "type", value: spec.type),
            URLQueryItem(name: "content_rating", value: "safe"),
            URLQueryItem(name: "limit", value: "30")
        ]
        if let genre = spec.genre {
            items.append(URLQueryItem(name: "genre", value: genre))
        }
        components.queryItems = items

        guard let url = components.url else { throw MangaBakaDiscoverError.badStatus(-1) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MangaBakaDiscoverError.badStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        let usable = (decoded.data ?? []).filter { $0.isUsable }
        let ranked = usable.sorted { lhs, rhs in
            switch spec.sortBy {
                case .popularity: lhs.popularityScore > rhs.popularityScore
                case .rating: lhs.ratingScore > rhs.ratingScore
            }
        }
        return ranked.prefix(20).compactMap { $0.toManga() }
    }

    enum MangaBakaDiscoverError: Error {
        case badStatus(Int)
        case empty
    }
}

// MARK: - Response mapping

/// MangaBaka `series/search` response. Private to this file so it doesn't collide
/// with the tracker's differently-shaped `MangaBakaSeries`/`MangaBakaResponse`.
private struct SearchResponse: Decodable {
    let data: [Series]?

    struct Series: Decodable {
        let id: Int
        let title: String?
        let romanizedTitle: String?
        let nativeTitle: String?
        let cover: Cover?
        let genres: [String]?
        let rating: Double?
        let popularity: Popularity?
        let state: String?
        let description: String?

        enum CodingKeys: String, CodingKey {
            case id, title
            case romanizedTitle = "romanized_title"
            case nativeTitle = "native_title"
            case cover, genres, rating, popularity, state, description
        }

        struct Cover: Decodable {
            let x350: Variant?
            let x250: Variant?
            let raw: Raw?

            struct Variant: Decodable { let x1: String? }
            struct Raw: Decodable { let url: String? }
        }

        struct Popularity: Decodable {
            let global: Global?
            struct Global: Decodable { let current: Double? }
        }

        /// Best available title: display → romanized → native.
        var bestTitle: String? {
            for candidate in [title, romanizedTitle, nativeTitle] {
                if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return candidate
                }
            }
            return nil
        }

        /// Best available cover: CDN thumbnails first, then the raw image.
        var bestCover: String? {
            for candidate in [cover?.x350?.x1, cover?.x250?.x1, cover?.raw?.url] {
                if let candidate, !candidate.isEmpty { return candidate }
            }
            return nil
        }

        /// Sortable global-popularity number (0 when absent).
        var popularityScore: Double { popularity?.global?.current ?? 0 }

        /// Sortable rating (0..100, 0 when absent).
        var ratingScore: Double { rating ?? 0 }

        /// Worth showing only with a cover and a real title — the DB is full of
        /// 1–2 char placeholder entries and merged duplicates we drop.
        var isUsable: Bool {
            state != "merged"
                && bestCover != nil
                && (bestTitle?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) >= 3
        }

        /// Map a MangaBaka series into an `AidokuRunner.Manga`. Returns nil when
        /// there is no usable title, so the feed never shows blank cards.
        func toManga() -> AidokuRunner.Manga? {
            guard let name = bestTitle else { return nil }
            let tags = (genres ?? []).map { $0.prettyGenre }.prefix(6)
            return AidokuRunner.Manga(
                sourceKey: MangaBakaDiscoverClient.sourceKey,
                key: String(id),
                title: name,
                cover: bestCover,
                description: description?.trimmingCharacters(in: .whitespacesAndNewlines),
                url: URL(string: "https://mangabaka.org/series/\(id)"),
                tags: Array(tags)
            )
        }
    }
}

private extension String {
    /// "school_life" -> "School Life"
    var prettyGenre: String {
        split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
