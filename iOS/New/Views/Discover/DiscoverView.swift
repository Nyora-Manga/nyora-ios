//
//  DiscoverView.swift
//  Aidoku (iOS) — Nyora fork
//
//  ND-012 / NX-002 — Discover screen.
//
//  The Nyora "Discover" signature surface (ported from nyora-android's
//  fragment_discover.xml). NX-002 rewires the feed to source from the MangaBaka
//  database (auth-free search) rather than the first installed reader source: a
//  hero (top trending), a "Trending" recommendation pager, and further rails.
//  MangaBaka entries aren't tied to a readable source, so tapping one presents a
//  universal search (``NyoraTitleSearchView``) that finds a readable copy across
//  the installed sources.
//

import AidokuRunner
import SwiftUI

struct DiscoverView: View {
    enum LoadState {
        case loading
        case loaded(DiscoverFeed)
        case empty
        case failed(Error)
    }

    struct DiscoverFeed {
        let hero: AidokuRunner.Manga
        let trending: [AidokuRunner.Manga]              // trending minus hero → the pager
        let rails: [MangaBakaDiscoverClient.Section]    // Top Rated, Manhwa, genres…
    }

    /// Identifiable wrapper so a MangaBaka entry can drive a `.sheet(item:)`.
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
        VStack(spacing: 0) {
            // Universal search bar pinned above the feed so it stays visible in
            // every state (loading / empty / error / loaded), not just the feed.
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
                // Only skip once a load has *succeeded*. A cancelled/failed first
                // attempt (the view is briefly torn down during the onboarding→main
                // transition, cancelling the fetch) leaves `hasLoaded == false` so
                // the reappearing `.task` retries cleanly instead of sticking on an
                // "Unknown Error".
                if hasLoaded { return }
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

    // Skeleton placeholder that mirrors the real feed layout (a hero-sized block +
    // a few cover-shaped rails) with a subtle shimmer, so the first paint reads as
    // "content is arriving" rather than a lone spinner. Uses the same
    // `ShimmerSkeleton` the covers fade in from.
    private var loadingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero block
                DiscoverSkeletonBlock(cornerRadius: NyoraTheme.cornerHero)
                    .frame(height: DiscoverHeroCard.height)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                // A few cover rails
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

    // MangaBaka-backed feed: hero (top trending) + "Trending" pager + rails.
    private func loadedView(feed: DiscoverFeed) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // NX-006 — inline "Continue reading" row built from in-progress
                // reading history. Self-hides when there is nothing to resume.
                ContinueReadingSection()
                    .padding(.top, 4)

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

                // Popular, Top Rated, and the genre rails.
                ForEach(feed.rails) { rail in
                    if !rail.manga.isEmpty {
                        DiscoverRailView(
                            source: nil,
                            title: rail.title,
                            manga: rail.manga,
                            onSelect: openSearch
                        )
                    }
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

    /// Present the universal "find this title to read" sheet for a MangaBaka entry.
    private func openSearch(_ manga: AidokuRunner.Manga) {
        searchTarget = SearchTarget(manga: manga)
    }

    private func load() async {
        state = .loading
        do {
            let sections = try await MangaBakaDiscoverClient.shared.feed()

            // First section ("trending") drives the hero + pager; the rest are rails.
            let trendingSection = sections.first { $0.id == "trending" } ?? sections.first
            guard let hero = trendingSection?.manga.first else {
                state = .empty
                hasLoaded = true
                return
            }
            let trending = Array((trendingSection?.manga ?? []).dropFirst().prefix(12))
            let rails = sections.filter { $0.id != trendingSection?.id }

            state = .loaded(DiscoverFeed(hero: hero, trending: trending, rails: rails))
            hasLoaded = true
        } catch is CancellationError {
            // The fetch was cancelled by a transient view teardown. Leave the state
            // as-is (still `.loading`) and don't mark loaded, so the `.task` that
            // fires when the view reappears retries the fetch cleanly.
            return
        } catch {
            state = .failed(error)
        }
    }
}

// MARK: - Loading skeleton

/// A single shimmering rounded block used to build the Discover loading skeleton.
private struct DiscoverSkeletonBlock: View {
    var cornerRadius: CGFloat = 12

    var body: some View {
        ShimmerSkeleton()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// One shimmer rail: a short section-title placeholder above a row of
/// cover-shaped shimmer cards, matching `DiscoverRailView`'s real layout.
private struct DiscoverSkeletonRail: View {
    private static let cardWidth: CGFloat = 140
    private static let corner: CGFloat = 16

    private var coverHeight: CGFloat {
        (Self.cardWidth / NyoraTheme.coverAspectRatio).rounded()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section-title placeholder
            DiscoverSkeletonBlock(cornerRadius: 6)
                .frame(width: 140, height: 18)
                .padding(.horizontal, 16)

            // Row of cover-shaped cards (no scrolling — decorative)
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
