//
//  NyoraSource.swift
//  Aidoku
//
//  A pure-Swift REST runner that backs an Aidoku source with the hosted Nyora
//  parser helper (e.g. https://api.hasanraza.tech). One Aidoku "Nyora" source
//  aggregates the helper's ~960 parser sources: each parser source is exposed
//  as a Listing, global search spans all of them, and the underlying parser
//  source id is carried inside each manga's `key` (there's no side channel in
//  the Runner API). Modeled on KomgaSourceRunner.
//

import AidokuRunner
import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Source factory

extension AidokuRunner.Source {
    static func nyora(
        key: String = "nyora",
        name: String = "Nyora",
        server: String
    ) -> AidokuRunner.Source {
        .init(
            // `url` must be nil (or a package path with ≥2 path components) — it is
            // used by SourceObject.load as a file path, NOT the server. A bare host
            // URL has 0 path components and crashes there. Server lives in `urls` +
            // the runner. (Komga does the same.)
            url: nil,
            key: key,
            name: name,
            version: 1,
            languages: ["multi"],
            urls: URL(string: server).map { [$0] } ?? [],
            contentRating: .safe,
            config: .init(
                languageSelectType: .single,
                supportsTagSearch: false
            ),
            staticListings: [],
            staticFilters: [],
            runner: NyoraSourceRunner(sourceKey: key, name: name, server: server)
        )
    }
}

// MARK: - Runner

