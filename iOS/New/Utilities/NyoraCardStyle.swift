//
//  NyoraCardStyle.swift
//  Aidoku (iOS) — Nyora fork
//
//  Flat "tinted surface" card ported from nyora-android's Widget.Nyora.Card:
//  zero elevation, depth conveyed purely by a subtly-tinted surface fill plus a
//  1px outline. Corners default to the cornerCard token (20pt). No shadow.
//
//  Usage: `SomeView().nyoraTintedCard()` or `.nyoraTintedCard(cornerRadius:)`.
//

import SwiftUI
import UIKit

struct NyoraTintedCardModifier: ViewModifier {
    var cornerRadius: CGFloat = NyoraTheme.cornerCard
    /// Content inset applied inside the card. Pass 0 for edge-to-edge fills
    /// (e.g. cover art) and add padding manually.
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .padding(padding)
            .background(shape.fill(Color.nyoraCardSurface))
            .overlay(shape.strokeBorder(Color.nyoraCardOutline, lineWidth: 1))
            .clipShape(shape)
    }
}

extension View {
    /// Applies the Nyora flat tinted-surface card: tinted fill + 1px outline,
    /// 20pt corners, no shadow. Matches nyora-android's Widget.Nyora.Card.
    func nyoraTintedCard(
        cornerRadius: CGFloat = NyoraTheme.cornerCard,
        padding: CGFloat = 0
    ) -> some View {
        modifier(NyoraTintedCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

extension Color {
    /// Faintly-tinted card surface (nyora-android surfaceVariant / inverseSurface),
    /// adapting between light and dark appearances.
    static let nyoraCardSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? NyoraTheme.hex("1E293B")   // slate 800
            : NyoraTheme.hex("F1F5F9")   // slate 100
    })

    /// 1px card outline — a low-opacity indigo tint on the surface edge.
    static let nyoraCardOutline = Color(uiColor: UIColor { traits in
        NyoraTheme.indigo.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.22 : 0.14)
    })
}

#Preview {
    VStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tinted Card")
                .font(.poppins(17, weight: .semibold))
            Text("Flat surface, 1px outline, no shadow.")
                .font(.poppins(13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nyoraTintedCard(padding: 16)

        Text("Cover corners")
            .font(.poppins(13, weight: .medium))
            .frame(maxWidth: .infinity)
            .nyoraTintedCard(cornerRadius: NyoraTheme.cornerCover, padding: 24)
    }
    .padding()
    .background(Color(uiColor: NyoraTheme.slateBackground))
}
