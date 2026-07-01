//
//  ContinueReadingSection.swift
//  Aidoku (iOS) — Nyora fork
//
//  NX-006 — Inline "Continue reading" section for the Discover feed.
//
//  A horizontal row of the most recently read, in-progress manga (ported in
//  spirit from nyora-android's "Continue reading" carousel). Each card shows the
//  cover, title, and a thin progress bar; tapping resumes the exact last-read
//  chapter in the reader. The whole section hides itself when there is no
//  resumable reading history. Self-contained: it resolves its own resume targets
//  from Core Data (mirroring ``ContinueReadingButton``) so it can be dropped into
//  the Discover feed without threading data through callers.
//

import AidokuRunner
import SwiftUI

struct ContinueReadingSection: View {
    /// A resolved "resume reading" destination plus the display progress.
    struct Entry: Identifiable {
        let id = UUID()
        let source: AidokuRunner.Source
        let manga: AidokuRunner.Manga
        let chapter: AidokuRunner.Chapter
        /// 0...1 read progress of the resume chapter (0 when unknown).
        let progress: Double
    }

    /// Maximum number of titles shown in the row.
    private static let limit = 15

    @State private var entries: [Entry] = []
    @State private var presented: Entry?

    var body: some View {
        Group {
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(NSLocalizedString("CONTINUE_READING", comment: ""))
                        .font(.poppins(18, weight: .semibold))
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(entries) { entry in
                                ContinueReadingCard(entry: entry) {
                                    presented = entry
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: entries.map(\.id))
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .historyAdded)) { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .historySet)) { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyRemoved)) { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateHistory)) { _ in
            Task { await refresh() }
        }
        .fullScreenCover(item: $presented) { entry in
            SwiftUIReaderNavigationController(
                source: entry.source,
                manga: entry.manga,
                chapter: entry.chapter
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Loading

    private struct RawEntry {
        let source: String
        let manga: String
        let chapter: String
        let progress: Int16
        let total: Int16
    }

    /// Load recent history, keep the most recent chapter per distinct manga, and
    /// resolve each into a full resume target.
    private func refresh() async {
        // Pull a generous window of recent history so we have enough distinct
        // manga to fill the row after de-duplication.
        let raw = await CoreDataManager.shared.container.performBackgroundTask { context -> [RawEntry] in
            CoreDataManager.shared.getRecentHistory(limit: 60, offset: 0, context: context).map {
                RawEntry(
                    source: $0.sourceId,
                    manga: $0.mangaId,
                    chapter: $0.chapterId,
                    progress: $0.progress,
                    total: $0.total
                )
            }
        }

        // De-dupe by (source, manga), keeping the most recent (history is already
        // sorted by dateRead descending).
        var seen = Set<String>()
        var deduped: [RawEntry] = []
        for entry in raw {
            let key = entry.source + "|" + entry.manga
            if seen.contains(key) { continue }
            seen.insert(key)
            deduped.append(entry)
            if deduped.count >= Self.limit { break }
        }

        var resolved: [Entry] = []
        for entry in deduped {
            guard let source = SourceManager.shared.source(for: entry.source) else { continue }

            let baseManga = await CoreDataManager.shared.container.performBackgroundTask { context -> AidokuRunner.Manga? in
                CoreDataManager.shared.getManga(
                    sourceId: entry.source,
                    mangaId: entry.manga,
                    context: context
                )?.toNewManga()
            }

            let chapters = await CoreDataManager.shared
                .getChapters(sourceId: entry.source, mangaId: entry.manga)
                .map { $0.toNew() }

            guard
                var manga = baseManga,
                let chapter = chapters.first(where: { $0.key == entry.chapter })
            else { continue }

            manga.chapters = chapters
            let progress: Double = entry.total > 0
                ? min(1, max(0, Double(entry.progress) / Double(entry.total)))
                : 0
            resolved.append(Entry(source: source, manga: manga, chapter: chapter, progress: progress))
        }

        entries = resolved
    }
}

/// A single "Continue reading" card: cover with a progress bar overlay and a
/// two-line title beneath it.
private struct ContinueReadingCard: View {
    let entry: ContinueReadingSection.Entry
    let onTap: () -> Void

    // Match the Discover rail card metrics.
    private static let width: CGFloat = 140
    private static let corner: CGFloat = 16

    private var coverHeight: CGFloat {
        (Self.width / NyoraTheme.coverAspectRatio).rounded()
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                SourceImageView(
                    source: entry.source,
                    imageUrl: entry.manga.cover ?? "",
                    downsampleWidth: 300,
                    contentMode: .fill
                )
                .frame(width: Self.width, height: coverHeight)
                .clipped()
                .overlay(alignment: .bottom) {
                    if entry.progress > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.black.opacity(0.45))
                                Rectangle()
                                    .fill(AccentManager.shared.color)
                                    .frame(width: geo.size.width * entry.progress)
                            }
                        }
                        .frame(height: 4)
                    }
                }

                Text(entry.manga.title)
                    .font(.poppins(13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                    .padding(8)
            }
            .frame(width: Self.width)
            .background(
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .fill(Color.nyoraCardSurface)
            )
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
