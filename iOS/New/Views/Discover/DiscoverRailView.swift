//
//  DiscoverRailView.swift
//  Aidoku (iOS) — Nyora fork
//
//  Discover horizontal RAIL, redesigned 1:1 with nyora-web's `.discover-rail`:
//  a header (title + a "Show all" tonal pill) above a horizontal scroller of
//  138pt cards. Each card is a 2:3 cover filling a rounded surface card, with a
//  single dark-blurred lead-genre chip pinned to the cover's bottom-left and a
//  2-line title beneath. Tapping a card runs a title search.
//

import SwiftUI

struct DiscoverRailView: View {
    let title: String
    let items: [DiscoverItem]
    let onSelect: (DiscoverItem) -> Void
    var onShowAll: (() -> Void)?

    @ObservedObject private var accentManager = AccentManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.poppins(18, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let onShowAll {
                    Button(action: onShowAll) {
                        Text(NSLocalizedString("SHOW_ALL", comment: ""))
                            .font(.poppins(13, weight: .semibold))
                            .foregroundStyle(accentManager.color)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.nyoraCardSurface)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.nyoraCardOutline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        DiscoverRailCard(item: item) { onSelect(item) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct DiscoverRailCard: View {
    let item: DiscoverItem
    let onTap: () -> Void

    // nyora-web: 138px cards, 2:3 cover, 18–20px radius surface card.
    private static let width: CGFloat = 138
    private static let corner: CGFloat = 18
    private var coverHeight: CGFloat { (Self.width * 3 / 2).rounded() }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    SourceImageView(
                        imageUrl: item.cover ?? "",
                        downsampleWidth: 300,
                        contentMode: .fill,
                        showsLoadingIndicator: true
                    )
                    .frame(width: Self.width, height: coverHeight)
                    .clipped()

                    if let genre = item.genres.first {
                        Text(genre)
                            .font(.poppins(11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .background(Color.black.opacity(0.35), in: Capsule())
                            .padding(8)
                    }
                }

                Text(item.title)
                    .font(.poppins(13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
            .frame(width: Self.width)
            .background(Color.nyoraCardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