actor NyoraSourceRunner: Runner {
    static let sourceKeyPrefix = "nyora"

    /// Separates the parser source id from the manga url inside a manga `key`.
    /// A control char that never appears in a source id or url.
    static let keyDelimiter = "\u{1}"

    let sourceKey: String
    private let name: String
    private let helper: NyoraHelper

    /// Cached mapping of parser source id -> language code, populated from the catalog.
    /// Used to derive a title's translation language for the details header.
    private var sourceLangs: [String: String] = [:]

    let features = SourceFeatures(
        providesListings: true,
        providesHome: true,
        dynamicListings: true,
        providesImageRequests: true,
        providesBaseUrl: true
    )

    /// A small, hand-picked set of well-behaved parser sources surfaced on the
    /// Home screen and as browse listing tabs. The helper aggregates ~960 parser
    /// sources, but exposing every one as a listing tab produces an unusable
    /// wall of ~960 chips. Discovery across *all* sources still happens through
    /// global search (`getSearchMangaList`); these featured sources just give
    /// Browse a clean, curated landing that's usable out of the box.
    static let featuredSources: [(id: String, name: String)] = [
        ("parser:MANGADEX", "MangaDex"),
        ("parser:TOONILY", "Toonily"),
        ("parser:MANHWAZ", "ManhwaZ"),
        ("parser:ANISASCANS", "AnisaScans"),
        ("parser:UTOON", "UToon"),
        ("parser:MANGAGG", "MangaGg"),
        ("parser:HMANGABAT", "MangaBat"),
        ("parser:ISEKAISCAN", "IsekaiScan")
    ]

    init(sourceKey: String, name: String, server: String) {
        self.sourceKey = sourceKey
        self.name = name
        self.helper = NyoraHelper(server: URL(string: server) ?? URL(string: "https://api.hasanraza.tech")!)
    }

    // MARK: Browse

    func getListings() async throws -> [AidokuRunner.Listing] {
        // Only the curated featured sources become listing tabs — surfacing all
        // ~960 helper catalog entries here made Browse an unusable tab wall.
        // Global search still spans every source. The catalog (for the details
        // header's translation language) is fetched lazily in `languageCode`.
        Self.featuredSources.map { .init(id: $0.id, name: $0.name, kind: .default) }
    }

    /// Outcome of fetching one featured source's popular list for the Home.
    private enum HomeFetchOutcome: Sendable {
        case component(AidokuRunner.HomeComponent) // succeeded, has entries
        case empty                                 // succeeded but no entries (or all NSFW-filtered)
        case failed                                // request threw (network/backend error)
    }

    /// Home screen: one horizontal "popular" scroller per curated featured
    /// source. Sources are fetched concurrently and any that individually error
    /// or return nothing are dropped, so a single flaky parser never blanks the
    /// whole Home. But if *every* featured source fails (e.g. the backend is
    /// down or offline), we throw so the UI shows an error + retry instead of a
    /// silent blank Home. Tapping "more" on a scroller opens that source's listing.
    func getHome() async throws -> AidokuRunner.Home {
        let sources = Self.featuredSources
        var outcomes: [HomeFetchOutcome] = Array(repeating: .failed, count: sources.count)

        await withTaskGroup(of: (Int, HomeFetchOutcome).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask { [helper, sourceKey] in
                    do {
                        let res: NyoraBrowseResponse = try await helper.get(
                            "sources/popular",
                            items: [.init(name: "id", value: source.id), .init(name: "page", value: "1")]
                        )
                        let manga = self.filteringNsfw(
                            res.entries.map { $0.intoManga(sourceKey: sourceKey, parserSource: source.id, helper: helper) }
                        )
                        guard !manga.isEmpty else { return (index, .empty) }
                        let listing = AidokuRunner.Listing(id: source.id, name: source.name, kind: .default)
                        let component = AidokuRunner.HomeComponent(
                            title: source.name,
                            value: .scroller(entries: manga.map { $0.intoLink() }, listing: listing)
                        )
                        return (index, .component(component))
                    } catch {
                        return (index, .failed)
                    }
                }
            }
            for await (index, outcome) in group {
                outcomes[index] = outcome
            }
        }

        // If every featured source errored (not merely returned empty), the
        // backend is unreachable — surface it so the UI offers a retry.
        if !sources.isEmpty && outcomes.allSatisfy({ if case .failed = $0 { true } else { false } }) {
            throw SourceError.message("REQUEST_FAILED")
        }

        let components = outcomes.compactMap { outcome -> AidokuRunner.HomeComponent? in
            if case let .component(component) = outcome { component } else { nil }
        }
        return .init(components: components)
    }

    private func cacheSourceLangs(_ entries: [NyoraCatalogEntry]) {
        for entry in entries where !entry.lang.isEmpty {
            sourceLangs[entry.id] = entry.lang
        }
    }

    /// Language code for a parser source, fetching (and caching) the catalog on first miss.
    private func languageCode(for parserSource: String) async -> String? {
        if let lang = sourceLangs[parserSource] { return lang }
        if let catalog: NyoraCatalogResponse = try? await helper.get("sources/catalog") {
            cacheSourceLangs(catalog.entries)
        }
        return sourceLangs[parserSource]
    }

    /// When the global "disable NSFW content" toggle is on, drops any manga
    /// flagged `.nsfw` so it never appears in browse/search results.
    /// Mirrors android `AppSettings.isNsfwContentDisabled`.
    private nonisolated func filteringNsfw(_ entries: [AidokuRunner.Manga]) -> [AidokuRunner.Manga] {
        guard UserDefaults.standard.bool(forKey: "Sources.disableNsfw") else { return entries }
        return entries.filter { $0.contentRating != .nsfw }
    }

    func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
        let res: NyoraBrowseResponse = try await helper.get(
            "sources/popular",
            items: [.init(name: "id", value: listing.id), .init(name: "page", value: String(page))]
        )
        return .init(
            entries: filteringNsfw(res.entries.map { $0.intoManga(sourceKey: sourceKey, parserSource: listing.id, helper: helper) }),
            hasNextPage: res.hasNextPage
        )
    }

    func getSearchMangaList(
        query: String?,
        page: Int,
        filters _: [AidokuRunner.FilterValue]
    ) async throws -> AidokuRunner.MangaPageResult {
        guard let query, !query.isEmpty else {
            // No query and no listing selected — nothing to show. Browsing is
            // driven through listings (per parser source) instead.
            return .init(entries: [], hasNextPage: false)
        }
        // Global search spans every installed parser source; single page.
        guard page == 1 else { return .init(entries: [], hasNextPage: false) }
        let res: NyoraGlobalSearchResponse = try await helper.get(
            "search/global",
            items: [.init(name: "q", value: query), .init(name: "limit", value: "10")]
        )

        // The helper fans a query out across ~67 matching parser sources, so a
        // popular title (e.g. "One Piece" → 25 copies) comes back dozens of
        // times across the groups. Left flat, the primary discovery surface is
        // an unusable wall of duplicate covers with no quality ordering.
        //
        // 1. Order the groups so curated featured sources surface first (stable
        //    otherwise), giving a deterministic, quality-first ordering.
        // 2. Collapse identical titles down to their first (highest-priority)
        //    occurrence so each title appears once, from the best source.
        // Each entry's key still carries its own parser source id, so opening a
        // result and reading it is unaffected.
        let featuredRank = Dictionary(
            uniqueKeysWithValues: Self.featuredSources.enumerated().map { ($0.element.id, $0.offset) }
        )
        let orderedGroups = res.groups
            .enumerated()
            .sorted { lhs, rhs in
                let lhsRank = featuredRank[lhs.element.sourceId] ?? Int.max
                let rhsRank = featuredRank[rhs.element.sourceId] ?? Int.max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.offset < rhs.offset // keep the helper's order stable within a tier
            }
            .map { $0.element }

        var seenTitles = Set<String>()
        let entries = orderedGroups
            .flatMap { group in
                group.entries.map { $0.intoManga(sourceKey: sourceKey, parserSource: group.sourceId, helper: helper) }
            }
            .filter { manga in
                let normalized = manga.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return true }
                return seenTitles.insert(normalized).inserted
            }
        return .init(entries: filteringNsfw(entries), hasNextPage: false)
    }

    // MARK: Details / pages

    func getMangaUpdate(
        manga: AidokuRunner.Manga,
        needsDetails: Bool,
        needsChapters: Bool
    ) async throws -> AidokuRunner.Manga {
        guard needsDetails || needsChapters else { return manga }
        let (parserSource, mangaUrl) = Self.splitKey(manga.key)
        let res: NyoraDetailsResponse = try await helper.get(
            "manga/details",
            items: [.init(name: "id", value: parserSource), .init(name: "url", value: mangaUrl)]
        )
        var updated = manga
        if needsDetails {
            // Stash alternate titles in the side store (the Manga model has no field for them).
            NyoraAltTitleStore.shared.set(res.manga.altTitles ?? [], for: manga.key)
            // Stash the numeric rating too (the Manga model only has a content-rating enum).
            NyoraRatingStore.shared.set(res.manga.rating, for: manga.key)
            // Stash the translation language derived from the parser source's catalog lang.
            NyoraLanguageStore.shared.set(await languageCode(for: parserSource), for: manga.key)
            let mapped = res.manga.intoManga(sourceKey: sourceKey, parserSource: parserSource, helper: helper)
            // Rebuild with the original encoded key preserved (it carries the
            // parser source id needed by later detail/page calls).
            updated = AidokuRunner.Manga(
                sourceKey: sourceKey,
                key: manga.key,
                title: mapped.title,
                cover: mapped.cover,
                artists: mapped.artists,
                authors: mapped.authors,
                description: mapped.description,
                url: mapped.url,
                tags: mapped.tags,
                status: mapped.status,
                contentRating: mapped.contentRating,
                viewer: mapped.viewer,
                chapters: manga.chapters
            )
        }
        if needsChapters {
            updated.chapters = res.chapters.map { $0.intoChapter(helper: helper) }
        }
        return updated
    }

    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        let (parserSource, _) = Self.splitKey(manga.key)
        let res: NyoraPagesResponse = try await helper.get(
            "manga/pages",
            items: [.init(name: "id", value: parserSource), .init(name: "url", value: chapter.key)]
        )
        return res.pages.compactMap { page in
            guard let url = URL(string: helper.rewriteImageHost(page.url)) else { return nil }
            return .init(content: .url(url: url))
        }
    }

    // MARK: Images

    func getImageRequest(url: String, context _: PageContext?) async throws -> URLRequest {
        // Covers and pages are already rewritten to <server>/image?u=…&h=… at
        // mapping time; the helper performs the upstream fetch with the right
        // headers, so the client just GETs the proxied URL.
        guard let url = URL(string: helper.rewriteImageHost(url)) else {
            throw SourceError.message("INVALID_URL")
        }
        return URLRequest(url: url)
    }

    func getBaseUrl() async throws -> URL? {
        helper.server
    }

    // MARK: Key encoding

    static func makeKey(parserSource: String, mangaUrl: String) -> String {
        "\(parserSource)\(keyDelimiter)\(mangaUrl)"
    }

    static func splitKey(_ key: String) -> (parserSource: String, mangaUrl: String) {
        if let range = key.range(of: keyDelimiter) {
            return (String(key[..<range.lowerBound]), String(key[range.upperBound...]))
        }
        return ("", key)
    }
}

