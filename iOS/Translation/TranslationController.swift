//
//  TranslationController.swift
//  Aidoku (iOS)
//
//  Global state for the AI page-translation feature (ported from nyora-ios).
//  Holds the on/off toggle, target language, and the shared translator, and
//  broadcasts changes so visible reader pages re-evaluate themselves.
//

import Foundation
import SwiftUI

extension Notification.Name {
    /// Posted whenever translation is toggled or its settings change.
    static let translationSettingsChanged = Notification.Name("Nyora.translationSettingsChanged")
}

@MainActor
final class TranslationController {
    static let shared = TranslationController()

    /// One translator instance shared across pages (its OCR/MT actors serialize work).
    let translator = MangaTranslator()

    private enum Keys {
        static let enabled = "Reader.translate"
        static let target = "Reader.translateTarget"
        static let useAI = "Reader.translateUseAI"
    }

    private init() {}

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.enabled) }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.enabled)
            NotificationCenter.default.post(name: .translationSettingsChanged, object: nil)
        }
    }

    var targetLanguage: String {
        get { UserDefaults.standard.string(forKey: Keys.target) ?? "English" }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.target)
            NotificationCenter.default.post(name: .translationSettingsChanged, object: nil)
        }
    }

    var useAppleIntelligence: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.useAI) == nil { return true }
            return UserDefaults.standard.bool(forKey: Keys.useAI)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.useAI)
            NotificationCenter.default.post(name: .translationSettingsChanged, object: nil)
        }
    }

    func toggle() {
        enabled.toggle()
    }
}

/// Wraps `TranslationOverlayView` in a `GeometryReader` so the SwiftUI overlay
/// always knows its host view's current size (tracks rotation/layout), keeping
/// the bubble boxes aligned to the page image.
struct TranslationOverlayContainer: View {
    let blocks: [TranslatedBlock]
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            TranslationOverlayView(blocks: blocks, imageSize: imageSize, containerSize: geo.size)
        }
    }
}
