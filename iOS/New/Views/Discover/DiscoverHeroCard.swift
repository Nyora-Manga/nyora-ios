//
//  DiscoverHeroCard.swift
//  Aidoku (iOS) — Nyora fork
//
//  Discover HERO — the #1 trending title, redesigned 1:1 with nyora-web's
//  `.discover-hero`: a rounded accent-tinted card with a heavily-blurred, low-opacity
//  copy of the cover behind it, the real cover on the left (2:3), and on the right an
//  uppercase accent "TRENDING" eyebrow, the title, a chip row (green score% + up to 3
//  genres), and an accent "Read" pill. The whole card taps through to a title search.
//

import SwiftUI

struct DiscoverHeroCard: View {
    let item: DiscoverItem
    let onSelect: (DiscoverItem) -> Void

    static let height: CGFloat = 208

    @ObservedObject private var accentManager = AccentManager.shared

    private var genres: [String] { Array(item.genres.prefix(3)) }
    private var accent: Color { accentManager.color }

    var body: some View {
        Button {
            onSelect(item)
        } label: {
            HStack(spacing: 16) {
                // Left: the real cover (2:3).
                SourceImageView(
                    imageUrl: item.cover ?? "",
                    downsampleWidth: 300,
                    contentMode: .fill,
                    showsLoadingIndicator: true
                )
                .frame(width: 116, height: 174)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Right: eyebrow / title / chips / Read pill.
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("TRENDING", comment: ""))
                        .font(.poppins(11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(accent)

                    Text(item.title)
                        .font(.poppins(20, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    chips

                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(NSLocalizedString("READ", comment: ""))
                            .font(.poppins(14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(accent)
                    .clipShape(Capsule())
                    .padding(.top, 2)

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(height: Self.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(heroBackground)
            .clipShape(RoundedRectangle(cornerRadius: NyoraTheme.cornerHero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NyoraTheme.cornerHero, style: .continuous)
                    .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var chips: some View {
        HStack(spacing: 6) {
            if let score = item.score {
                Text("\(score)%")
                    .font(.poppins(11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hue: 0.41, saturation: 0.6, brightness: 0.75)) // green
                    .clipShape(Capsule())
            }
            ForEach(genres, id: \.self) { genre in
                Text(genre)
                    .font(.poppins(11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.nyoraCardSurface)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.nyoraCardOutline, lineWidth: 1))
            }
        }
        .lineLimit(1)
    }

    // Accent-tinted base with a blurred, low-opacity copy of the cover/banner behind it.
    private var heroBackground: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.14), Color.nyoraCardSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            SourceImageView(
                imageUrl: (item.banner ?? item.cover) ?? "",
                downsampleWidth: 240,
                contentMode: .fill
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .blur(radius: 32)
            .opacity(0.28)
            .allowsHitTesting(false)
        }
    }
}
