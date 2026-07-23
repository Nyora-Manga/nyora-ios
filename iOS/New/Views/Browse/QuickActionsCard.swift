//
//  QuickActionsCard.swift
//  Aidoku (iOS) — Nyora fork
//
//  Explore "quick actions": a flat tinted card holding a row of tall tonal buttons
//  (Local / Bookmarks / Downloads), ported from nyora-android's item_explore_buttons.xml.
//  Purely presentational — each tile invokes a closure supplied by the host screen so
//  navigation/data flow stay owned by BrowseViewController.
//

import SwiftUI

struct QuickActionsCard: View {
    var onLocal: () -> Void
    var onBookmarks: () -> Void
    var onDownloads: () -> Void

    var body: some View {
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
            QuickActionTile(
                title: NSLocalizedString("DOWNLOADS", comment: ""),
                systemImage: "arrow.down.circle",
                action: onDownloads
            )
        }
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
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accentManager.color)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(accentManager.color.opacity(0.15)))
                Text(title)
                    .font(.poppins(13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(
                RoundedRectangle(cornerRadius: NyoraTheme.cornerCard, style: .continuous)
                    .fill(Color.nyoraCardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NyoraTheme.cornerCard, style: .continuous)
                    .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: NyoraTheme.cornerCard, style: .continuous))
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
        onDownloads: {}
    )
    .padding(.vertical)
    .background(Color(uiColor: NyoraTheme.slateBackground))
}
