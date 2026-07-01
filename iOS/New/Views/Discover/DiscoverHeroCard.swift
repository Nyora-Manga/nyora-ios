//
//  DiscoverHeroCard.swift
//  Aidoku (iOS) — Nyora fork
//
//  ND-013 — Discover HERO card.
//
//  The signature full-width hero at the top of the Discover feed, ported from
//  nyora-android's item_discover_hero.xml. A ~240pt tall card at the Nyora hero
//  corner radius (24pt) with a full-bleed cover, a left→right dark gradient for
//  legibility, and a bottom-left block carrying a Poppins-bold title, genre
//  labels, and a white "Read" pill (NyoraPillButtonStyle .nyoraPillWhite) that
//  opens the manga details.
//

import AidokuRunner
import SwiftUI

struct DiscoverHeroCard: View {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    /// When set, taps invoke this instead of opening source details directly.
    /// Used by the AniList feed to run a universal search for the title.
    var onSelect: ((AidokuRunner.Manga) -> Void)?

    static let height: CGFloat = 240

    @EnvironmentObject private var path: NavigationCoordinator

    private var genres: [String] {
        Array((manga.tags ?? []).prefix(3))
    }

    var body: some View {
        Button(action: openDetails) {
            ZStack(alignment: .bottomLeading) {
                // Full-bleed cover
                SourceImageView(
                    source: source,
                    imageUrl: manga.cover ?? "",
                    downsampleWidth: 800,
                    contentMode: .fill
                )
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .clipped()

                // Left→right dark gradient for legibility of the text block
                LinearGradient(
                    colors: [
                        .black.opacity(0.78),
                        .black.opacity(0.35),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                // Extra bottom darkening so genres/title stay readable
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )

                // Bottom-left content block
                VStack(alignment: .leading, spacing: 10) {
                    Text(manga.title)
                        .font(.poppins(24, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !genres.isEmpty {
                        Text(genres.joined(separator: "  •  "))
                            .font(.poppins(12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    // White "Read" pill — non-interactive here; the whole card taps
                    // through to details, matching the Android hero behaviour.
                    Text(NSLocalizedString("READ", comment: ""))
                        .font(.poppins(15, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .padding(.top, 2)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: NyoraTheme.cornerHero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NyoraTheme.cornerHero, style: .continuous)
                    .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
            )
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
