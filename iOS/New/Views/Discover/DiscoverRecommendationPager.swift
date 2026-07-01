//
//  DiscoverRecommendationPager.swift
//  Aidoku (iOS) — Nyora fork
//
//  ND-015 — Discover recommendation pager.
//
//  A swipeable pager ported from nyora-android's item_recommendation.xml /
//  item_recommendation_manga.xml: a horizontal ViewPager2 of recommendation
//  cards (cover + title + description) with a DotsIndicator beneath it. Here it
//  is rebuilt natively with a paging TabView and a custom indigo dots indicator
//  (the Android DotsIndicator uses tinted dots that grow for the active page).
//

import AidokuRunner
import SwiftUI

struct DiscoverRecommendationPager: View {
    let source: AidokuRunner.Source?
    let title: String?
    let manga: [AidokuRunner.Manga]
    /// When set, taps invoke this instead of opening source details directly.
    var onSelect: ((AidokuRunner.Manga) -> Void)?

    @State private var selection = 0

    // nyora-android recommendation_item_height = 90dp; give it a little more
    // breathing room for the iOS card outline + padding.
    private static let pageHeight: CGFloat = 104

    // Cap the pager so the dots row stays legible with many trending items —
    // one dot per page becomes an unreadable strip past ~8 pages.
    private static let maxPages = 8

    private var pages: [AidokuRunner.Manga] {
        Array(manga.prefix(Self.maxPages))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.poppins(18, weight: .semibold))
                    .padding(.horizontal, 16)
            }

            TabView(selection: $selection) {
                ForEach(pages.indices, id: \.self) { index in
                    DiscoverRecommendationCard(source: source, manga: pages[index], onSelect: onSelect)
                        .padding(.horizontal, 16)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: Self.pageHeight)

            if pages.count > 1 {
                DotsIndicator(count: pages.count, selection: selection)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct DiscoverRecommendationCard: View {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    var onSelect: ((AidokuRunner.Manga) -> Void)?

    @EnvironmentObject private var path: NavigationCoordinator

    private static let coverHeight: CGFloat = 72
    private var coverWidth: CGFloat {
        (Self.coverHeight * NyoraTheme.coverAspectRatio).rounded()
    }

    private var subtitle: String? {
        if let description = manga.description, !description.isEmpty {
            return description
        }
        if let authors = manga.authors, !authors.isEmpty {
            return authors.joined(separator: ", ")
        }
        return nil
    }

    var body: some View {
        Button(action: openDetails) {
            HStack(alignment: .top, spacing: 14) {
                SourceImageView(
                    source: source,
                    imageUrl: manga.cover ?? "",
                    downsampleWidth: 200,
                    contentMode: .fill,
                    showsLoadingIndicator: true
                )
                .frame(width: coverWidth, height: Self.coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: NyoraTheme.cornerCover, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: NyoraTheme.cornerCover, style: .continuous)
                        .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(manga.title)
                        .font(.poppins(16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.poppins(13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nyoraTintedCard()
        }
        .buttonStyle(.plain)
    }

    private func openDetails() {
        if let onSelect {
            onSelect(manga)
        } else if let source {
            path.push(MangaViewController(source: source, manga: manga, parent: path.rootViewController))
        }
    }
}

/// Nyora dots indicator: tinted indigo dots where the active page's dot grows
/// into a pill, mirroring nyora-android's DotsIndicator (dotScale/dotAlpha).
private struct DotsIndicator: View {
    let count: Int
    let selection: Int
    @ObservedObject private var accentManager = AccentManager.shared

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                let active = index == selection
                Capsule()
                    .fill(accentManager.color.opacity(active ? 1 : 0.35))
                    .frame(width: active ? 18 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: selection)
            }
        }
        .padding(.vertical, 4)
    }
}
