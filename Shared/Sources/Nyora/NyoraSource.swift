//
//  NyoraSource.swift
//  Aidoku
//
//  Per-source REST runner. The Nyora helper (https://api.nyora.xyz) is a
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
        // Source icon: the helper has no icon URL, so use the parser-id-keyed
        // icons hosted in the nyora-aidoku repo (icons-by-parser/<BARE_ID>.png).
        let bareId = parserSource.hasPrefix("parser:") ? String(parserSource.dropFirst("parser:".count)) : parserSource
        let iconUrl = URL(string: "https://raw.githubusercontent.com/Hasan72341/nyora-aidoku/main/icons-by-parser/\(bareId).png")
        return .init(
            // `url` must be nil (SourceObject.load treats it as a file path; a bare
            // host URL has 0 path components and crashes there). Server → `urls`.
            url: nil,
            key: key,
            name: name,
            version: 1,
            languages: [(lang.isEmpty || lang == "all") ? "multi" : lang],
            urls: URL(string: server).map { [$0] } ?? [],
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
        self.helper = NyoraHelper(server: URL(string: server) ?? URL(string: "https://api.nyora.xyz")!)
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
    /// Sources found dead / Cloudflare-blocked by a live health-check
    /// (`NyoraBlockedSources`) are filtered out so the Add-Source list only
    /// ever shows working sources.
    func catalog() async throws -> [NyoraCatalogEntry] {
        let res: NyoraCatalogResponse = try await get("sources/catalog")
        return res.entries.filter { !NyoraBlockedSources.ids.contains($0.id) }
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
    static func fetchAll(server: String = "https://api.nyora.xyz") async -> [NyoraCatalogEntry] {
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
    /// Whether this source is adult-only. Missing in older catalog payloads → false.
    let isNsfw: Bool
    /// Raw content-type label, e.g. "Hentai". Optional / advisory.
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case id, name, lang, isNsfw, contentType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        lang = (try? c.decode(String.self, forKey: .lang)) ?? ""
        isNsfw = (try? c.decode(Bool.self, forKey: .isNsfw)) ?? false
        contentType = try? c.decode(String.self, forKey: .contentType)
    }

    /// Memberwise init retained for constructing entries in code (e.g. seeding).
    init(id: String, name: String, lang: String, isNsfw: Bool = false, contentType: String? = nil) {
        self.id = id
        self.name = name
        self.lang = lang
        self.isNsfw = isNsfw
        self.contentType = contentType
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

// MARK: - Blocked sources (live health-check 2026-07-09)

/// Sources that consistently returned NO browsable content (dead upstreams,
/// broken parsers, cert/handshake failures, or a browser-only Cloudflare
/// challenge) on both /sources/popular and /sources/latest. Hidden from the
/// Add-Source catalog. Regenerate by re-running the health-check.
/// 597 disabled of 960 (363 working remain).
enum NyoraBlockedSources {
    static let ids: Set<String> = [
        "parser:ADONISFANSUB",
        "parser:ADULT_WEBTOON",
        "parser:ADUMANGA",
        "parser:AINZSCANS",
        "parser:ALLHENTAI",
        "parser:ALLPORN_COMIC",
        "parser:ALONESCANLATOR",
        "parser:ALTERKAISCANS",
        "parser:ALUCARDSCANS",
        "parser:ANIMESAMA",
        "parser:ANIMEXNOVEL",
        "parser:APENASMAISUMYAOI",
        "parser:APKOMIK",
        "parser:ARABSHENTAI",
        "parser:ARAREASCANS",
        "parser:ARAZNOVEL",
        "parser:ARCTICSCAN",
        "parser:ARCURAFANSUB",
        "parser:AREASCANS",
        "parser:ARMONISCANS",
        "parser:ARTHUR_SCAN",
        "parser:ARVENSCANS",
        "parser:ARYASCANS",
        "parser:ASEMIFANSUB",
        "parser:ASQORG",
        "parser:ASTRASCANS",
        "parser:ASURASCANSGG",
        "parser:ASURASCANS_US",
        "parser:ATEMPORAL",
        "parser:ATHENAMANGA",
        "parser:ATIKROST",
        "parser:AYATOON",
        "parser:AZORAMOON",
        "parser:BABELWUXIA",
        "parser:BANANA_MANGA",
        "parser:BARMANGA",
        "parser:BATCAVE",
        "parser:BEEHENTAI",
        "parser:BEETOON",
        "parser:BEGATRANSLATION",
        "parser:BERSERKSCAN",
        "parser:BIRDTOON",
        "parser:BLUELOCKSCAN",
        "parser:BOKUGENTS",
        "parser:BOOKMANGA",
        "parser:BRMANGASTOP",
        "parser:CAFECOMYAOI",
        "parser:CHAINSAWMANSCAN",
        "parser:CMANGA",
        "parser:COFFEE_MANGA",
        "parser:COMICSVALLEY",
        "parser:COMIX",
        "parser:COMIZ",
        "parser:COMX",
        "parser:COSMIC_SCANS",
        "parser:CRYSTALSCAN",
        "parser:CVNSCAN",
        "parser:CYPHERSCANS",
        "parser:DAMCONUONG",
        "parser:DARK_SCANS",
        "parser:DAYCOMICS",
        "parser:DEMONSECT",
        "parser:DEMONSLAYERSCAN",
        "parser:DESUME",
        "parser:DEXHENTAI",
        "parser:DIANXIATRADS",
        "parser:DOCTRUYEN3Q",
        "parser:DOUJINDESU",
        "parser:DOUJINDESURIP",
        "parser:DOUJINDESUUK",
        "parser:DOUJINKU",
        "parser:DOUJINSHELL",
        "parser:DOUJIN_HENTAI_NET",
        "parser:DRAGONMANGA",
        "parser:DRAGONTEA",
        "parser:DRAGONTRANSLATIONORG",
        "parser:DREAMSCAN",
        "parser:DRSTONE",
        "parser:DTUPSCAN",
        "parser:DUALEOTRUYEN",
        "parser:EDOUJIN",
        "parser:EDSCANLATION",
        "parser:ELDERMANGA",
        "parser:ELEVENSCANLATOR",
        "parser:EMPERORSCAN",
        "parser:ENRYUMANGA",
        "parser:ERO18X",
        "parser:EROSSCANS",
        "parser:EVILMANGA",
        "parser:FACTMANGA",
        "parser:FAYSCANS",
        "parser:FIREFORCE",
        "parser:FIRESCANS",
        "parser:FIRSTKISSMANHUA",
        "parser:FLARES",
        "parser:FLOWERMANGA",
        "parser:FMTEAM",
        "parser:FREEMANGA",
        "parser:FREEMANGATOP",
        "parser:FURYMANGA",
        "parser:FUTARI",
        "parser:GAFELAND",
        "parser:GAIATOON",
        "parser:GEASSCOMICS",
        "parser:GISTAMISHOUSEFANSUB",
        "parser:GMANGA",
        "parser:GOCTRUYENTRANH",
        "parser:GOCTRUYENTRANHVUI",
        "parser:GOLGEBAHCESI",
        "parser:GOURMETSCANS",
        "parser:GREEDSCANS",
        "parser:GTOTHEGREATSITE",
        "parser:GUNCEL_MANGA",
        "parser:HADESNOFANSUB",
        "parser:HAIKYUU",
        "parser:HANGTRUYEN",
        "parser:HARIMANGA",
        "parser:HASTATEAM",
        "parser:HASTATEAM_READER",
        "parser:HAYALISTIC",
        "parser:HELLSPARADISESCAN",
        "parser:HENCHAN",
        "parser:HENTAI18VN",
        "parser:HENTAI3ZCC",
        "parser:HENTAICUBE",
        "parser:HENTAIMANGA",
        "parser:HENTAIORIGINES",
        "parser:HENTAIREAD",
        "parser:HENTAISCANTRADVF",
        "parser:HENTAISEASON",
        "parser:HENTAITECA",
        "parser:HENTAIVNBUZZ",
        "parser:HENTAIVNSU",
        "parser:HENTAIWEBTOON",
        "parser:HENTAIZONE",
        "parser:HENTAMAN",
        "parser:HERENSCAN",
        "parser:HHENTAIFR",
        "parser:HIJALACOM",
        "parser:HIKARISCAN",
        "parser:HIPERCOOL",
        "parser:HIPERDEX",
        "parser:HITOMILA",
        "parser:HNISCANTRAD",
        "parser:HOIFANSUB",
        "parser:HOTCOMICS",
        "parser:HUNTERXHUNTERSCAN",
        "parser:HWAGO",
        "parser:ICHIROMANGA",
        "parser:ILLUSIONSCAN",
        "parser:IMPERIODABRITANNIA",
        "parser:INOVASCANMANGA",
        "parser:IRISSCANLATOR",
        "parser:ISEKAISCAN_EU",
        "parser:ITSYOURIGHTMANHUA",
        "parser:JIANGZAITOON",
        "parser:JIMANGA",
        "parser:KABUSMANGA",
        "parser:KAGANE",
        "parser:KAISCANS",
        "parser:KAKUSEIPROJECT",
        "parser:KALANGO",
        "parser:KATAKOMIK",
        "parser:KINGDOMSCAN",
        "parser:KINGS_MANGA",
        "parser:KISSMANGA",
        "parser:KLMANHUA",
        "parser:KNIGHTNOSCANLATION",
        "parser:KOHARU",
        "parser:KOMIKCAST",
        "parser:KOMIKDEWASA",
        "parser:KOMIKGO",
        "parser:KOMIKMAMA",
        "parser:KOMIKREALM",
        "parser:KOMIKSIN_CO",
        "parser:KOMIKSTATION",
        "parser:KOMIKU",
        "parser:KOMIKZOID",
        "parser:KORELISCANS",
        "parser:KUMAPAGE",
        "parser:KUMASCANS",
        "parser:KUNMANGA",
        "parser:KURONEKO",
        "parser:LAMIMANGA",
        "parser:LANGGEEK",
        "parser:LAVINIAFANSUB",
        "parser:LECTORMANGA",
        "parser:LEGENDSCANLATIONS",
        "parser:LEITORDEMANGA",
        "parser:LEKMANGACOM",
        "parser:LEKMANGAORG",
        "parser:LEPOYTL",
        "parser:LERHENTAI",
        "parser:LERMANGAS",
        "parser:LERYAOI",
        "parser:LICHMANGAS",
        "parser:LILYUMFANSUB",
        "parser:LIMBOSCAN",
        "parser:LIMITEDTIMEPOJECT",
        "parser:LUACOMIC_COM",
        "parser:LUMOSKOMIK",
        "parser:LUNAR_SCAN",
        "parser:LUPITEAM",
        "parser:LXMANGA",
        "parser:MAFIAMANGA",
        "parser:MAGERIN",
        "parser:MAIDSECRET",
        "parser:MANGA168",
        "parser:MANGA18X",
        "parser:MANGA1ST",
        "parser:MANGAATREND",
        "parser:MANGAAY",
        "parser:MANGABALL_IS",
        "parser:MANGABALL_KN",
        "parser:MANGABALL_ML",
        "parser:MANGABUDDY",
        "parser:MANGABUFF",
        "parser:MANGACIX",
        "parser:MANGACLASH",
        "parser:MANGACLOUD",
        "parser:MANGACRAZY",
        "parser:MANGACUTE",
        "parser:MANGADEEMAK",
        "parser:MANGADOP",
        "parser:MANGADOTNET",
        "parser:MANGAEFENDISI",
        "parser:MANGAFASTNET",
        "parser:MANGAFIRE_EN",
        "parser:MANGAFIRE_ES",
        "parser:MANGAFIRE_ESLA",
        "parser:MANGAFIRE_FR",
        "parser:MANGAFIRE_JA",
        "parser:MANGAFIRE_PT",
        "parser:MANGAFIRE_PTBR",
        "parser:MANGAFLAME",
        "parser:MANGAFOREST",
        "parser:MANGAFORFREE",
        "parser:MANGAFOXFULL",
        "parser:MANGAFR",
        "parser:MANGAGEKO",
        "parser:MANGAGEZGINI",
        "parser:MANGAGOJO",
        "parser:MANGAHAUS",
        "parser:MANGAHENTAI",
        "parser:MANGAHONA",
        "parser:MANGAHUB_LINK",
        "parser:MANGAITALIA",
        "parser:MANGAJP",
        "parser:MANGAKAKALOT",
        "parser:MANGAKAKALOTTV",
        "parser:MANGAKAWAII",
        "parser:MANGAKAWAII_EN",
        "parser:MANGAKINGS",
        "parser:MANGAKISS",
        "parser:MANGAKITA",
        "parser:MANGAKOINU",
        "parser:MANGAKOLEJI",
        "parser:MANGAKOMA01",
        "parser:MANGAKYO",
        "parser:MANGALAND",
        "parser:MANGALC",
        "parser:MANGALEK",
        "parser:MANGALEKO",
        "parser:MANGALEVELING",
        "parser:MANGALINKNET",
        "parser:MANGALIONZ",
        "parser:MANGALIVRE",
        "parser:MANGAMAMMY",
        "parser:MANGAMANA",
        "parser:MANGAMATE",
        "parser:MANGAMUNDODRAMA",
        "parser:MANGANINJA",
        "parser:MANGAOKUTR",
        "parser:MANGAONELOVE",
        "parser:MANGAONI",
        "parser:MANGAONLINE",
        "parser:MANGAONLINETEAM",
        "parser:MANGAONLINE_BLOG",
        "parser:MANGAPUMA",
        "parser:MANGARAW",
        "parser:MANGAREADCO",
        "parser:MANGAREADERTO",
        "parser:MANGAROCK",
        "parser:MANGAROCKTEAM",
        "parser:MANGAROLLS",
        "parser:MANGAROSE",
        "parser:MANGASECT",
        "parser:MANGASEHRI",
        "parser:MANGASEHRINET",
        "parser:MANGASHIINA",
        "parser:MANGASNOSEKAI",
        "parser:MANGASORIGINES",
        "parser:MANGASOUL",
        "parser:MANGASSCANS",
        "parser:MANGASTARZ",
        "parser:MANGASWAT",
        "parser:MANGATERRA",
        "parser:MANGATILKISI",
        "parser:MANGATR",
        "parser:MANGATXUNOFFICIAL",
        "parser:MANGATX_GG",
        "parser:MANGATYRANT",
        "parser:MANGAWEEBS",
        "parser:MANGAWT",
        "parser:MANGAWT_NET",
        "parser:MANGAXICO",
        "parser:MANGAXYZ",
        "parser:MANGAYARO",
        "parser:MANGAZAVR",
        "parser:MANGA_CRAB",
        "parser:MANGA_DENIZI",
        "parser:MANGA_DISTRICT",
        "parser:MANGA_KOMI",
        "parser:MANGA_MANHUA",
        "parser:MANGA_SCANTRAD",
        "parser:MANGA_WTF",
        "parser:MANHASTRO",
        "parser:MANHUABUG",
        "parser:MANHUAES",
        "parser:MANHUAFAST",
        "parser:MANHUAGA",
        "parser:MANHUAGOLD",
        "parser:MANHUAMANHWA",
        "parser:MANHUAUS",
        "parser:MANHUAUSS",
        "parser:MANHUAZONE",
        "parser:MANHUAZONGHE",
        "parser:MANHWA18ORG",
        "parser:MANHWA68",
        "parser:MANHWACLAN",
        "parser:MANHWADESU",
        "parser:MANHWAFREAKE",
        "parser:MANHWAFULL",
        "parser:MANHWAHENTAI",
        "parser:MANHWAHENTAITO",
        "parser:MANHWAINDO",
        "parser:MANHWAKU",
        "parser:MANHWALAND",
        "parser:MANHWALAND_INK",
        "parser:MANHWALATINO",
        "parser:MANHWALIST",
        "parser:MANHWAMANHUA",
        "parser:MANHWAONLINE",
        "parser:MANHWARAW",
        "parser:MANHWARAW_COM",
        "parser:MANHWASCO",
        "parser:MANHWASMEN",
        "parser:MANHWAS_ES",
        "parser:MANHWAX",
        "parser:MANHWA_ES",
        "parser:MANJANOON",
        "parser:MANTRAZSCAN",
        "parser:MANYTOON",
        "parser:MANYTOONME",
        "parser:MANYTOON_CLUB",
        "parser:MARMOTA",
        "parser:MASHLESCAN",
        "parser:MASTERKOMIK",
        "parser:MEDIOCRETOONS",
        "parser:MEDUSASCANS",
        "parser:MEHENTAIVN",
        "parser:MERLINSCANS",
        "parser:MGKOMIK",
        "parser:MHSCANS",
        "parser:MI2MANGAES",
        "parser:MIAUSCAN",
        "parser:MIKOROKU",
        "parser:MILFTOON",
        "parser:MIMIHENTAI",
        "parser:MINDAFANSUB",
        "parser:MINITWOSCAN",
        "parser:MINTMANGA",
        "parser:MONZEEKOMIK",
        "parser:MOONDAISY_SCANS",
        "parser:MOONLOVERSSCAN",
        "parser:MOONWITCHINLOVESCAN",
        "parser:MRBENNE",
        "parser:MUGIMANGA",
        "parser:MUGIWARASOFICIAL",
        "parser:MURIMSCAN",
        "parser:MYHEROACADEMIASCAN",
        "parser:MYREADINGMANGA",
        "parser:MYSHOJO",
        "parser:NEATMANGA",
        "parser:NECROSCANS",
        "parser:NETTRUYEN",
        "parser:NETTRUYEN1975",
        "parser:NETTRUYENFE",
        "parser:NETTRUYENHE",
        "parser:NETTRUYENLL",
        "parser:NETTRUYENSSR",
        "parser:NETTRUYENUU",
        "parser:NETTRUYENVIE",
        "parser:NEUMANGA",
        "parser:NEWTRUYEN",
        "parser:NGOMIK",
        "parser:NHATTRUYENVN",
        "parser:NHENTAI",
        "parser:NHENTAI_TO",
        "parser:NIGHTSCANS",
        "parser:NIMEMOB",
        "parser:NINEMANGA_BR",
        "parser:NINEMANGA_DE",
        "parser:NINEMANGA_EN",
        "parser:NINEMANGA_ES",
        "parser:NINEMANGA_FR",
        "parser:NINEMANGA_IT",
        "parser:NINEMANGA_RU",
        "parser:NIRVANASCAN",
        "parser:NITROMANGA",
        "parser:NIVERAFANSUB",
        "parser:NOCSUMMER",
        "parser:NOINDEXSCAN",
        "parser:NORTEROSE",
        "parser:NOVELCROW",
        "parser:NOVELMIC",
        "parser:NUDEMOON",
        "parser:OLAOE",
        "parser:OLIMPOSCANS",
        "parser:ONEPIECESCAN",
        "parser:ONEPUNCHMANSCAN",
        "parser:OPIATOON",
        "parser:OSHINOKO",
        "parser:PANTHEONSCAN",
        "parser:PASSAMAOSCAN",
        "parser:PATIMANGA",
        "parser:PERF_SCAN",
        "parser:PHILIASCANS",
        "parser:PHOENIXSCANS",
        "parser:PIEDPIPERFANSUB",
        "parser:PIEDPIPERFANSUBYY",
        "parser:PIRULITOROSA",
        "parser:PLATINUMSCANS",
        "parser:PLUMACOMICS",
        "parser:POINTZEROTOONS",
        "parser:POJOKMANGA",
        "parser:POPSMANGA",
        "parser:PORNCOMIXONLINE",
        "parser:PUSSYSUSSYTOONS",
        "parser:RAGNARSCANS",
        "parser:RAIJINSCANS",
        "parser:RAIKISCAN",
        "parser:RAINDROPTEAMFAN",
        "parser:RAISCANS",
        "parser:RAMAREADER",
        "parser:RAWDEX",
        "parser:RAYSSCAN",
        "parser:READCOMICSONLINE",
        "parser:READER_EVILFLOWERS",
        "parser:READKOMIK",
        "parser:REAPERSCANSUNORIGINAL",
        "parser:REMANGA",
        "parser:RESETSCANS",
        "parser:REZOSCANS",
        "parser:RIMUSCANS",
        "parser:RIO2MANGANET",
        "parser:ROMANTIKMANGA",
        "parser:RUAHAPCHANHDAY",
        "parser:RYZUKOMIK",
        "parser:S2MANGA",
        "parser:SADSCANS",
        "parser:SAKAMOTODAYS",
        "parser:SAMURAISCAN",
        "parser:SAPPHIRESCAN",
        "parser:SARCASMSCANS",
        "parser:SCANBORUTO",
        "parser:SCANHENTAIMENU",
        "parser:SCANITA",
        "parser:SCANJUJUTSUKAISEN",
        "parser:SCANS4U",
        "parser:SCANTRAD",
        "parser:SCANVF",
        "parser:SCANVFORG",
        "parser:SCYLLACOMICS",
        "parser:SECTSCANS",
        "parser:SEINEMANGA",
        "parser:SEKAIKOMIK",
        "parser:SEKTEKOMIK",
        "parser:SELFMANGA",
        "parser:SENKURO",
        "parser:SEREINSCAN",
        "parser:SETSUSCANS",
        "parser:SHADOWMANGAS",
        "parser:SHIBAMANGA",
        "parser:SHIRAKAMI",
        "parser:SHIRO_DOUJIN",
        "parser:SHOOTINGSTARSCANS",
        "parser:SILENCESCAN",
        "parser:SIRENKOMIK",
        "parser:SITEMANGA",
        "parser:SNKSCAN",
        "parser:SNOWMACHINETRANSLATION",
        "parser:SOULSCANS",
        "parser:SSREADING",
        "parser:STELLARSABER",
        "parser:SUMMANGA",
        "parser:SUMMERTOON",
        "parser:SUSHISCAN",
        "parser:SUSSYSCAN",
        "parser:SWEETSCAN",
        "parser:TAROTSCANS",
        "parser:TATAKAE_SCANS",
        "parser:TAURUSMANGA",
        "parser:TCBSCANSMANGA",
        "parser:TECNOSCANS",
        "parser:TEMAKIMANGAS",
        "parser:TEMPESTFANSUBNET",
        "parser:TEMPESTSCANS",
        "parser:TENSHIMANGA",
        "parser:TERRITORIOLEAL",
        "parser:THEBLANK",
        "parser:THUNDERSCANS",
        "parser:TIMENAIGHT",
        "parser:TITANMANGA",
        "parser:TOKYOREVENGERS",
        "parser:TOONFR",
        "parser:TOONGOD",
        "parser:TOONILY_ME",
        "parser:TOONITUBE",
        "parser:TOONIZY",
        "parser:TOPCOMICPORNO",
        "parser:TOPREADMANHWA",
        "parser:TOPTRUYEN",
        "parser:TRADUCCIONESAMISTOSAS",
        "parser:TRADUCCIONESMOONLIGHT",
        "parser:TRESDAOS",
        "parser:TRUEMANGA",
        "parser:TRUYENHENTAIVN",
        "parser:TRUYENTRANH3Q",
        "parser:TRUYENTRANHFULL",
        "parser:TRUYENVN",
        "parser:TUKANGKOMIK",
        "parser:TUMANGAONLINE",
        "parser:TUMANHWAS",
        "parser:TUTTOANIMEMANGA",
        "parser:TU_MANHWAS",
        "parser:TYRANTSCANS",
        "parser:ULASCOMIC",
        "parser:UNIVERSOHENTAI",
        "parser:USAGI",
        "parser:UTOON",
        "parser:UZAYMANGA",
        "parser:VALKYRIESCAN",
        "parser:VARNASCAN",
        "parser:VCOMYCS",
        "parser:VERCOMICSPORNO",
        "parser:VERMANGASPORNO",
        "parser:VINLANDSAGA",
        "parser:VYMANGA",
        "parser:WALPURGISCAN",
        "parser:WAMANGA",
        "parser:WAVETEAMY",
        "parser:WEBDEXSCANS",
        "parser:WEBTOONEMPIRE",
        "parser:WEBTOONHATTI",
        "parser:WEBTOONTR",
        "parser:WEBTOONXYZ",
        "parser:WEEBDEX_DE",
        "parser:WEEBDEX_EN",
        "parser:WEEBDEX_ES",
        "parser:WEEBDEX_FR",
        "parser:WEEBDEX_IT",
        "parser:WEEBDEX_JA",
        "parser:WEEBDEX_KO",
        "parser:WEEBDEX_PT",
        "parser:WEEBDEX_RU",
        "parser:WEEBDEX_ZH",
        "parser:WELOVEMANGA",
        "parser:WESTMANGA",
        "parser:WHALEMANGA",
        "parser:WICKEDWITCHSCAN",
        "parser:WINTERSCAN",
        "parser:WITCHSCANS",
        "parser:WONDERLANDSCAN",
        "parser:WOOPREAD",
        "parser:XCALIBRSCANS",
        "parser:XSSCAN",
        "parser:YANPFANSUB",
        "parser:YAOIBAR",
        "parser:YAOIFLIX",
        "parser:YAOIHUB",
        "parser:YAOIMANGAOKU",
        "parser:YAOISCAN",
        "parser:YAOIX3",
        "parser:YCSCAN",
        "parser:YOMUMANGAS",
        "parser:YONABAR",
        "parser:YUGENMANGAS",
        "parser:YUMEKOMIK",
        "parser:YURIGARDEN",
        "parser:YURIGARDEN_R18",
        "parser:YURILAB",
        "parser:YURILIVE",
        "parser:ZANDYNOFANSUB",
        "parser:ZINCHANMANGA",
        "parser:ZINCHANMANGA_NET",
        "parser:ZIN_MANGA_COM",
    ]
}
