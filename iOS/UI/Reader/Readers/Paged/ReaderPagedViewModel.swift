//
//  ReaderPagedViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Foundation
import AidokuRunner

@MainActor
class ReaderPagedViewModel {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    var chapter: AidokuRunner.Chapter?
    var pages: [Page] = []

    // Prefetch is DISABLED (see loadPages/preload): these stay empty so the reader
    // controllers' seamless chapter-boundary previews are simply skipped (they all
    // guard on `preloadedPages.isEmpty`). Kept only so those call sites compile.
    var preloadedChapter: AidokuRunner.Chapter?
    var preloadedPages: [Page] = []

    init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga) {
        self.source = source
        self.manga = manga
    }

    func loadPages(chapter: AidokuRunner.Chapter) async {
        // Prefetch removed — always fetch the requested chapter's pages LIVE.
        // The background preload cache made non-first chapters open blank: a
        // failed/racing preload cached an empty page list that loadPages then
        // served without ever retrying. Fetching live on open is simpler and
        // correct (page IMAGES are still lazy-loaded per-page).
        self.chapter = chapter
        pages = await getPages(chapter: chapter)
    }

    func preload(chapter: AidokuRunner.Chapter) async {
        // No-op: chapter prefetching is disabled (see loadPages). Kept so existing
        // call sites compile; pages are fetched live when a chapter is opened.
    }

    /// Fetch a chapter's pages LIVE without mutating the current-chapter state
    /// (`chapter`/`pages`). Used by the webtoon reader's infinite-scroll
    /// append/prepend, which otherwise relied on `preloadedPages` — always empty
    /// now that prefetch is disabled — and so never loaded adjacent chapters.
    func fetchPages(chapter: AidokuRunner.Chapter) async -> [Page] {
        await getPages(chapter: chapter)
    }

    private func getPages(chapter: AidokuRunner.Chapter) async -> [Page] {
        let sourceId = source?.key ?? manga.sourceKey
        let identifier = ChapterIdentifier(
            sourceKey: sourceId,
            mangaKey: manga.key,
            chapterKey: chapter.key
        )
        let isDownloaded = DownloadManager.shared.isChapterDownloaded(chapter: identifier)
        if isDownloaded {
            let downloaded = await DownloadManager.shared.getDownloadedPages(for: identifier)
                .map {
                    $0.toOld(sourceId: sourceId, chapterId: chapter.key)
                }
            // A downloaded chapter with 0 page files (corrupt/partial download) would
            // otherwise return an empty list, which makes loadChapter skip
            // loadPageControllers entirely and leave the PREVIOUS chapter's controllers +
            // stale `chapter` in place (swiping then navigates old pages while progress is
            // tracked against the new chapter). Mirror the live path: surface a diagnostic
            // page so pages is never empty.
            if downloaded.isEmpty {
                return [Self.diagnosticPage(sourceId: sourceId, chapter: chapter, reason: "0 downloaded pages (re-download this chapter)")]
            }
            return downloaded
        } else {
            do {
                let list = try await source?.getPageList(manga: manga, chapter: chapter) ?? []
                let mapped = list.map { $0.toOld(sourceId: sourceId, chapterId: chapter.key) }
                if mapped.isEmpty {
                    return [Self.diagnosticPage(sourceId: sourceId, chapter: chapter, reason: "helper returned 0 pages")]
                }
                return mapped
            } catch {
                return [Self.diagnosticPage(sourceId: sourceId, chapter: chapter, reason: String(describing: error))]
            }
        }
    }

    /// Placeholder shown in place of a blank chapter when pages can't be loaded.
    /// Renders a CLEAN, user-facing message inline in whichever reader is active
    /// (image or text) and is flagged `isError` so it is never mistaken for a real
    /// novel/text page (which would switch readers + mark the chapter read). The
    /// raw failure `reason` is logged for diagnostics, never shown — matching
    /// nyora-web, which surfaces a sanitized error and keeps parser/source ids and
    /// raw errors out of the UI.
    private static func diagnosticPage(sourceId: String, chapter: AidokuRunner.Chapter, reason: String) -> Page {
        LogManager.logger.error("Nyora reader: couldn't load pages for \(sourceId) chapter \(chapter.key): \(reason)")
        var page = Page(sourceId: sourceId, chapterId: chapter.key)
        page.isError = true
        page.text = NSLocalizedString("FAILED_CHAPTER_LOAD", comment: "")
            + "\n\n"
            + NSLocalizedString("FAILED_CHAPTER_LOAD_INFO", comment: "")
        return page
    }
}
