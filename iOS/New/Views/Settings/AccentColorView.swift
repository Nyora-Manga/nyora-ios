//
//  AccentColorView.swift
//  Aidoku (iOS)
//
//  Nyora port (NP-009): accent / color-theme system.
//

import SwiftUI
import UIKit

/// A named accent palette. Modeled after nyora-android's ColorScheme themes,
/// each backed by a light/dark primary color that drives the app-wide tint.
enum AccentColor: String, CaseIterable, Identifiable {
    case `default`
    case totoro
    case miku
    case asuka
    case mion
    case rikka
    case sakura
    case mamimi
    case itsuka
    case kanade
    case yuki

    var id: String { rawValue }

    /// The UserDefaults key the whole app reads from.
    static let defaultsKey = "Appearance.accentColor"

    /// Currently selected accent, falling back to `.default`.
    static var current: AccentColor {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? AccentColor.default.rawValue
        return AccentColor(rawValue: raw) ?? .default
    }

    var title: String {
        switch self {
        case .default: NSLocalizedString("DEFAULT")
        case .totoro: "Totoro"
        case .miku: "Miku"
        case .asuka: "Asuka"
        case .mion: "Mion"
        case .rikka: "Rikka"
        case .sakura: "Sakura"
        case .mamimi: "Mamimi"
        case .itsuka: "Itsuka"
        case .kanade: "Kanade"
        case .yuki: "Yuki"
        }
    }

    /// Primary color in light mode (hex).
    private var lightHex: String {
        switch self {
        case .default: "FF2D55" // systemPink-ish
        case .totoro: "3C6090"
        case .miku: "00696D"
        case .asuka: "904A40"
        case .mion: "3B693A"
        case .rikka: "68548D"
        case .sakura: "8C4A60"
        case .mamimi: "465D91"
        case .itsuka: "974800"
        case .kanade: "353543"
        case .yuki: "43474A"
        }
    }

    /// Primary color in dark mode (hex).
    private var darkHex: String {
        switch self {
        case .default: "FF375F"
        case .totoro: "A6C8FF"
        case .miku: "6FDDE2"
        case .asuka: "FFB4A8"
        case .mion: "A1D39A"
        case .rikka: "D3BBFD"
        case .sakura: "FFB1C8"
        case .mamimi: "AFC6FF"
        case .itsuka: "FFBA8F"
        case .kanade: "C6C5D0"
        case .yuki: "C3C7CF"
        }
    }

    /// A dynamic UIColor resolving to the right primary per interface style.
    var uiColor: UIColor {
        if self == .default {
            return .systemPink
        }
        let light = UIColor(hex: lightHex) ?? .systemPink
        let dark = UIColor(hex: darkHex) ?? light
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

extension UIColor {
    fileprivate convenience init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let value = UInt32(str, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Notification.Name {
    static let accentColorChanged = Notification.Name("Appearance.accentColorChanged")
}

/// Applies the current accent tint to a window, and installs a live observer.
enum AccentColorApplier {
    private static var observer: NSObjectProtocol?

    static func apply(to window: UIWindow?) {
        window?.tintColor = AccentColor.current.uiColor
    }

    /// Registers a single app-wide observer that re-tints all windows on change.
    static func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .accentColorChanged,
            object: nil,
            queue: .main
        ) { _ in
            let tint = AccentColor.current.uiColor
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    window.tintColor = tint
                }
            }
        }
    }
}

/// Inline horizontal picker of named accent palettes, shown in appearance settings.
struct AccentColorView: View {
    @State private var selected = AccentColor.current

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(AccentColor.allCases) { accent in
                    swatch(accent)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func swatch(_ accent: AccentColor) -> some View {
        let isSelected = accent == selected
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(accent.color)
                    .frame(width: 40, height: 40)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(
                        isSelected ? Color.primary : Color.clear,
                        lineWidth: 2
                    )
                    .padding(-3)
            )
            Text(accent.title)
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard accent != selected else { return }
            selected = accent
            UserDefaults.standard.set(accent.rawValue, forKey: AccentColor.defaultsKey)
            NotificationCenter.default.post(name: .accentColorChanged, object: nil)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
