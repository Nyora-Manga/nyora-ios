//
//  NyoraSource.swift
//  Aidoku
//
//  Per-source REST runner. The Nyora helper (https://api.hasanraza.tech) is a
//  SOURCE REPOSITORY: each parser source it aggregates (parser:MANGADEX, …)
//  becomes its OWN installable Aidoku source (like the Android per-source model),
//  each with its own Popular/Latest listings + search backed by the helper's
//  `/sources/*` endpoints for that one source id. Modeled on KomgaSourceRunner.
//

import AidokuRunner
import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Source factory

extension AidokuRunner.Source {
    /// Build an Aidoku source for a SINGLE Nyora parser source.
    /// - key: unique Aidoku source key ("nyora.<slug>").
    /// - parserSource: the helper's source id, e.g. "parser:MANGADEX".
    /// - lang: catalog language code (drives the source's language + details flag).
    static func nyora(
        key: String,
        name: String,
        lang: String,
        parserSource: String,
        server: String
    ) -> AidokuRunner.Source {
        .init(
            // `url` must be nil (SourceObject.load treats it as a file path; a bare
            // host URL has 0 path components and crashes there). Server → `urls`.
            url: nil,
            key: key,
            name: name,
            version: 1,
            languages: [(lang.isEmpty || lang == "all") ? "multi" : lang],
            urls: URL(string: server).map { [$0] } ?? [],
            contentRating: .safe,
            config: .init(
                languageSelectType: .single,
                supportsTagSearch: false
            ),
            staticListings: [],
            staticFilters: [],
            runner: NyoraSourceRunner(
                sourceKey: key,
                name: name,
                lang: lang,
                parserSource: parserSource,
                server: server
            )
        )
    }
}

// MARK: - Runner

