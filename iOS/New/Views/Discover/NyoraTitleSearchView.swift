//
//  NyoraTitleSearchView.swift
//  Aidoku (iOS) — Nyora fork
//
//  NX-002 — universal "find this title in a source" sheet.
//
//  AniList feed entries in Discover are not tied to a readable source, so tapping
//  one presents this sheet: it runs a universal search of the title across every
//  installed source concurrently and shows the matches grouped by source. Picking
//  a match opens that source's manga details (where it can actually be read).
//

import AidokuRunner
import SwiftUI

struct NyoraTitleSearchView: View {
    let title: String
    /// Cover for the AniList entry, shown in the sheet header while searching.
    let cover: String?
    /// Opens the chosen readable copy. The presenter dismisses and pushes details.
    let onOpen: (AidokuRunner.Source, AidokuRunner.Manga) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var accentManager = AccentManager.shared

    @State private var groups: [SourceGroup] = []
    @State private var isLoading = true
    @State private var searchTask: Task<Void, Never>?

    struct SourceGroup: Identifiable {
        let source: AidokuRunner.Source
        let entries: [AidokuRunner.Manga]
        var id: String { source.id }
    }

    private var hasResults: Bool {
        groups.contains { !$0.entries.isEmpty }
    }

    var body: some View {
        PlatformNavigationStack {
            content
                .navigationTitle(NSLocalizedString("FIND_TO_READ", comment: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("CANCEL", comment: "")) { dismiss() }
                    }
                }
        }
        .task {
            await runSearch()
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if isLoading && !hasResults {
                    HStack {
                        Spacer()
                        ProgressView().progressViewStyle(.circular)
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if !hasResults {
                    emptyResults
                } else {
                    ForEach(groups) { group in
                        if !group.entries.isEmpty {
                            resultsSection(group)
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            SourceImageView(
                source: nil,
                imageUrl: cover ?? "",
                downsampleWidth: 160,
                contentMode: .fill
            )
            .frame(width: 52, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: NyoraTheme.cornerCover, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NyoraTheme.cornerCover, style: .continuous)
                    .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.poppins(18, weight: .bold))
                    .lineLimit(2)
                Text(NSLocalizedString("FIND_TO_READ_SUBTITLE", comment: ""))
                    .font(.poppins(13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private var emptyResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(accentManager.color)
            Text(NSLocalizedString("FIND_TO_READ_NONE", comment: ""))
                .font(.poppins(16, weight: .semibold))
            Text(NSLocalizedString("FIND_TO_READ_NONE_TEXT", comment: ""))
                .font(.poppins(13, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 32)
    }

    private func resultsSection(_ group: SourceGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.source.name)
                .font(.poppins(16, weight: .semibold))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(group.entries.indices, id: \.self) { index in
                        let manga = group.entries[index]
                        Button {
                            onOpen(group.source, manga)
                        } label: {
                            resultCard(source: group.source, manga: manga)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func resultCard(source: AidokuRunner.Source, manga: AidokuRunner.Manga) -> some View {
        let width: CGFloat = 120
        let coverHeight = (width / NyoraTheme.coverAspectRatio).rounded()
        return VStack(alignment: .leading, spacing: 0) {
            SourceImageView(
                source: source,
                imageUrl: manga.cover ?? "",
                downsampleWidth: 260,
                contentMode: .fill
            )
            .frame(width: width, height: coverHeight)
            .clipped()

            Text(manga.title)
                .font(.poppins(12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                .padding(8)
        }
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.nyoraCardSurface)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
        )
    }

    // MARK: - Search

    @MainActor
    private func runSearch() async {
        guard groups.isEmpty else { return }
        isLoading = true
        let sources = SourceManager.shared.sources
        guard !sources.isEmpty else {
            isLoading = false
            return
        }

        // Sources can freeze under too much concurrency, so cap parallelism.
        let maxConcurrent = 3
        await withTaskGroup(of: (AidokuRunner.Source, [AidokuRunner.Manga]).self) { taskGroup in
            var next = 0
            func addTask(_ source: AidokuRunner.Source) {
                taskGroup.addTask {
                    let result = try? await source.getSearchMangaList(query: title, page: 1, filters: [])
                    return (source, Array((result?.entries ?? []).prefix(10)))
                }
            }

            while next < min(sources.count, maxConcurrent) {
                addTask(sources[next])
                next += 1
            }

            while let (source, entries) = await taskGroup.next() {
                if next < sources.count {
                    addTask(sources[next])
                    next += 1
                }
                if Task.isCancelled { return }
                if !entries.isEmpty {
                    groups.append(SourceGroup(source: source, entries: entries))
                }
            }
        }

        isLoading = false
    }
}
