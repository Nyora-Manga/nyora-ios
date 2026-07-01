//
//  QuickActionsCard.swift
//  Aidoku (iOS) — Nyora fork
//
//  Explore "quick actions": a flat tinted card holding a 2×2 grid of tall
//  tonal buttons (Local / Bookmarks / Random / Downloads), ported from
//  nyora-android's item_explore_buttons.xml. Purely presentational — each tile
//  invokes a closure supplied by the host screen so navigation/data flow stay
//  owned by BrowseViewController.
//

import SwiftUI

struct QuickActionsCard: View {
    var onLocal: () -> Void
    var onBookmarks: () -> Void
    var onRandom: () -> Void
    var onDownloads: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                QuickActionTile(
                    title: NSLocalizedString("LOCAL_FILES", comment: ""),
                    systemImage: "folder",
                    action: onLocal
                )
                QuickActionTile(
                    title: NSLocalizedString("BOOKMARKS", comment: ""),
                    systemImage: "bookmark",
                    action: onBookmarks
                )
            }
            HStack(spacing: 10) {
                QuickActionTile(
                    title: NSLocalizedString("RANDOM", comment: ""),
                    systemImage: "dice",
                    action: onRandom
                )
                QuickActionTile(
                    title: NSLocalizedString("DOWNLOADS", comment: ""),
                    systemImage: "arrow.down.circle",
                    action: onDownloads
                )
            }
        }
        .nyoraTintedCard(padding: 12)
        .padding(.horizontal, 16)
    }
}

private struct QuickActionTile: View {
    var title: String
    var systemImage: String
    var action: () -> Void
    @ObservedObject private var accentManager = AccentManager.shared

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accentManager.color)
                Text(title)
                    .font(.poppins(13, weight: .semibold))
                    .foregroundStyle(accentManager.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(
                RoundedRectangle(cornerRadius: NyoraTheme.cornerCover, style: .continuous)
                    .fill(accentManager.color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NyoraTheme.cornerCover, style: .continuous)
                    .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: NyoraTheme.cornerCover, style: .continuous))
        }
        .buttonStyle(QuickActionTileButtonStyle())
    }
}

private struct QuickActionTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    QuickActionsCard(
        onLocal: {},
        onBookmarks: {},
        onRandom: {},
        onDownloads: {}
    )
    .padding(.vertical)
    .background(Color(uiColor: NyoraTheme.slateBackground))
}
