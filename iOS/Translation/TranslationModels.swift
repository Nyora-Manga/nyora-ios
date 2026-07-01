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

/// Which backend performs the actual translation of the merged OCR bubbles.
/// Mirrors the macApp's translation engine choice.
enum TranslationEngine: String, CaseIterable, Identifiable {
    /// Free, no-key unofficial Google Translate endpoint (the current default).
    case google
    /// On-device Apple Intelligence (FoundationModels, iOS 26+). No key, no network.
    case appleIntelligence
    /// Bring-your-own-key: any OpenAI-compatible /chat/completions endpoint.
    case byok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: return "Google (free)"
        case .appleIntelligence: return "Apple Intelligence"
        case .byok: return "Custom (API key)"
        }
    }
}

// MARK: - LLM request / response models (BYOK, OpenAI-compatible)

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ResponseFormat: Codable {
    let type: String
}

struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Float
    let response_format: ResponseFormat?

    init(model: String, messages: [ChatMessage], temperature: Float = 0.3, response_format: ResponseFormat? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.response_format = response_format
    }
}

struct ChatResponse: Codable {
    struct Choice: Codable { let message: ChatMessage }
    let choices: [Choice]
}

struct DialogueBlock: Codable {
    let id: String
    let original: String
    var mt_draft: String
}

struct ChapterTranslationRequest: Codable {
    let context: String
    let source_lang: String
    let target_lang: String
    let dialogues: [DialogueBlock]

    init(source_lang: String, target_lang: String, dialogues: [DialogueBlock]) {
        self.context = "Manga Chapter Translation"
        self.source_lang = source_lang
        self.target_lang = target_lang
        self.dialogues = dialogues
    }
}

struct ChapterTranslationResponse: Codable {
    struct TranslatedDialogue: Codable {
        let id: String
        let translated: String
    }
    let reasoning: String?
    let translations: [TranslatedDialogue]
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
