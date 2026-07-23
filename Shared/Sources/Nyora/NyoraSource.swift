//
//  NyoraSource.swift
//  Aidoku
//
//  Per-source runner backed by the ON-DEVICE parser engine (NyoraLocalEngine, GraalVM).
//  There is no cloud parser server — each parser source (parser:MANGADEX, …) becomes its
//  own Aidoku source whose Popular/Latest/search/details/pages run locally in-process via
//  the same `sources/*` + `manga/*` JSON protocol. Modeled on KomgaSourceRunner.
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
        domain: String = ""
    ) -> AidokuRunner.Source {
        // Source icon: the source's own favicon, from its site domain (provided by the engine's
        // `sources/headers`). Nothing custom is hosted per-source, so the favicon is the icon.
        let d = domain.trimmingCharacters(in: .whitespaces)
        let iconUrl: URL? = d.isEmpty
            ? nil
            : URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(d)")
        return .init(
            url: nil,
            key: key,
            name: name,
            version: 1,
            languages: [(lang.isEmpty || lang == "all") ? "multi" : lang],
            urls: [],   // parsing is fully on-device; no cloud/base host
            contentRating: .safe,
            imageUrl: iconUrl,
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
                parserSource: parserSource
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

    init(sourceKey: String, name: String, lang: String, parserSource: String) {
        self.sourceKey = sourceKey
        self.name = name
        self.lang = lang
        self.parserSource = parserSource
        self.helper = NyoraHelper()
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

    /// The source's image request headers (mainly `Referer` = the site domain), cached once.
    /// Hotlink-protected sources (MangaPill, most Madara sites) return 403 for covers/pages
    /// without the right Referer. We deliberately DROP User-Agent — a browser UA breaks some
    /// CDNs (e.g. MangaDex's uploads.* returns 400), while URLSession's default UA works with
    /// the Referer everywhere.
    private var cachedImageHeaders: [String: String]?

    private func imageHeaders() async -> [String: String] {
        if let h = cachedImageHeaders { return h }
        var h: [String: String] = [:]
        if let res: NyoraHeadersResponse = try? await getEnsuringInstalled(
            "sources/headers", items: [.init(name: "id", value: parserSource)]
        ) {
            h = res.headers.filter { $0.key.lowercased() != "user-agent" }
        }
        cachedImageHeaders = h
        return h
    }

    func getImageRequest(url: String, context _: PageContext?) async throws -> URLRequest {
        guard let imgUrl = URL(string: helper.rewriteImageHost(url)) else {
            throw SourceError.message("INVALID_URL")
        }
        var request = URLRequest(url: imgUrl)
        for (key, value) in await imageHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        // If this image host has a Cloudflare clearance, send the UA it was issued for so the
        // cf_clearance cookie is honored (otherwise we leave URLSession's default UA, since a
        // browser UA breaks some open CDNs like MangaDex).
        #if canImport(UIKit)
        if let host = imgUrl.host, NyoraCloudflareSolver.hasClearance(for: host) {
            request.setValue(NyoraCloudflareSolver.userAgent, forHTTPHeaderField: "User-Agent")
        }
        #endif
        return request
    }

    func getBaseUrl() async throws -> URL? {
        nil   // parsing is on-device; there is no cloud base URL
    }
}

// MARK: - HTTP helper

/// In-process access to the on-device parser engine. There is NO cloud parser server
/// (api.nyora.xyz was removed) — every call runs the native GraalVM engine locally. The
/// only network Nyora does off-device is sync (sync.nyora.xyz) and the sources' own sites.
actor NyoraHelper {

    func get<T: Decodable & Sendable>(_ path: String, items: [URLQueryItem] = []) async throws -> T {
        #if canImport(NyoraNativeBridge) || NYORA_LOCAL_ENGINE
        let data = try await NyoraLocalEngine.shared.request(path: path, items: items)
        if let err = try? JSONDecoder().decode(NyoraErrorResponse.self, from: data), !err.error.isEmpty {
            throw SourceError.message(err.error)
        }
        return try JSONDecoder().decode(T.self, from: data)
        #else
        throw SourceError.message("The Nyora local engine is not available in this build.")
        #endif
    }

    /// The engine's full source catalog — returned AS-IS, no iOS-side filtering. The engine already
    /// mirrors nyora-android's catalog (all installable sources minus android's DEAD_SOURCES), so the
    /// app shows exactly what android shows. (Previously an extra iOS `NyoraBlockedSources` health-list
    /// hid ~570 of them, which is why sources like ManhuaUS were missing.)
    func catalog() async throws -> [NyoraCatalogEntry] {
        let res: NyoraCatalogResponse = try await get("sources/catalog")
        return res.entries
    }

    /// Parsers are always resident in the local engine — nothing to install.
    func install(_ parserSource: String) async {}

    /// The source's site domain (used for its favicon), taken from the engine's Referer header.
    func domain(for parserSource: String) async -> String {
        guard let res: NyoraHeadersResponse = try? await get(
            "sources/headers", items: [.init(name: "id", value: parserSource)]
        ) else { return "" }
        let referer = res.headers.first { $0.key.lowercased() == "referer" }?.value ?? ""
        return URL(string: referer)?.host ?? ""
    }

    /// The local engine returns direct image URLs (no loopback proxy), so this is identity.
    nonisolated func rewriteImageHost(_ raw: String) -> String { raw }
}

// MARK: - Catalog fetch (repository listing)

enum NyoraCatalog {
    /// Fetch every parser source the on-device engine offers, for the "add source" list.
    static func fetchAll() async -> [NyoraCatalogEntry] {
        (try? await NyoraHelper().catalog()) ?? []
    }

    /// Curated set of parser sources verified to return content (live-probed).
    /// Surfaced as "Recommended" in Add Source so users start on working sources
    /// instead of the many dead/Cloudflare-blocked catalog mirrors. Ordered.
    static let recommended: [String] = [
        "parser:MANGADEX",
        // ComicK dropped: cover CDN is Cloudflare-blocked (covers won't load)
        "parser:ASURASCANS",     // AsuraComic on asurascans.com (domain override)
        "parser:MANGAFIRE_EN",   // native JSON-API backend (custom engine service)
        "parser:TOONILY_ME",     // "ToonDex" — native JSON-API backend (custom engine service)
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
        "parser:MANHUAUS",       // manhuaus.com (live, behind Cloudflare — solved on-device)
    ]
}

/// The Google favicon URL for a site domain — the same icon installed Nyora sources use.
func nyoraFaviconURL(for domain: String?) -> URL? {
    let d = (domain ?? "").trimmingCharacters(in: .whitespaces)
    guard !d.isEmpty else { return nil }
    return URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(d)")
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
    /// Whether this source is adult-only. Missing in older catalog payloads → false.
    let isNsfw: Bool
    /// Raw content-type label, e.g. "Hentai". Optional / advisory.
    let contentType: String?
    /// The source's live site domain (override applied) — drives its favicon in the Add-Source list.
    let domain: String?

    enum CodingKeys: String, CodingKey {
        case id, name, lang, isNsfw, contentType, domain
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        lang = (try? c.decode(String.self, forKey: .lang)) ?? ""
        isNsfw = (try? c.decode(Bool.self, forKey: .isNsfw)) ?? false
        contentType = try? c.decode(String.self, forKey: .contentType)
        domain = try? c.decode(String.self, forKey: .domain)
    }

    /// Memberwise init retained for constructing entries in code (e.g. seeding).
    init(id: String, name: String, lang: String, isNsfw: Bool = false, contentType: String? = nil, domain: String? = nil) {
        self.id = id
        self.name = name
        self.lang = lang
        self.isNsfw = isNsfw
        self.contentType = contentType
        self.domain = domain
    }
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

private struct NyoraHeadersResponse: Decodable, Sendable {
    let headers: [String: String]
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

// MARK: - Hidden sources (android parity)

/// Sources hidden from the Add-Source catalog. Ported 1:1 from nyora-android's
/// `SourcePatches.DEAD_SOURCES` (this app is android's port) so iOS shows the SAME set of sources
/// android does — dead domains with no working same-CMS successor — MINUS `TOONILY_ME`, which iOS
/// surfaces via its own working ToonDex custom engine service. Cloudflare-protected sources are
/// intentionally KEPT: the on-device interactive WebView solver (NyoraCloudflareSolver) clears them.
enum NyoraBlockedSources {
    static let ids: Set<String> = [
        "parser:ASURASCANS_US",
        "parser:ASURASCANSGG",
        "parser:ATEMPORAL",
        "parser:AYATOON",
        "parser:BANANA_MANGA",
        "parser:DREAMSCAN",
        "parser:EDSCANLATION",
        "parser:ELEVENSCANLATOR",
        "parser:FACTMANGA",
        "parser:FREEMANGA",
        "parser:FREEMANGATOP",
        "parser:GMANGA",
        "parser:GOURMETSCANS",
        "parser:GUNCEL_MANGA",
        "parser:HIKARISCAN",
        "parser:HOIFANSUB",
        "parser:KABUSMANGA",
        "parser:KALANGO",
        "parser:KORELISCANS",
        "parser:KUMASCANS",
        "parser:LEGENDSCANLATIONS",
        "parser:LILYUMFANSUB",
        "parser:MAFIAMANGA",
        "parser:MANGAGOJO",
        "parser:MANGAJINX",
        "parser:MANGAKINGS",
        "parser:MANGAKISS",
        "parser:MANGAMATE",
        "parser:MANGANINJA",
        "parser:MANGAOKUTR",
        "parser:MANGAONELOVE",
        "parser:MANGAONLINETEAM",
        "parser:MANGAREADCO",
        "parser:MANGAROSE",
        "parser:MANGASECT",
        "parser:MANGASSCANS",
        "parser:MANGATX_GG",
        "parser:MANGA_MANHUA",
        "parser:MANHUAES",
        "parser:MANHUAGA",
        "parser:MANHUAGOLD",
        "parser:MANHUASCAN",
        "parser:MANHWAKU",
        "parser:MANHWASCO",
        "parser:MANJANOON",
        "parser:MOONWITCHINLOVESCAN",
        "parser:MURIMSCAN",
        "parser:NEWTRUYEN",
        "parser:NIRVANASCAN",
        "parser:NORTEROSE",
        "parser:NOVELMIC",
        "parser:RAYSSCAN",
        "parser:READER_EVILFLOWERS",
        "parser:REAPERCOMICS",
        "parser:RUAHAPCHANHDAY",
        "parser:SECTSCANS",
        "parser:SEINAGI",
        "parser:SHOOTINGSTARSCANS",
        "parser:SITEMANGA",
        "parser:SSREADING",
        "parser:SWEETSCAN",
        "parser:TATAKAE_SCANS",
        "parser:TAURUSMANGA",
        "parser:TCBSCANSMANGA",
        "parser:TECNOSCANS",
        "parser:TIMENAIGHT",
        "parser:TRADUCCIONESAMISTOSAS",
        "parser:TYRANTSCANS",
        "parser:WEBTOONTR",
        "parser:WINTERSCAN",
        "parser:ZANDYNOFANSUB",
        "parser:ZENITHSCANS",
        "parser:ZINCHANMANGA_NET",
        "parser:ZIN_MANGA_COM",
    ]
}
