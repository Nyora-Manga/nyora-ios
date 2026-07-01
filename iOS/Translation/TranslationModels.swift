import Foundation
import SwiftUI

/// Pipeline stages, mirroring nyora-android's `TranslationState`.
enum TranslationState: Int, Comparable {
    case translating = 0   // OCR found, awaiting machine translation
    case mt = 1            // machine-translated (fast layer)
    case refined = 2       // Apple Intelligence polished (refine layer)

    static func < (a: TranslationState, b: TranslationState) -> Bool { a.rawValue < b.rawValue }
}

/// One translated speech bubble. Bounding box is in image-pixel coords, top-left origin.
struct TranslatedBlock: Identifiable {
    let id: String
    let originalText: String
    var translatedText: String
    let boundingBox: CGRect
    var state: TranslationState
    var backgroundColor: Color
}

/// Language config shared by the OCR + MT layers. Mirrors the Android language maps.
enum TranslationConfig {
    static let supportedLanguages = [
        "AUTO", "English", "Japanese", "Chinese", "Korean",
        "Spanish", "French", "German", "Portuguese", "Italian",
        "Russian", "Arabic", "Hindi", "Turkish", "Vietnamese",
        "Polish", "Dutch", "Thai", "Indonesian",
    ]

    /// Google Translate target code for a display language name.
    static func googleLangCode(for lang: String) -> String {
        switch lang.lowercased() {
        case "english": return "en"
        case "japanese": return "ja"
        case "chinese": return "zh-CN"
        case "korean": return "ko"
        case "spanish": return "es"
        case "french": return "fr"
        case "german": return "de"
        case "portuguese": return "pt"
        case "italian": return "it"
        case "russian": return "ru"
        case "arabic": return "ar"
        case "hindi": return "hi"
        case "turkish": return "tr"
        case "vietnamese": return "vi"
        case "polish": return "pl"
        case "dutch": return "nl"
        case "thai": return "th"
        case "indonesian": return "id"
        default: return "en"
        }
    }
}
