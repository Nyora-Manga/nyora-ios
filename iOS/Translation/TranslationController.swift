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
        static let engine = "Reader.translateEngine"
        static let source = "Reader.translateSource"
        static let byokEndpoint = "Reader.translateByokEndpoint"
        static let byokApiKey = "Reader.translateByokApiKey"
        static let byokModel = "Reader.translateByokModel"
    }

    private init() {}

    private func postChanged() {
        NotificationCenter.default.post(name: .translationSettingsChanged, object: nil)
    }

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.enabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.enabled); postChanged() }
    }

    var targetLanguage: String {
        get { UserDefaults.standard.string(forKey: Keys.target) ?? "English" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.target); postChanged() }
    }

    var sourceLanguage: String {
        get { UserDefaults.standard.string(forKey: Keys.source) ?? "AUTO" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.source); postChanged() }
    }

    /// Post-MT on-device polish. Kept independent of the primary engine.
    var useAppleIntelligence: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.useAI) == nil { return true }
            return UserDefaults.standard.bool(forKey: Keys.useAI)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.useAI); postChanged() }
    }

    /// The primary translation engine (google / appleIntelligence / byok).
    var engine: TranslationEngine {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Keys.engine),
                  let e = TranslationEngine(rawValue: raw) else { return .google }
            return e
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.engine); postChanged() }
    }

    // MARK: BYOK (OpenAI-compatible) configuration

    var byokEndpoint: String {
        get { UserDefaults.standard.string(forKey: Keys.byokEndpoint) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.byokEndpoint); postChanged() }
    }

    var byokApiKey: String {
        get { UserDefaults.standard.string(forKey: Keys.byokApiKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.byokApiKey); postChanged() }
    }

    var byokModel: String {
        get { UserDefaults.standard.string(forKey: Keys.byokModel) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.byokModel); postChanged() }
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
