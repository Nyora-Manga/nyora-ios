//
//  DiscoverView.swift
//  Aidoku (iOS) — Nyora fork
//
//  ND-012 — Discover screen scaffold.
//
//  A new vertical-feed screen (the Nyora "Discover" signature surface, ported
//  from nyora-android's fragment_discover.xml). This scaffold loads home data
//  from the first installed source that provides a home layout via the existing
//  `AidokuRunner.Source.getHome()` path, and renders loading / empty / error
//  states plus a minimal component overview. Later phases (ND-013 hero card,
//  ND-014 rails, ND-015 recommendation pager) replace the placeholder feed with
//  the full Nyora hero + rails + pager layout.
//

import AidokuRunner
import SwiftUI

struct DiscoverView: View {
    enum LoadState {
        case loading
        case loaded(source: AidokuRunner.Source, home: Home)
        case empty
        case failed(Error)
    }

    @State private var state: LoadState = .loading
    @State private var hasLoaded = false

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
            .onReceive(NotificationCenter.default.publisher(for: .updateSourceList)) { _ in
                // Sources load asynchronously after launch (and on install), so the
                // initial load() can race ahead of them and land on .empty. Re-run
                // once the source list is available so Discover self-heals.
                Task { await reloadIfNeeded() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
            case .loading:
                loadingView
            case let .loaded(source, home):
                loadedView(source: source, home: home)
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
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.nyoraIndigo)
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

    // Placeholder vertical feed proving the home data is wired in. Replaced by
    // the Nyora hero + rails + pager in ND-013..ND-015.
    private func loadedView(source: AidokuRunner.Source, home: Home) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(source.name)
                    .font(.poppins(28, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if let hero = home.heroManga {
                    DiscoverHeroCard(source: source, manga: hero)
                        .padding(.horizontal, 16)
                }

                ForEach(home.components.indices, id: \.self) { index in
                    let component = home.components[index]
                    let manga = component.value.railManga
                    if !manga.isEmpty {
                        // A "big scroller" is the Nyora featured/recommendation
                        // carousel — render it as the swipeable pager (ND-015);
                        // everything else stays a horizontal rail (ND-014).
                        if component.value.isBigScroller {
                            DiscoverRecommendationPager(
                                source: source,
                                title: component.title,
                                manga: manga
                            )
                        } else {
                            DiscoverRailView(
                                source: source,
                                title: component.title,
                                manga: manga
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Loading

    /// Re-run the load only from the "stuck" states, so a good render isn't clobbered
    /// and an in-flight load isn't interrupted when the source list updates.
    private func reloadIfNeeded() async {
        switch state {
            case .empty, .failed: await load()
            case .loading, .loaded: break
        }
    }

    private func load() async {
        state = .loading

        guard let source = SourceManager.shared.sources.first(where: { $0.features.providesHome }) else {
            state = .empty
            return
        }

        do {
            let home = try await source.getHome()
            if home.components.isEmpty {
                state = .empty
            } else {
                state = .loaded(source: source, home: home)
            }
        } catch {
            state = .failed(error)
        }
    }
}

private extension Home {
    /// The first manga entry across the home components, used as the hero.
    var heroManga: AidokuRunner.Manga? {
        for component in components {
            switch component.value {
                case let .bigScroller(entries, _):
                    if let first = entries.first { return first }
                case let .scroller(entries, _):
                    for entry in entries {
                        if case let .manga(manga) = entry.value { return manga }
                    }
                case let .mangaList(_, _, entries, _):
                    for entry in entries {
                        if case let .manga(manga) = entry.value { return manga }
                    }
                case let .mangaChapterList(_, entries, _):
                    if let first = entries.first?.manga { return first }
                default:
                    continue
            }
        }
        return nil
    }
}

private extension HomeComponent.Value {
    /// Whether this is the featured "big scroller" carousel, which Discover
    /// renders as the swipeable recommendation pager rather than a rail.
    var isBigScroller: Bool {
        if case .bigScroller = self { return true }
        return false
    }

    /// The manga entries a horizontal rail can render for this component, if any.
    /// Non-manga components (image scrollers, filters, plain links) yield nothing.
    var railManga: [AidokuRunner.Manga] {
        switch self {
            case let .bigScroller(entries, _):
                entries
            case let .scroller(entries, _):
                entries.compactMap { link in
                    if case let .manga(manga) = link.value { manga } else { nil }
                }
            case let .mangaList(_, _, entries, _):
                entries.compactMap { link in
                    if case let .manga(manga) = link.value { manga } else { nil }
                }
            case let .mangaChapterList(_, entries, _):
                entries.map { $0.manga }
            default:
                []
        }
    }
}
