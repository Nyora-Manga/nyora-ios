//
//  LibraryDisplayMode.swift
//  Aidoku
//
//  Nyora port: NP-011 library list display mode (list / detailed / grid).
//

import UIKit

/// The three ways the library can lay out its manga entries, mirroring
/// nyora-android's `ListMode` (LIST / DETAILED_LIST / GRID).
enum LibraryDisplayMode: Int, CaseIterable {
    /// Cover-only grid (the default).
    case grid = 0
    /// Compact single-line list with a small cover thumbnail.
    case list = 1
    /// Detailed list with a large cover, subtitle and tags.
    case detailed = 2

    static let userDefaultsKey = "Library.displayMode"
    private static let legacyListKey = "Library.listView"

    /// Reads the persisted mode, migrating from the legacy `Library.listView`
    /// boolean the first time (true -> detailed list, false -> grid).
    static var current: LibraryDisplayMode {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: userDefaultsKey) == nil {
                return defaults.bool(forKey: legacyListKey) ? .detailed : .grid
            }
            return LibraryDisplayMode(rawValue: defaults.integer(forKey: userDefaultsKey)) ?? .grid
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
            // keep the legacy key in sync so other surfaces stay consistent
            UserDefaults.standard.set(newValue != .grid, forKey: legacyListKey)
        }
    }

    var title: String {
        switch self {
            case .grid: NSLocalizedString("LAYOUT_GRID")
            case .list: NSLocalizedString("LAYOUT_LIST")
            case .detailed: NSLocalizedString("LAYOUT_DETAILED_LIST")
        }
    }

    var image: UIImage? {
        switch self {
            case .grid: UIImage(systemName: "square.grid.2x2")
            case .list: UIImage(systemName: "list.bullet")
            case .detailed: UIImage(systemName: "list.bullet.below.rectangle")
        }
    }
}
