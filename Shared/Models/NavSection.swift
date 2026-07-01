//
//  NavSection.swift
//  Aidoku
//
//  Main-screen navigation configuration (ported from nyora-android NavItem / nav_main).
//

import Foundation

/// A bottom-tab section in the main screen. Mirrors nyora-android's `NavItem`,
/// mapped onto Aidoku's tab set (Library / Browse / History / Search / Settings).
enum NavSection: String, CaseIterable {
    case discover
    case library
    case browse
    case history
    case search
    case settings

    var title: String {
        switch self {
            case .discover: NSLocalizedString("DISCOVER")
            // Nyora nav labels: Library surfaces the user's Favourites, Browse is Explore
            case .library: NSLocalizedString("NAV_FAVOURITES")
            case .browse: NSLocalizedString("NAV_EXPLORE")
            case .history: NSLocalizedString("HISTORY")
            case .search: NSLocalizedString("SEARCH")
            case .settings: NSLocalizedString("SETTINGS")
        }
    }

    var systemImage: String {
        switch self {
            case .discover: "sparkles"
            case .library: "books.vertical.fill"
            case .browse: "globe"
            case .history: "clock.fill"
            case .search: "magnifyingglass"
            case .settings: "gear"
        }
    }

    /// Sections that can never be hidden (so the user can always reach settings again).
    var isRequired: Bool {
        self == .settings
    }
}

/// Persistence + defaults for the main-screen navigation config (`Appearance.navSections`).
///
/// Storage mirrors nyora-android's `mainNavItems`: an ordered list of the *enabled*
/// section raw values. Any section not present in the list is considered disabled.
enum NavConfig {
    static let key = "Appearance.navSections"

    /// Nyora nav destinations (mirrors nyora-android): Discover / Favourites / Explore / History / Settings.
    /// Universal search lives in the Discover top bar (not a bottom tab), so `.search` is not a default tab
    /// but remains available as an opt-in section in NavConfigView.
    static let defaultSections: [NavSection] = [.discover, .library, .browse, .history, .settings]

    /// The ordered list of enabled sections, always guaranteeing the required
    /// sections are present and at least one browsable section exists.
    static var enabledSections: [NavSection] {
        var sections: [NavSection]
        if let raw = UserDefaults.standard.array(forKey: key) as? [String] {
            sections = raw.compactMap(NavSection.init)
        } else {
            sections = defaultSections
        }
        // ensure required sections are always present
        for required in NavSection.allCases where required.isRequired && !sections.contains(required) {
            sections.append(required)
        }
        // never allow an entirely empty (or settings-only) nav bar
        if sections.allSatisfy(\.isRequired) {
            sections = defaultSections
        }
        return sections
    }

    static func isEnabled(_ section: NavSection) -> Bool {
        enabledSections.contains(section)
    }

    /// Persist the ordered list of enabled sections and notify observers.
    static func save(_ sections: [NavSection]) {
        var sections = sections
        for required in NavSection.allCases where required.isRequired && !sections.contains(required) {
            sections.append(required)
        }
        UserDefaults.standard.set(sections.map(\.rawValue), forKey: key)
        NotificationCenter.default.post(name: .init(key), object: nil)
    }

    static func registerDefault() {
        UserDefaults.standard.register(defaults: [key: defaultSections.map(\.rawValue)])
    }
}
