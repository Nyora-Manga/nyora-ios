//
//  ReaderControl.swift
//  Aidoku
//
//  Customizable reader control buttons (ported from nyora-android ReaderControl).
//

import Foundation

/// A toggleable reader control button. Mirrors nyora-android's `ReaderControl` enum,
/// mapped onto Aidoku's reader chrome (navbar + bottom toolbar).
enum ReaderControl: String, CaseIterable {
    case prevChapter
    case nextChapter
    case slider
    case pagesSheet
    case screenRotation
    case timer

    var title: String {
        switch self {
            case .prevChapter: NSLocalizedString("READER_CONTROL_PREV_CHAPTER")
            case .nextChapter: NSLocalizedString("READER_CONTROL_NEXT_CHAPTER")
            case .slider: NSLocalizedString("READER_CONTROL_SLIDER")
            case .pagesSheet: NSLocalizedString("READER_CONTROL_CHAPTER_LIST")
            case .screenRotation: NSLocalizedString("READER_CONTROL_ROTATION")
            case .timer: NSLocalizedString("READER_CONTROL_TIMER")
        }
    }

    var systemImage: String {
        switch self {
            case .prevChapter: "chevron.left.2"
            case .nextChapter: "chevron.right.2"
            case .slider: "slider.horizontal.below.rectangle"
            case .pagesSheet: "list.bullet"
            case .screenRotation: "rotate.right"
            case .timer: "timer"
        }
    }
}

/// Persistence + defaults for the customizable reader controls (`Reader.controls`).
enum ReaderControlSettings {
    static let key = "Reader.controls"

    /// All controls enabled by default so the reader chrome matches the pre-NP-022 behaviour.
    static let defaultControls: [ReaderControl] = ReaderControl.allCases

    static var current: Set<ReaderControl> {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [String] else {
            return Set(defaultControls)
        }
        return Set(raw.compactMap(ReaderControl.init))
    }

    static func isEnabled(_ control: ReaderControl) -> Bool {
        current.contains(control)
    }

    static func setEnabled(_ control: ReaderControl, _ enabled: Bool) {
        var set = current
        if enabled {
            set.insert(control)
        } else {
            set.remove(control)
        }
        save(set)
    }

    static func save(_ set: Set<ReaderControl>) {
        // preserve a stable order matching the enum declaration
        let ordered = ReaderControl.allCases.filter { set.contains($0) }.map { $0.rawValue }
        UserDefaults.standard.set(ordered, forKey: key)
        NotificationCenter.default.post(name: .init(key), object: nil)
    }

    static func registerDefault() {
        UserDefaults.standard.register(defaults: [key: defaultControls.map { $0.rawValue }])
    }
}
