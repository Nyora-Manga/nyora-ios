//
//  NyoraLanguageStore.swift
//  Aidoku
//
//  Side channel for a manga's translation language. The AidokuRunner.Manga model
//  carries no per-title language, so the Nyora runner derives it from the parser
//  source's catalog `lang` and stashes it here (keyed by the manga's encoded key)
//  when details load; the details header reads it back to render a language label
//  with an emoji flag. Mirrors nyora-android's DetailsActivity textViewTranslation
//  (details.getLocale() + LocaleUtils.getEmojiFlag).
//

import Foundation

final class NyoraLanguageStore: @unchecked Sendable {
    static let shared = NyoraLanguageStore()

    private let lock = NSLock()
    private var storage: [String: String] = [:]

    private init() {}

    /// Stores a BCP-47-ish language code (e.g. "en", "ja", "pt-BR"). Empty / catch-all
    /// values ("multi", "all") are treated as unknown.
    func set(_ code: String?, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed == "multi" || trimmed == "all" || trimmed == "other" {
            storage[key] = nil
        } else {
            storage[key] = trimmed
        }
    }

    /// Returns the stored language code if known, otherwise nil.
    func get(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    // MARK: - Presentation helpers

    /// Human-readable language name shown in that language itself, title-cased —
    /// mirrors android's `translation.getDisplayLanguage(translation).toTitleCase(translation)`.
    static func displayName(forLanguageCode code: String) -> String? {
        let lower = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty, lower != "multi", lower != "all", lower != "other" else { return nil }
        let langPart = String(lower.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
        guard !langPart.isEmpty else { return nil }
        let locale = Locale(identifier: lower)
        guard let name = locale.localizedString(forLanguageCode: langPart), !name.isEmpty else {
            return nil
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Regional-indicator emoji flag for a language code, mapping ambiguous language
    /// codes to a representative country the same way android's LocaleUtils.getEmojiFlag does.
    static func emojiFlag(forLanguageCode code: String) -> String? {
        let lower = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty, lower != "multi", lower != "all", lower != "other" else { return nil }

        let parts = lower.split(whereSeparator: { $0 == "-" || $0 == "_" })
        let region: String
        if parts.count >= 2, parts[1].count == 2 {
            region = String(parts[1]).uppercased()
        } else {
            region = mapLanguageToRegion(String(parts[0]).uppercased())
        }

        guard region.count == 2, region.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }

        var scalars = String.UnicodeScalarView()
        for ch in region.unicodeScalars {
            guard let scalar = UnicodeScalar(127_397 + ch.value) else { return nil }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func mapLanguageToRegion(_ lang: String) -> String {
        switch lang {
            case "EN": return "GB"
            case "JA": return "JP"
            case "VI": return "VN"
            case "ZH": return "CN"
            case "AR": return "SA"
            case "KO": return "KR"
            case "CS": return "CZ"
            case "DA": return "DK"
            case "EL": return "GR"
            case "HI": return "IN"
            case "UK": return "UA"
            case "FA": return "IR"
            case "MS": return "MY"
            case "HE": return "IL"
            case "SV": return "SE"
            case "SL": return "SI"
            default: return lang
        }
    }
}
