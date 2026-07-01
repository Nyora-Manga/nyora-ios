//
//  ReaderAnimationMode.swift
//  Aidoku (iOS)
//
//  Ported from nyora-android core/prefs/ReaderAnimation.kt (+ DepthPageTransformer.kt).
//  Replaces the old boolean "Reader.animatePageTransitions" toggle with a
//  three-way page-turn animation picker: none / slide / advanced (depth).
//

import UIKit

enum ReaderAnimationMode: String, CaseIterable {
    /// Pages swap instantly with no transition.
    case none
    /// Standard horizontal/vertical slide (the built-in page-view scroll).
    case slide
    /// Cinematic depth effect: outgoing page dims + scales down while the
    /// incoming page pushes in — re-implemented natively via Core Animation.
    case advanced

    static let key = "Reader.animation"

    static var current: ReaderAnimationMode {
        UserDefaults.standard.string(forKey: key)
            .flatMap(ReaderAnimationMode.init) ?? .slide
    }

    /// Whether the page swap should be animated at all. Readers that can't
    /// render the depth effect (webtoon / text) fall back to a plain slide for
    /// `.advanced`; the paged reader special-cases `.advanced` itself.
    var animatesPageTransition: Bool {
        self != .none
    }

    var title: String {
        switch self {
        case .none: return NSLocalizedString("PAGE_ANIMATION_NONE")
        case .slide: return NSLocalizedString("PAGE_ANIMATION_SLIDE")
        case .advanced: return NSLocalizedString("PAGE_ANIMATION_ADVANCED")
        }
    }

    /// One-time migration from the legacy boolean preference. If the user had
    /// explicitly disabled the old "animate page transitions" toggle, carry
    /// that over as `.none`; otherwise leave the registered default (`.slide`).
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        let migratedKey = "Reader.animation.migrated"
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)

        // Only act if the user explicitly set the legacy key.
        if
            defaults.object(forKey: "Reader.animation") == nil,
            defaults.object(forKey: "Reader.animatePageTransitions") != nil,
            defaults.bool(forKey: "Reader.animatePageTransitions") == false
        {
            defaults.set(ReaderAnimationMode.none.rawValue, forKey: key)
        }
    }

    /// Applies the advanced depth transition to a container layer while its
    /// content is swapped underneath (call `setViewControllers(animated: false)`
    /// inside a `CATransaction` alongside this).
    ///
    /// Mirrors DepthPageTransformer: a push in the travel direction combined
    /// with a brief scale-down/-up giving a layered, 3D-like page turn.
    static func applyAdvancedTransition(to layer: CALayer, forward: Bool, vertical: Bool) {
        let duration: CFTimeInterval = 0.35
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)

        let push = CATransition()
        push.type = .push
        if vertical {
            push.subtype = forward ? .fromTop : .fromBottom
        } else {
            push.subtype = forward ? .fromRight : .fromLeft
        }
        push.duration = duration
        push.timingFunction = timing

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.0, 0.9, 1.0]
        scale.keyTimes = [0, 0.5, 1]
        scale.duration = duration
        scale.timingFunction = timing

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1.0, 0.55, 1.0]
        opacity.keyTimes = [0, 0.5, 1]
        opacity.duration = duration
        opacity.timingFunction = timing

        let group = CAAnimationGroup()
        group.animations = [push, scale, opacity]
        group.duration = duration
        group.timingFunction = timing
        layer.add(group, forKey: "advancedPageTransition")
    }
}
