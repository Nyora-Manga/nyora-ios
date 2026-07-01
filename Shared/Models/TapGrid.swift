//
//  TapGrid.swift
//  Aidoku
//
//  Configurable 3x3 reader tap grid (ported from nyora-android TapGridSettings).
//

import Foundation
import CoreGraphics

/// One of the nine zones of the reader tap grid.
enum TapGridArea: String, CaseIterable {
    case topLeft
    case topCenter
    case topRight
    case centerLeft
    case center
    case centerRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    /// row 0 = top, 2 = bottom; col 0 = left, 2 = right
    init(row: Int, col: Int) {
        let clampedRow = min(2, max(0, row))
        let clampedCol = min(2, max(0, col))
        let index = clampedRow * 3 + clampedCol
        self = TapGridArea.allCases[index]
    }

    var row: Int { (TapGridArea.allCases.firstIndex(of: self) ?? 0) / 3 }
    var col: Int { (TapGridArea.allCases.firstIndex(of: self) ?? 0) % 3 }
}

/// The action performed when a tap grid zone is tapped.
enum TapGridAction: String, CaseIterable {
    case none
    case previousPage
    case nextPage
    case previousChapter
    case nextChapter
    case toggleMenu
    case openMenu

    var title: String {
        switch self {
            case .none: NSLocalizedString("TAP_ACTION_NONE")
            case .previousPage: NSLocalizedString("TAP_ACTION_PREV_PAGE")
            case .nextPage: NSLocalizedString("TAP_ACTION_NEXT_PAGE")
            case .previousChapter: NSLocalizedString("TAP_ACTION_PREV_CHAPTER")
            case .nextChapter: NSLocalizedString("TAP_ACTION_NEXT_CHAPTER")
            case .toggleMenu: NSLocalizedString("TAP_ACTION_TOGGLE_UI")
            case .openMenu: NSLocalizedString("TAP_ACTION_SHOW_MENU")
        }
    }

    /// Reference color (0xRRGGBB) matching the android palette, used to tint grid cells.
    var colorHex: UInt32 {
        switch self {
            case .none: 0x9E9E9E
            case .nextPage: 0x8BFF00
            case .previousPage: 0xFF4700
            case .nextChapter: 0x327E49
            case .previousChapter: 0x7E1218
            case .toggleMenu: 0x3D69C5
            case .openMenu: 0xAA1AC5
        }
    }
}

/// Loads/saves the reader tap-grid configuration from UserDefaults.
enum TapGridSettings {
    static let defaultsKey = "Reader.tapGrid"
    static let longDefaultsKey = "Reader.tapGridLong"

    /// Default mapping: left column + top edges = previous page, right column + bottom edges = next page,
    /// center = toggle UI (matching the android defaults).
    static let defaultActions: [TapGridArea: TapGridAction] = [
        .topLeft: .previousPage,
        .topCenter: .previousPage,
        .centerLeft: .previousPage,
        .bottomLeft: .previousPage,
        .center: .toggleMenu,
        .topRight: .nextPage,
        .centerRight: .nextPage,
        .bottomCenter: .nextPage,
        .bottomRight: .nextPage
    ]

    /// Default long-tap mapping: only the center zone shows the menu (matching the android defaults);
    /// all other zones default to no action.
    static let defaultLongActions: [TapGridArea: TapGridAction] = [
        .center: .openMenu
    ]

    /// The full 9-zone mapping, backfilling defaults for any missing/invalid stored values.
    static func currentMapping() -> [TapGridArea: TapGridAction] {
        var result = defaultActions
        if let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] {
            for (key, value) in stored {
                if let area = TapGridArea(rawValue: key), let action = TapGridAction(rawValue: value) {
                    result[area] = action
                }
            }
        }
        return result
    }

    /// The full 9-zone long-tap mapping, backfilling defaults for missing/invalid stored values.
    static func currentLongMapping() -> [TapGridArea: TapGridAction] {
        var result: [TapGridArea: TapGridAction] = [:]
        for area in TapGridArea.allCases {
            result[area] = defaultLongActions[area] ?? .none
        }
        if let stored = UserDefaults.standard.dictionary(forKey: longDefaultsKey) as? [String: String] {
            for (key, value) in stored {
                if let area = TapGridArea(rawValue: key), let action = TapGridAction(rawValue: value) {
                    result[area] = action
                }
            }
        }
        return result
    }

    static func action(for area: TapGridArea, isLongTap: Bool = false) -> TapGridAction {
        if isLongTap {
            return currentLongMapping()[area] ?? .none
        } else {
            return currentMapping()[area] ?? .none
        }
    }

    static func setAction(_ action: TapGridAction, for area: TapGridArea) {
        var mapping = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        // seed with defaults if empty so partial edits keep sensible neighbours
        if mapping.isEmpty {
            for (a, act) in defaultActions {
                mapping[a.rawValue] = act.rawValue
            }
        }
        mapping[area.rawValue] = action.rawValue
        UserDefaults.standard.set(mapping, forKey: defaultsKey)
    }

    static func setLongAction(_ action: TapGridAction, for area: TapGridArea) {
        var mapping = UserDefaults.standard.dictionary(forKey: longDefaultsKey) as? [String: String] ?? [:]
        // seed with defaults if empty so partial edits keep sensible neighbours
        if mapping.isEmpty {
            for area in TapGridArea.allCases {
                mapping[area.rawValue] = (defaultLongActions[area] ?? .none).rawValue
            }
        }
        mapping[area.rawValue] = action.rawValue
        UserDefaults.standard.set(mapping, forKey: longDefaultsKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: longDefaultsKey)
    }

    /// Maps a relative point (0-1) to its grid area.
    static func area(for relativePoint: CGPoint) -> TapGridArea {
        let col = min(2, max(0, Int(relativePoint.x * 3)))
        let row = min(2, max(0, Int(relativePoint.y * 3)))
        return TapGridArea(row: row, col: col)
    }
}
