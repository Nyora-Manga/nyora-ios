//
//  DiscoverView.swift
//  Aidoku (iOS) — Nyora fork
//
//  Discover screen, redesigned 1:1 with nyora-web. The feed is sourced from AniList
//  (primary) with a MangaBaka fallback via ``AniListDiscoverClient``: a hero (#1
//  trending) followed by horizontal rails (Trending now, Popular Manhwa/Manhua/Manga,
//  and genre rails). Discover entries aren't tied to a readable source, so tapping one
//  presents a universal search (``NyoraTitleSearchView``) that finds a readable copy
//  across the installed sources.
//

import SwiftUI

struct DiscoverView: View {
    enum LoadState {
        case loading
        case loaded(DiscoverFeed)
        case empty
        case failed(Error)
    }

    struct DiscoverFeed {
        let hero: DiscoverItem
        let rails: [DiscoverSection]   // Trending now (hero-less), Popular Manhwa/Manhua/Manga, genres…
    }

    /// Identifiable wrapper so a discover entry can drive a `.sheet(item:)`.
    struct SearchTarget: Identifiable {
        let item: DiscoverItem
        var id: String { item.id }
    }

    @State private var state: LoadState = .loading
    @State private var hasLoaded = false
    @State private var searchTarget: SearchTarget?
    @ObservedObject private var accentManager = AccentManager.shared
    @EnvironmentObject private var path: NavigationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottomTrailing) {
            ContinueReadingButton()
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
        .navigationTitle(NSLocalizedString("DISCOVER", comment: ""))
        .navigationBarTitleDisplayMode(.automatic)
        .task {
            if hasLoaded { return }
            await load()
        }
        .sheet(item: $searchTarget) { target in
            NyoraTitleSearchView(title: target.item.title, cover: target.item.cover) { source, result in
                searchTarget = nil
                DispatchQueue.main.async {
                    path.push(MangaViewController(
                        source: source,
                        manga: result,
                        parent: path.rootViewController
                    ))
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
            case .loading:
                loadingView
            case let .loaded(feed):
                loadedView(feed: feed)
            case .empty:
                emptyView
            case let .failed(error):
                ErrorView(error: error) {
                    await load()
                }
                .padding()
        }
    }

    // MARK: - States

    private var loadingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DiscoverSkeletonBlock(cornerRadius: NyoraTheme.cornerHero)
                    .frame(height: DiscoverHeroCard.height)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                ForEach(0..<3, id: \.self) { _ in
                    DiscoverSkeletonRail()
                }
            }
            .padding(.bottom, 24)
        }
        .disabled(true)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(accentManager.color)
            Text(NSLocalizedString("DISCOVER", comment: ""))
                .font(.poppins(22, weight: .bold))
            Text(NSLocalizedString("DISCOVER_EMPTY_MESSAGE", comment: ""))
                .font(.poppins(14, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadedView(feed: DiscoverFeed) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ContinueReadingSection()
                    .padding(.top, 4)

                DiscoverHeroCard(item: feed.hero, onSelect: openSearch)
                    .padding(.horizontal, 16)

                ForEach(feed.rails) { rail in
                    DiscoverRailView(
                        title: rail.title,
                        items: rail.items,
                        onSelect: openSearch,
                        onShowAll: openUniversalSearch
                    )
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Universal search

    private var searchBar: some View {
        Button {
            openUniversalSearch()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentManager.color)
                Text(NSLocalizedString("DISCOVER_SEARCH_HINT", comment: ""))
                    .font(.poppins(15, weight: .regular))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .fill(Color.nyoraCardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func openUniversalSearch() {
        let searchController = SearchViewController(autoActivateSearch: true)
        searchController.title = NSLocalizedString("SEARCH", comment: "")
        path.push(searchController)
    }

    // MARK: - Loading

    private func openSearch(_ item: DiscoverItem) {
        searchTarget = SearchTarget(item: item)
    }

    private func load() async {
        state = .loading
        do {
            let sections = try await AniListDiscoverClient.shared.feed()

            // The "trending" section drives the hero (item 0) + the "Trending now" rail (the rest).
            let trendingSection = sections.first { $0.id == "trending" } ?? sections.first
            guard let trendingSection, let hero = trendingSection.items.first else {
                state = .empty
                hasLoaded = true
                return
            }
            let trendingRail = DiscoverSection(
                id: trendingSection.id,
                title: trendingSection.title,
                items: Array(trendingSection.items.dropFirst())
            )
            let otherRails = sections.filter { $0.id != trendingSection.id }
            let rails = ([trendingRail] + otherRails).filter { !$0.items.isEmpty }

            state = .loaded(DiscoverFeed(hero: hero, rails: rails))
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error)
        }
    }
}

// MARK: - Loading skeleton

private struct DiscoverSkeletonBlock: View {
    var cornerRadius: CGFloat = 12

    var body: some View {
        ShimmerSkeleton()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct DiscoverSkeletonRail: View {
    private static let cardWidth: CGFloat = 138
    private static let corner: CGFloat = 18
    private var coverHeight: CGFloat { (Self.cardWidth * 3 / 2).rounded() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiscoverSkeletonBlock(cornerRadius: 6)
                .frame(width: 140, height: 18)
                .padding(.horizontal, 16)

            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        DiscoverSkeletonBlock(cornerRadius: Self.corner)
                            .frame(width: Self.cardWidth, height: coverHeight)
                        DiscoverSkeletonBlock(cornerRadius: 4)
                            .frame(width: Self.cardWidth * 0.8, height: 12)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
