//
//  NyoraPillButtonStyle.swift
//  Aidoku (iOS) — Nyora fork
//
//  Fully-rounded "pill" button ported from nyora-android's
//  Widget.Nyora.Button (cornerRadius 100dp, Poppins SemiBold label).
//  Two variants match the Android design language:
//   - .indigo: solid indigo fill with white label (primary CTA)
//   - .white:  white fill with black label (the Discover HERO "Read" pill)
//

import SwiftUI

struct NyoraPillButtonStyle: ButtonStyle {
    enum Variant {
        case indigo
        case white
    }

    var variant: Variant = .indigo
    /// Horizontal content padding; the pill hugs its label by default.
    var horizontalPadding: CGFloat = 20
    var verticalPadding: CGFloat = 10
    var fontSize: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        let (fill, label) = colors
        configuration.label
            .font(.poppins(fontSize, weight: .semibold))
            .foregroundStyle(label)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(fill)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var colors: (fill: Color, label: Color) {
        switch variant {
        case .indigo: (.nyoraIndigo, .white)
        case .white: (.white, .black)
        }
    }
}

extension ButtonStyle where Self == NyoraPillButtonStyle {
    /// Solid indigo pill with a white Poppins SemiBold label (primary CTA).
    static var nyoraPill: NyoraPillButtonStyle { NyoraPillButtonStyle(variant: .indigo) }

    /// White pill with a black label — the Discover HERO "Read" button.
    static var nyoraPillWhite: NyoraPillButtonStyle { NyoraPillButtonStyle(variant: .white) }
}

#Preview {
    VStack(spacing: 16) {
        Button("Read") {}
            .buttonStyle(.nyoraPill)
        Button("Read") {}
            .buttonStyle(.nyoraPillWhite)
    }
    .padding()
    .background(Color(uiColor: NyoraTheme.slateBackground))
}
