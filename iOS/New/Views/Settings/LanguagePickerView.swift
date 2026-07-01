//
//  LanguagePickerView.swift
//  Aidoku (iOS)
//
//  Nyora port (NP-020): in-app app-language picker.
//
//  Mirrors nyora-android's `app_locale` ActivityListPreference: lets the user
//  override the app language (Follow system + any bundled localization) by
//  writing the `AppleLanguages` UserDefaults key, then prompts a restart.
//

import SwiftUI

/// A selectable app language: either "follow system" or a specific bundled locale.
struct AppLanguage: Identifiable, Equatable {
    /// The language code (e.g. "en", "pt-BR"), or nil for "follow system".
    let code: String?

    var id: String { code ?? "" }

    /// Localized display name shown to the user.
    var displayName: String {
        guard let code else {
            return NSLocalizedString("FOLLOW_SYSTEM")
        }
        let locale = Locale(identifier: code)
        // Prefer the language's own name (autonym) so each entry is legible
        // to a speaker of that language, falling back to the current locale.
        let name = locale.localizedString(forIdentifier: code)
            ?? Locale.current.localizedString(forIdentifier: code)
            ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// All languages the app is localized for, "Follow system" first.
    static var all: [AppLanguage] {
        let bundled = Bundle.main.localizations
            .filter { $0 != "Base" }
            .map { AppLanguage(code: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return [AppLanguage(code: nil)] + bundled
    }

    /// The currently effective override (nil = follow system).
    static var current: AppLanguage {
        guard
            let override = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first,
            !override.isEmpty
        else {
            return AppLanguage(code: nil)
        }
        // Match against a bundled localization, tolerating region suffixes.
        let bundled = Bundle.main.localizations.filter { $0 != "Base" }
        if bundled.contains(override) {
            return AppLanguage(code: override)
        }
        let base = override.split(separator: "-").first.map(String.init) ?? override
        if let match = bundled.first(where: { $0 == base || $0.hasPrefix(base + "-") }) {
            return AppLanguage(code: match)
        }
        return AppLanguage(code: nil)
    }

    /// Applies this language as the app override.
    func apply() {
        let defaults = UserDefaults.standard
        if let code {
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
        defaults.synchronize()
    }
}

struct LanguagePickerView: View {
    @State private var selected = AppLanguage.current
    @State private var showRestartAlert = false

    private let languages = AppLanguage.all

    var body: some View {
        List {
            Section(footer: Text(NSLocalizedString("APP_LANGUAGE_FOOTER"))) {
                ForEach(languages) { language in
                    Button {
                        select(language)
                    } label: {
                        HStack {
                            Text(language.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                            if language == selected {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("LANGUAGE"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(NSLocalizedString("RESTART_REQUIRED"), isPresented: $showRestartAlert) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("RESTART_REQUIRED_TEXT"))
        }
    }

    private func select(_ language: AppLanguage) {
        guard language != selected else { return }
        selected = language
        language.apply()
        UISelectionFeedbackGenerator().selectionChanged()
        showRestartAlert = true
    }
}
