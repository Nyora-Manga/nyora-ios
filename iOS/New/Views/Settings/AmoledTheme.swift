//
//  AmoledTheme.swift
//  Aidoku (iOS)
//
//  Nyora port (NP-010): AMOLED pure-black dark theme.
//
//  Mirrors nyora-android's `ThemeOverlay.Nyora.Amoled`, which swaps the surface /
//  background colors to pure black in dark mode. On iOS we achieve the app-wide
//  swap by swizzling the semantic background `UIColor` getters so that — while the
//  toggle is on and the current trait collection is dark — they resolve to true
//  black. The swizzled getters re-check the flag at resolve time, so toggling takes
//  effect on the next redraw (and never affects light mode).
//

import UIKit

enum AmoledTheme {
    /// UserDefaults key the whole app reads from.
    static let defaultsKey = "Appearance.amoled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    private static var installed = false

    /// Wraps an original semantic color so it resolves to pure black in dark mode
    /// while the AMOLED flag is enabled, and otherwise falls back to the original.
    static func wrap(_ original: UIColor) -> UIColor {
        UIColor { traits in
            if isEnabled && traits.userInterfaceStyle == .dark {
                return .black
            }
            return original.resolvedColor(with: traits)
        }
    }

    /// Installs the background-color swizzles. Safe to call multiple times.
    static func install() {
        guard !installed else { return }
        installed = true

        let pairs: [(Selector, Selector)] = [
            (#selector(getter: UIColor.systemBackground), #selector(getter: UIColor.amoled_systemBackground)),
            (#selector(getter: UIColor.secondarySystemBackground), #selector(getter: UIColor.amoled_secondarySystemBackground)),
            (#selector(getter: UIColor.tertiarySystemBackground), #selector(getter: UIColor.amoled_tertiarySystemBackground)),
            (#selector(getter: UIColor.systemGroupedBackground), #selector(getter: UIColor.amoled_systemGroupedBackground)),
            (#selector(getter: UIColor.secondarySystemGroupedBackground), #selector(getter: UIColor.amoled_secondarySystemGroupedBackground)),
            (#selector(getter: UIColor.tertiarySystemGroupedBackground), #selector(getter: UIColor.amoled_tertiarySystemGroupedBackground))
        ]

        // These are class properties, so swizzle on the metaclass.
        guard let metaclass = object_getClass(UIColor.self) else { return }
        for (original, replacement) in pairs {
            guard
                let originalMethod = class_getClassMethod(UIColor.self, original),
                let replacementMethod = class_getClassMethod(UIColor.self, replacement)
            else { continue }
            _ = metaclass // silence unused in case of future refactors
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }

    /// Forces visible windows to redraw so a toggle change is reflected immediately.
    static func refreshAllWindows() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                let style = window.overrideUserInterfaceStyle
                // Nudge the trait environment so cached background colors are re-resolved.
                window.overrideUserInterfaceStyle = style == .unspecified ? .unspecified : style
                window.subviews.forEach { $0.setNeedsLayout() }
                window.rootViewController?.view.setNeedsDisplay()
            }
        }
    }
}

// After `method_exchangeImplementations`, calling the `amoled_*` selector invokes
// the *original* implementation, so `Self.wrap(self.amoled_x)` wraps the real color.
extension UIColor {
    @objc class var amoled_systemBackground: UIColor {
        AmoledTheme.wrap(self.amoled_systemBackground)
    }
    @objc class var amoled_secondarySystemBackground: UIColor {
        AmoledTheme.wrap(self.amoled_secondarySystemBackground)
    }
    @objc class var amoled_tertiarySystemBackground: UIColor {
        AmoledTheme.wrap(self.amoled_tertiarySystemBackground)
    }
    @objc class var amoled_systemGroupedBackground: UIColor {
        AmoledTheme.wrap(self.amoled_systemGroupedBackground)
    }
    @objc class var amoled_secondarySystemGroupedBackground: UIColor {
        AmoledTheme.wrap(self.amoled_secondarySystemGroupedBackground)
    }
    @objc class var amoled_tertiarySystemGroupedBackground: UIColor {
        AmoledTheme.wrap(self.amoled_tertiarySystemGroupedBackground)
    }
}

extension Notification.Name {
    static let amoledThemeChanged = Notification.Name("Appearance.amoledChanged")
}