// MARK: - HTTP helper

actor NyoraHelper {
    let server: URL

    init(server: URL) {
        self.server = server
    }

    func get<T: Decodable & Sendable>(_ path: String, items: [URLQueryItem] = []) async throws -> T {
        guard
            var comps = URLComponents(url: server.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw SourceError.message("INVALID_URL") }
        comps.queryItems = items.isEmpty ? nil : items
        guard let url = comps.url else { throw SourceError.message("INVALID_URL") }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // The helper returns {"error": "..."} on failure.
            if let err = try? JSONDecoder().decode(NyoraErrorResponse.self, from: data) {
                throw SourceError.message(err.error)
            }
            throw SourceError.message("REQUEST_FAILED")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// The helper rewrites cover/page URLs to its own loopback proxy
    /// (`http://127.0.0.1:<port>/image?u=…`). Since we reach it over a public
    /// domain, swap that local base for the configured server, preserving the
    /// `/image?u=…&h=…` path+query. Port-agnostic.
    nonisolated func rewriteImageHost(_ raw: String) -> String {
        guard let range = raw.range(of: "/image?u=") else { return raw }
        let base = server.absoluteString.hasSuffix("/")
            ? String(server.absoluteString.dropLast())
            : server.absoluteString
        return base + raw[range.lowerBound...]
    }
}

// MARK: - Wire models

private struct NyoraErrorResponse: Decodable, Sendable {
    let error: String
}

private struct NyoraTag: Decodable, Sendable {
    let key: String?
    let title: String
}

private struct NyoraManga: Decodable, Sendable {
    let id: String
    let title: String
    let altTitles: [String]?
    let url: String?
    let coverUrl: String?
    let authors: [String]?
    let description: String?
    let rating: Float?
    let isNsfw: Bool?
    let contentRating: String?
    let state: String?
    let tags: [NyoraTag]?
}

private struct NyoraChapter: Decodable, Sendable {
    let id: String
    let title: String
    let number: Float?
    let volume: Int?
    let url: String?
    let scanlator: String?
    let uploadDate: Int64?
    let branch: String?
}

private struct NyoraPage: Decodable, Sendable {
    let url: String
    let headers: [String: String]?
}

private struct NyoraCatalogEntry: Decodable, Sendable {
    let id: String
    let name: String
    let lang: String
}

private struct NyoraCatalogResponse: Decodable, Sendable {
    let entries: [NyoraCatalogEntry]
}

private struct NyoraBrowseResponse: Decodable, Sendable {
    let entries: [NyoraManga]
    let hasNextPage: Bool
}

private struct NyoraDetailsResponse: Decodable, Sendable {
    let manga: NyoraManga
    let chapters: [NyoraChapter]
}

private struct NyoraPagesResponse: Decodable, Sendable {
    let pages: [NyoraPage]
}

private struct NyoraGlobalSearchGroup: Decodable, Sendable {
    let sourceId: String
    let sourceName: String
    let entries: [NyoraManga]
    let error: String?
}

private struct NyoraGlobalSearchResponse: Decodable, Sendable {
    let query: String
    let groups: [NyoraGlobalSearchGroup]
}

// MARK: - Mappers

private extension NyoraManga {
    func intoManga(sourceKey: String, parserSource: String, helper: NyoraHelper) -> AidokuRunner.Manga {
        let status: AidokuRunner.PublishingStatus = switch (state ?? "").uppercased() {
            case "ONGOING": .ongoing
            case "FINISHED": .completed
            case "ABANDONED": .cancelled
            case "PAUSED": .hiatus
            default: .unknown
        }
        let rating: AidokuRunner.ContentRating = {
            if isNsfw == true { return .nsfw }
            switch (contentRating ?? "").uppercased() {
                case "ADULT": return .nsfw
                case "SUGGESTIVE": return .suggestive
                case "SAFE": return .safe
                default: return .unknown
            }
        }()
        return .init(
            sourceKey: sourceKey,
            key: NyoraSourceRunner.makeKey(parserSource: parserSource, mangaUrl: url ?? id),
            title: title,
            cover: coverUrl.map { helper.rewriteImageHost($0) },
            authors: authors,
            description: description,
            url: url.flatMap { URL(string: $0) },
            tags: tags?.map { $0.title },
            status: status,
            contentRating: rating
        )
    }
}

private extension NyoraChapter {
    func intoChapter(helper: NyoraHelper) -> AidokuRunner.Chapter {
        .init(
            key: url ?? id,
            title: title.isEmpty ? nil : title,
            chapterNumber: number,
            volumeNumber: volume.map(Float.init),
            dateUploaded: uploadDate.flatMap { $0 > 0 ? Date(timeIntervalSince1970: Double($0) / 1000) : nil },
            scanlators: scanlator.map { [$0] },
            url: url.flatMap { URL(string: $0) },
            thumbnail: nil
        )
    }
}