actor NyoraSourceRunner: Runner {
    static let sourceKeyPrefix = "nyora"

    let sourceKey: String
    private let name: String
    private let lang: String
    /// The helper source id this Aidoku source is bound to, e.g. "parser:MANGADEX".
    private let parserSource: String
    private let helper: NyoraHelper

    let features = SourceFeatures(
        providesListings: true,
        providesHome: true,
        dynamicListings: true,
        providesImageRequests: true,
        providesBaseUrl: true
    )

    init(sourceKey: String, name: String, lang: String, parserSource: String, server: String) {
        self.sourceKey = sourceKey
        self.name = name
        self.lang = lang
        self.parserSource = parserSource
        self.helper = NyoraHelper(server: URL(string: server) ?? URL(string: "https://api.hasanraza.tech")!)
    }

    /// GET a helper endpoint for this source; if it fails because the source
    /// isn't installed on the helper yet, install it and retry once.
    private func getEnsuringInstalled<T: Decodable & Sendable>(
        _ path: String,
        items: [URLQueryItem]
    ) async throws -> T {
        do {
            return try await helper.get(path, items: items)
        } catch SourceError.message(let msg) where msg.lowercased().contains("not installed") {
            await helper.install(parserSource)
            return try await helper.get(path, items: items)
        }
    }

    // MARK: Browse

    func getListings() async throws -> [AidokuRunner.Listing] {
        [
            AidokuRunner.Listing(id: "popular", name: NSLocalizedString("POPULAR"), kind: .default),
            AidokuRunner.Listing(id: "latest", name: NSLocalizedString("LATEST"), kind: .default),
        ]
    }

    /// Landing for this source: a "Popular" scroller (and "Latest" when available).
    /// Without a Home the source view is just a blank search box, so this is what
    /// makes browsing a source actually show content. Throws if Popular fails so
    /// the UI shows an error + retry instead of a silent blank screen.
    func getHome() async throws -> AidokuRunner.Home {
        let popularRes: NyoraBrowseResponse = try await getEnsuringInstalled(
            "sources/popular",
            items: [.init(name: "id", value: parserSource), .init(name: "page", value: "1")]
        )
        var components: [AidokuRunner.HomeComponent] = []

        let popular = filteringNsfw(popularRes.entries.map { $0.intoManga(sourceKey: sourceKey, helper: helper) })
        if !popular.isEmpty {
            components.append(.init(
                title: NSLocalizedString("POPULAR"),
                value: .scroller(
                    entries: popular.map { $0.intoLink() },
                    listing: AidokuRunner.Listing(id: "popular", name: NSLocalizedString("POPULAR"))
                )
            ))
        }

        // Latest is best-effort — some sources don't support it.
        if let latestRes: NyoraBrowseResponse = try? await getEnsuringInstalled(
            "sources/latest",
            items: [.init(name: "id", value: parserSource), .init(name: "page", value: "1")]
        ) {
            let latest = filteringNsfw(latestRes.entries.map { $0.intoManga(sourceKey: sourceKey, helper: helper) })
            if !latest.isEmpty {
                components.append(.init(
                    title: NSLocalizedString("LATEST"),
                    value: .scroller(
                        entries: latest.map { $0.intoLink() },
                        listing: AidokuRunner.Listing(id: "latest", name: NSLocalizedString("LATEST"))
                    )
                ))
            }
        }

        return .init(components: components)
    }

    func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
        let endpoint = listing.id == "latest" ? "sources/latest" : "sources/popular"
        let res: NyoraBrowseResponse = try await getEnsuringInstalled(
            endpoint,
            items: [.init(name: "id", value: parserSource), .init(name: "page", value: String(page))]
        )
        return .init(
            entries: filteringNsfw(res.entries.map { $0.intoManga(sourceKey: sourceKey, helper: helper) }),
            hasNextPage: res.hasNextPage
        )
    }

    func getSearchMangaList(
        query: String?,
        page: Int,
        filters _: [AidokuRunner.FilterValue]
    ) async throws -> AidokuRunner.MangaPageResult {
        guard let query, !query.isEmpty else {
            return .init(entries: [], hasNextPage: false)
        }
        let res: NyoraBrowseResponse = try await getEnsuringInstalled(
            "sources/search",
            items: [
                .init(name: "id", value: parserSource),
                .init(name: "q", value: query),
                .init(name: "page", value: String(page)),
            ]
        )
        return .init(
            entries: filteringNsfw(res.entries.map { $0.intoManga(sourceKey: sourceKey, helper: helper) }),
            hasNextPage: res.hasNextPage
        )
    }

    /// When the global "disable NSFW content" toggle is on, drops `.nsfw` manga.
    private nonisolated func filteringNsfw(_ entries: [AidokuRunner.Manga]) -> [AidokuRunner.Manga] {
        guard UserDefaults.standard.bool(forKey: "Sources.disableNsfw") else { return entries }
        return entries.filter { $0.contentRating != .nsfw }
    }

    // MARK: Details / pages

    func getMangaUpdate(
        manga: AidokuRunner.Manga,
        needsDetails: Bool,
        needsChapters: Bool
    ) async throws -> AidokuRunner.Manga {
        guard needsDetails || needsChapters else { return manga }
        // manga.key is the opaque manga url for this source (source id is fixed).
        let res: NyoraDetailsResponse = try await getEnsuringInstalled(
            "manga/details",
            items: [.init(name: "id", value: parserSource), .init(name: "url", value: manga.key)]
        )
        var updated = manga
        if needsDetails {
            NyoraAltTitleStore.shared.set(res.manga.altTitles ?? [], for: manga.key)
            NyoraRatingStore.shared.set(res.manga.rating, for: manga.key)
            NyoraLanguageStore.shared.set(lang.isEmpty ? nil : lang, for: manga.key)
            let mapped = res.manga.intoManga(sourceKey: sourceKey, helper: helper)
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
        let res: NyoraPagesResponse = try await getEnsuringInstalled(
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
        guard let url = URL(string: helper.rewriteImageHost(url)) else {
            throw SourceError.message("INVALID_URL")
        }
        return URLRequest(url: url)
    }

    func getBaseUrl() async throws -> URL? {
        helper.server
    }
}

// MARK: - HTTP helper

actor NyoraHelper {
    let server: URL
    private let session: URLSession

    init(server: URL) {
        self.server = server
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func get<T: Decodable & Sendable>(_ path: String, items: [URLQueryItem] = []) async throws -> T {
        guard
            var comps = URLComponents(url: server.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw SourceError.message("INVALID_URL") }
        comps.queryItems = items.isEmpty ? nil : items
        guard let url = comps.url else { throw SourceError.message("INVALID_URL") }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let raw = (try? JSONDecoder().decode(NyoraErrorResponse.self, from: data))?.error ?? ""
            // Preserve the "not installed" signal (the runner self-heals on it);
            // sanitize everything else so users never see raw upstream URLs/status.
            if raw.lowercased().contains("not installed") {
                throw SourceError.message(raw)
            }
            throw SourceError.message("This source is currently unavailable. Try another source or tap Retry.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Fetch the helper's full source catalog (the "repository" listing).
    func catalog() async throws -> [NyoraCatalogEntry] {
        let res: NyoraCatalogResponse = try await get("sources/catalog")
        return res.entries
    }

    /// Tell the helper to install (load) a parser source. Many catalog sources
    /// are `isInstalled=false` and reject browse/search with "… is not installed"
    /// until this is called. Best-effort.
    func install(_ parserSource: String) async {
        guard
            var comps = URLComponents(url: server.appendingPathComponent("sources/install"), resolvingAgainstBaseURL: false)
        else { return }
        comps.queryItems = [.init(name: "id", value: parserSource)]
        guard let url = comps.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try? await session.data(for: request)
    }

    /// The helper rewrites cover/page URLs to its own loopback proxy
    /// (`http://127.0.0.1:<port>/image?u=…`). Swap that local base for the
    /// configured server, preserving the `/image?u=…&h=…` path+query.
    nonisolated func rewriteImageHost(_ raw: String) -> String {
        guard let range = raw.range(of: "/image?u=") else { return raw }
        let base = server.absoluteString.hasSuffix("/")
            ? String(server.absoluteString.dropLast())
            : server.absoluteString
        return base + raw[range.lowerBound...]
    }
}

// MARK: - Catalog fetch (repository listing)

enum NyoraCatalog {
    /// Fetch every parser source the helper offers, for the "add source" repo list.
    static func fetchAll(server: String = "https://api.hasanraza.tech") async -> [NyoraCatalogEntry] {
        guard let url = URL(string: server) else { return [] }
        return (try? await NyoraHelper(server: url).catalog()) ?? []
    }

    /// Curated set of parser sources verified to return content (live-probed).
    /// Surfaced as "Recommended" in Add Source so users start on working sources
    /// instead of the many dead/Cloudflare-blocked catalog mirrors. Ordered.
    static let recommended: [String] = [
        "parser:MANGADEX",
        // ComicK dropped: cover CDN is Cloudflare-blocked (covers won't load)
        "parser:ASURASCANS",     // AsuraComic (the working AsuraScans)
        "parser:FLAMECOMICS",
        "parser:MANGAPILL",
        "parser:MANGAGO",
        "parser:TOONILY",
        "parser:LIKEMANGA",
        "parser:MANHUAPLUSORG",
        "parser:MANHWATOP",
        "parser:MANGAREAD",
        "parser:MANGAOWL_IO",
        "parser:MANHUAPLUS",
    ]
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

/// One entry in the helper's source catalog (a repository listing row).
struct NyoraCatalogEntry: Decodable, Sendable, Identifiable, Hashable {
    let id: String       // "parser:MANGADEX"
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

// MARK: - Mappers

private extension NyoraManga {
    func intoManga(sourceKey: String, helper: NyoraHelper) -> AidokuRunner.Manga {
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
            key: url ?? id,
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
