//
//  AllBookmarksView.swift
//  Aidoku (iOS) — Nyora fork
//
//  The Bookmarks list — saved reader pages grouped per manga (matching nyora-android's
//  AllBookmarksFragment). Tapping a bookmark opens the reader at that exact page.
//

import AidokuRunner
import SwiftUI

struct AllBookmarksView: View {
    @ObservedObject private var store = NyoraBookmarkStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var target: ReaderTarget?

    struct ReaderTarget: Identifiable {
        let id = UUID()
        let source: AidokuRunner.Source
        let manga: AidokuRunner.Manga
        let chapter: AidokuRunner.Chapter
        let page: Int
    }

    var body: some View {
        PlatformNavigationStack {
            Group {
                if store.bookmarks.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }
            .navigationTitle(NSLocalizedString("BOOKMARKS", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("DONE", comment: "")) { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $target) { t in
            SwiftUIReaderNavigationController(
                source: t.source,
                manga: t.manga,
                chapter: t.chapter,
                startPage: t.page
            )
            .ignoresSafeArea()
        }
    }

    private var listView: some View {
        List {
            ForEach(store.grouped, id: \.key) { group in
                Section {
                    ForEach(group.items) { bookmark in
                        Button {
                            open(bookmark)
                        } label: {
                            row(bookmark)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                store.remove(bookmark)
                            } label: {
                                Label(NSLocalizedString("REMOVE", comment: ""), systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(group.title)
                }
            }
        }
    }

    private func row(_ bookmark: NyoraBookmark) -> some View {
        HStack(spacing: 12) {
            SourceImageView(
                sourceId: bookmark.sourceId,
                imageUrl: bookmark.mangaCover ?? "",
                width: 44,
                height: 44 * 3 / 2,
                downsampleWidth: 44
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.chapterTitle?.isEmpty == false ? bookmark.chapterTitle! : bookmark.mangaTitle)
                    .font(.poppins(15, weight: .semibold))
                    .lineLimit(1)
                Text(String(format: NSLocalizedString("PAGE_NUMBER", comment: ""), bookmark.page))
                    .font(.poppins(13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("BOOKMARKS_EMPTY", comment: ""))
                .font(.poppins(15, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Reconstruct the manga + chapter (from Core Data, falling back to the live source) and open
    /// the reader at the bookmarked page.
    private func open(_ bookmark: NyoraBookmark) {
        Task { @MainActor in
            guard let source = SourceManager.shared.source(for: bookmark.sourceId) else { return }
            let baseManga = await CoreDataManager.shared.container.performBackgroundTask { context -> AidokuRunner.Manga? in
                CoreDataManager.shared.getManga(
                    sourceId: bookmark.sourceId,
                    mangaId: bookmark.mangaId,
                    context: context
                )?.toNewManga()
            }
            var manga = baseManga ?? AidokuRunner.Manga(
                sourceKey: bookmark.sourceId,
                key: bookmark.mangaId,
                title: bookmark.mangaTitle,
                cover: bookmark.mangaCover
            )

            var chapters = await CoreDataManager.shared
                .getChapters(sourceId: bookmark.sourceId, mangaId: bookmark.mangaId)
                .map { $0.toNew() }
            if !chapters.contains(where: { $0.key == bookmark.chapterId }) {
                // The chapter isn't cached locally — pull the list from the source.
                if let updated = try? await source.getMangaUpdate(manga: manga, needsDetails: false, needsChapters: true) {
                    chapters = updated.chapters ?? []
                }
            }
            guard let chapter = chapters.first(where: { $0.key == bookmark.chapterId }) else { return }
            manga.chapters = chapters
            target = ReaderTarget(source: source, manga: manga, chapter: chapter, page: bookmark.page)
        }
    }
}
