//
//  DiscoverView.swift
//  Aidoku (iOS) — Nyora fork
//
//  ND-012 / NX-002 — Discover screen.
//
//  The Nyora "Discover" signature surface (ported from nyora-android's
//  fragment_discover.xml). NX-002 rewires the feed to source from AniList
//  (auth-free GraphQL) rather than the first installed reader source: a hero
//  (top trending), a "Trending" recommendation pager, and a "Popular" rail.
//  AniList entries aren't tied to a readable source, so tapping one presents a
//  universal search (``NyoraTitleSearchView``) that finds a readable copy across
//  the installed sources.
//

import AidokuRunner
import SwiftUI

struct DiscoverView: View {
    enum LoadState {
        case loading
        case loaded(AniListFeed)
        case empty
        case failed(Error)
    }

    struct AniListFeed {
        let hero: AidokuRunner.Manga
        let trending: [AidokuRunner.Manga]
        let popular: [AidokuRunner.Manga]
    }

    /// Identifiable wrapper so an AniList entry can drive a `.sheet(item:)`.
    struct SearchTarget: Identifiable {
        let manga: AidokuRunner.Manga
        var id: String { manga.key }
    }

    @State private var state: LoadState = .loading
    @State private var hasLoaded = false
    @State private var searchTarget: SearchTarget?
    @ObservedObject private var accentManager = AccentManager.shared
    @EnvironmentObject private var path: NavigationCoordinator

    var body: some View {
        content
            .overlay(alignment: .bottomTrailing) {
                // ND-019 — detached circular "Continue reading" button. Self-hides
                // when there is no in-progress reading history.
                ContinueReadingButton()
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
            }
            .navigationTitle(NSLocalizedString("DISCOVER", comment: ""))
            .navigationBarTitleDisplayMode(.automatic)
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await load()
            }
            .sheet(item: $searchTarget) { target in
                NyoraTitleSearchView(title: target.manga.title, cover: target.manga.cover) { source, result in
                    searchTarget = nil
                    // Defer the push so the sheet finishes dismissing first.
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
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text(NSLocalizedString("LOADING_ELLIPSIS", comment: ""))
                .font(.poppins(14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // AniList-backed feed: hero (top trending) + "Trending" pager + "Popular" rail.
    private func loadedView(feed: AniListFeed) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // NX-005 — android-style universal search bar at the top of the feed.
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // NX-006 — inline "Continue reading" row built from in-progress
                // reading history. Self-hides when there is nothing to resume.
                ContinueReadingSection()

                DiscoverHeroCard(source: nil, manga: feed.hero, onSelect: openSearch)
                    .padding(.horizontal, 16)

                if !feed.trending.isEmpty {
                    DiscoverRecommendationPager(
                        source: nil,
                        title: NSLocalizedString("TRENDING", comment: ""),
                        manga: feed.trending,
                        onSelect: openSearch
                    )
                }

                if !feed.popular.isEmpty {
                    DiscoverRailView(
                        source: nil,
                        title: NSLocalizedString("POPULAR", comment: ""),
                        manga: feed.popular,
                        onSelect: openSearch
                    )
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Universal search

    /// Android-style tappable search field. Opens the universal search screen,
    /// which queries every installed source concurrently and shows the matches
    /// grouped by source.
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

    /// Push the shared universal search screen onto the Discover navigation stack.
    private func openUniversalSearch() {
        let searchController = SearchViewController(autoActivateSearch: true)
        searchController.title = NSLocalizedString("SEARCH", comment: "")
        path.push(searchController)
    }

    // MARK: - Loading

    /// Present the universal "find this title to read" sheet for an AniList entry.
    private func openSearch(_ manga: AidokuRunner.Manga) {
        searchTarget = SearchTarget(manga: manga)
    }

    private func load() async {
        state = .loading
        do {
            async let trendingTask = AniListClient.shared.trending()
            async let popularTask = AniListClient.shared.popular()
            let trending = try await trendingTask
            let popular = try await popularTask

            guard let hero = trending.first else {
                state = .empty
                return
            }
            // Hero is the top trending entry; keep it out of the pager below it.
            state = .loaded(AniListFeed(
                hero: hero,
                trending: Array(trending.dropFirst().prefix(12)),
                popular: popular
            ))
        } catch {
            state = .failed(error)
        }
    }
}
