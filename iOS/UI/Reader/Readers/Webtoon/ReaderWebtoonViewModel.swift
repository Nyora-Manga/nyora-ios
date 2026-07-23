//
//  ReaderWebtoonViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 9/27/22.
//

import AidokuRunner
import Foundation

@MainActor
class ReaderWebtoonViewModel: ReaderPagedViewModel {
    func setPages(chapter: AidokuRunner.Chapter, pages: [Page]) {
        self.chapter = chapter
        self.pages = pages
    }

    /// Unlike the paged reader (which rebuilds the whole reader per chapter and
    /// reads `viewModel.pages`), the webtoon reader keeps multiple chapters stacked
    /// and seamlessly appends/prepends adjacent chapters during infinite scroll via
    /// `preloadedPages`. The base `preload` is a no-op (prefetch disabled), which
    /// left `preloadedPages` permanently empty and made infinite scroll dead-end at
    /// every chapter boundary. Fetch the adjacent chapter's pages LIVE here so the
    /// append/prepend paths have real data, without disturbing the current chapter.
    override func preload(chapter: AidokuRunner.Chapter) async {
        let fetched = await fetchPages(chapter: chapter)
        preloadedChapter = chapter
        preloadedPages = fetched
    }
}
