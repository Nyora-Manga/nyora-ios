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
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await load()
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

                ForEach(home.components.indices, id: \.self) { index in
                    let component = home.components[index]
                    VStack(alignment: .leading, spacing: 6) {
                        if let title = component.title, !title.isEmpty {
                            Text(title)
                                .font(.poppins(18, weight: .semibold))
                        }
                        Text(String(
                            format: NSLocalizedString("DISCOVER_SECTION_COUNT", comment: ""),
                            component.value.approximateEntryCount
                        ))
                        .font(.poppins(13, weight: .regular))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .nyoraTintedCard()
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Loading

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

private extension HomeComponent.Value {
    /// Best-effort entry count for the scaffold overview.
    var approximateEntryCount: Int {
        switch self {
            case let .imageScroller(links, _, _, _): links.count
            case let .bigScroller(entries, _): entries.count
            case let .scroller(entries, _): entries.count
            case let .mangaList(_, _, entries, _): entries.count
            case let .mangaChapterList(_, entries, _): entries.count
            case let .filters(items): items.count
            case let .links(links): links.count
        }
    }
}
