//
//  ProgressIndicatorMode.swift
//  Aidoku (iOS)
//
//  Reading-progress cover indicator, ported natively from
//  nyora-android core/prefs/ProgressIndicatorMode.kt + list/domain/ReadingProgress.kt
//

import Foundation

/// How reading progress is displayed as an overlay on library covers.
enum ProgressIndicatorMode: String, CaseIterable {
    case none
    case percentRead
    case percentLeft
    case chaptersRead
    case chaptersLeft

    /// Current stored mode from user defaults.
    static var current: ProgressIndicatorMode {
        let raw = UserDefaults.standard.string(forKey: "Appearance.progressIndicator") ?? none.rawValue
        return ProgressIndicatorMode(rawValue: raw) ?? .none
    }

    var title: String {
        switch self {
            case .none: NSLocalizedString("PROGRESS_INDICATOR_NONE")
            case .percentRead: NSLocalizedString("PROGRESS_INDICATOR_PERCENT_READ")
            case .percentLeft: NSLocalizedString("PROGRESS_INDICATOR_PERCENT_LEFT")
            case .chaptersRead: NSLocalizedString("PROGRESS_INDICATOR_CHAPTERS_READ")
            case .chaptersLeft: NSLocalizedString("PROGRESS_INDICATOR_CHAPTERS_LEFT")
        }
    }
}

/// Computed reading-progress value for a single manga.
struct ReadingProgress {
    let read: Int
    let total: Int
    let mode: ProgressIndicatorMode

    private var percent: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(read) / Double(total)))
    }

    private var chaptersLeft: Int {
        max(0, total - read)
    }

    private var isCompleted: Bool {
        percent >= 0.99999
    }

    /// Whether an overlay should be shown at all.
    var isValid: Bool {
        switch mode {
            case .none:
                return false
            case .percentRead, .percentLeft, .chaptersRead, .chaptersLeft:
                return total > 0
        }
    }

    /// Fraction (0...1) used to fill the progress ring.
    var fillFraction: Double {
        switch mode {
            case .percentLeft, .chaptersLeft:
                return 1 - percent
            default:
                return percent
        }
    }

    /// The short label rendered inside the badge (e.g. "45%" or "12").
    var label: String {
        switch mode {
            case .none:
                return ""
            case .percentRead:
                return "\(isCompleted ? 100 : Int(percent * 100))%"
            case .percentLeft:
                return isCompleted ? "0%" : "\(Int((1 - percent) * 100))%"
            case .chaptersRead:
                return "\(read)"
            case .chaptersLeft:
                return "\(chaptersLeft)"
        }
    }
}
