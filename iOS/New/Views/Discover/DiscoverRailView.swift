//
//  DiscoverRailView.swift
//  Aidoku (iOS) — Nyora fork
//
//  ND-014 — Discover horizontal RAIL.
//
//  A section of the Discover feed ported from nyora-android's item_discover_rail.xml
//  / item_discover_rail_card.xml: a section title above a horizontal scroller of
//  140pt-wide flat bordered cards. Each card is a 13:18 full-bleed cover with a
//  2-line Poppins-SemiBold title beneath it, and taps through to manga details.
//

import AidokuRunner
import SwiftUI

struct DiscoverRailView: View {
    let source: AidokuRunner.Source
    let title: String?
    let manga: [AidokuRunner.Manga]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.poppins(18, weight: .semibold))
                    .padding(.horizontal, 16)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(manga.indices, id: \.self) { index in
                        DiscoverRailCard(source: source, manga: manga[index])
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct DiscoverRailCard: View {
    let source: AidokuRunner.Source
    let manga: AidokuRunner.Manga

    @EnvironmentObject private var path: NavigationCoordinator

    // nyora-android item_discover_rail_card.xml: 140dp wide, 16dp corners, 1px outline.
    private static let width: CGFloat = 140
    private static let corner: CGFloat = 16

    private var coverHeight: CGFloat {
        (Self.width / NyoraTheme.coverAspectRatio).rounded()
    }

    var body: some View {
        Button(action: openDetails) {
            VStack(alignment: .leading, spacing: 0) {
                SourceImageView(
                    source: source,
                    imageUrl: manga.cover ?? "",
                    downsampleWidth: 300,
                    contentMode: .fill
                )
                .frame(width: Self.width, height: coverHeight)
                .clipped()

                Text(manga.title)
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

    private func openDetails() {
        path.push(MangaViewController(source: source, manga: manga, parent: path.rootViewController))
    }
}
