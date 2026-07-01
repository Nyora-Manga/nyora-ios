//
//  NyoraTheme.swift
//  Aidoku (iOS) — Nyora fork
//
//  Design foundation ported from nyora-android: the Poppins typeface (applied
//  app-wide), the indigo→purple→magenta accent palette on slate surfaces, and
//  the shape tokens (very round, flat, tinted cards + pill buttons + 13:18
//  covers). Per-screen styling in later phases consumes these tokens.
//

import SwiftUI
import UIKit

enum NyoraTheme {
    // MARK: - Palette (nyora-android colors_nyora.xml)
    static let indigo = hex("6366F1")       // primary accent
    static let indigoLight = hex("818CF8")  // dark-mode accent
    static let purple = hex("4F46E5")       // secondary
    static let magenta = hex("D946EF")      // tertiary

    // slate surfaces
    static let slateBackground = hex("F8FAFC")
    static let slateOnSurface = hex("0F172A")

    /// Parse a 6-digit hex string → UIColor (own copy; the app's is fileprivate).
    static func hex(_ string: String) -> UIColor {
        var str = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let value = UInt32(str, radix: 16) else { return .systemIndigo }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    // MARK: - Shape tokens
    static let cornerCard: CGFloat = 20
    static let cornerCover: CGFloat = 12
    static let cornerHero: CGFloat = 24
    static let cornerPill: CGFloat = 999 // fully rounded (Android used 100dp)
    static let coverAspectRatio: CGFloat = 13.0 / 18.0 // w:h

    // MARK: - Poppins
    static func poppinsName(_ weight: UIFont.Weight) -> String {
        switch weight {
        case .black, .heavy: "Poppins-Black"
        case .bold: "Poppins-Bold"
        case .semibold: "Poppins-SemiBold"
        case .medium: "Poppins-Medium"
        default: "Poppins-Regular"
        }
    }

    static func poppins(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        UIFont(name: poppinsName(weight), size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// Install Poppins app-wide + set nav/tab bar fonts. Call once at launch.
    static func applyGlobally() {
        UIFont.nyoraInstallPoppins()

        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.titleTextAttributes = [.font: poppins(17, .semibold)]
        nav.largeTitleTextAttributes = [.font: poppins(32, .bold)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        UITabBarItem.appearance().setTitleTextAttributes([.font: poppins(10, .medium)], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: poppins(10, .semibold)], for: .selected)
    }
}

// MARK: - SwiftUI Font

extension Font {
    static func poppins(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .black, .heavy: name = "Poppins-Black"
        case .bold: name = "Poppins-Bold"
        case .semibold: name = "Poppins-SemiBold"
        case .medium: name = "Poppins-Medium"
        default: name = "Poppins-Regular"
        }
        return .custom(name, size: size)
    }
}

extension Color {
    static let nyoraIndigo = Color(uiColor: NyoraTheme.indigo)
    static let nyoraPurple = Color(uiColor: NyoraTheme.purple)
    static let nyoraMagenta = Color(uiColor: NyoraTheme.magenta)
}

// MARK: - App-wide Poppins via system-font swizzle
//
// Swaps UIFont's system-font factories for Poppins so both UIKit labels and
// SwiftUI Text (which resolve fonts through UIFont) pick it up without touching
// every call site. monospacedDigit* is intentionally left alone (page counters).

extension UIFont {
    private static var didInstallPoppins = false

    static func nyoraInstallPoppins() {
        guard !didInstallPoppins else { return }
        didInstallPoppins = true
        exchange(#selector(systemFont(ofSize:)), #selector(nyora_systemFont(ofSize:)))
        exchange(#selector(systemFont(ofSize:weight:)), #selector(nyora_systemFont(ofSize:weight:)))
        exchange(#selector(boldSystemFont(ofSize:)), #selector(nyora_boldSystemFont(ofSize:)))
        exchange(#selector(preferredFont(forTextStyle:)), #selector(nyora_preferredFont(forTextStyle:)))
    }

    private static func exchange(_ original: Selector, _ swizzled: Selector) {
        guard
            let m1 = class_getClassMethod(self, original),
            let m2 = class_getClassMethod(self, swizzled)
        else { return }
        method_exchangeImplementations(m1, m2)
    }

    // After exchange, calling the "nyora_" selector below actually invokes the ORIGINAL impl.
    @objc private class func nyora_systemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(name: "Poppins-Regular", size: size) ?? nyora_systemFont(ofSize: size)
    }

    @objc private class func nyora_systemFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFont(name: NyoraTheme.poppinsName(weight), size: size) ?? nyora_systemFont(ofSize: size, weight: weight)
    }

    @objc private class func nyora_boldSystemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(name: "Poppins-Bold", size: size) ?? nyora_boldSystemFont(ofSize: size)
    }

    @objc private class func nyora_preferredFont(forTextStyle style: UIFont.TextStyle) -> UIFont {
        let original = nyora_preferredFont(forTextStyle: style) // original (post-swap)
        let heavy: Set<UIFont.TextStyle> = [.largeTitle, .title1, .title2, .title3, .headline]
        let weight: UIFont.Weight = heavy.contains(style) ? .semibold : .regular
        return UIFont(name: NyoraTheme.poppinsName(weight), size: original.pointSize) ?? original
    }
}
