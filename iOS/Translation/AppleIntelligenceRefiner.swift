import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The "refine" layer of the pipeline (Android's REFINED state), powered by Apple
/// Intelligence's on-device language model (FoundationModels, iOS 26+). It takes the rough
/// machine-translation draft and rewrites it into a natural, concise speech-bubble line —
/// entirely on-device, no API key, no network.
///
/// Gracefully no-ops on iOS < 26 or when Apple Intelligence is unavailable (e.g. the
/// Simulator or unsupported devices), in which case the MT draft is kept unchanged.
@MainActor
final class AppleIntelligenceRefiner {
    static let shared = AppleIntelligenceRefiner()

    enum State {
        case unsupportedOS
        case unavailable(String)
        case ready
    }
    private(set) var state: State = .unsupportedOS
    private var sessionStorage: Any?
    // Separate session for primary on-device translation (its own instruction
    // context, keyed by target language). Stored as `Any?` because @available
    // can't decorate stored properties.
    private var translateSessionStorage: Any?
    private var translateSessionTargetLang: String?

    private init() { refreshAvailability() }

    func refreshAvailability() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: state = .ready
            case .unavailable(let reason): state = .unavailable("\(reason)")
            @unknown default: state = .unavailable("unknown")
            }
        } else {
            state = .unsupportedOS
        }
        #else
        state = .unsupportedOS
        #endif
    }

    var isReady: Bool { if case .ready = state { return true }; return false }

    var statusText: String {
        switch state {
        case .ready: return "Ready"
        case .unsupportedOS: return "Needs iOS 26+"
        case .unavailable(let r): return "Unavailable (\(r))"
        }
    }

    /// Polish MT drafts into natural target-language bubble text. Returns one line per
    /// input, same order; on any failure the draft is kept so we never lose text.
    func refine(originals: [String], drafts: [String], targetLanguage: String) async -> [String] {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), isReady, !drafts.isEmpty else { return drafts }
        guard let session = ensureSession() else { return drafts }

        var out: [String] = []
        out.reserveCapacity(drafts.count)
        for (i, draft) in drafts.enumerated() {
            let original = i < originals.count ? originals[i] : ""
            if draft.count < 2 { out.append(draft); continue }
            do {
                let prompt = """
                Original line: \(original)
                Rough \(targetLanguage) translation: \(draft)
                Rewrite the rough translation as a single natural, concise \(targetLanguage) \
                line suitable for a manga speech bubble. Keep the meaning and tone. \
                Return ONLY the line, no quotes, no notes.
                """
                let response = try await session.respond(to: prompt)
                let cleaned = response.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`「」『』"))
                out.append(cleaned.isEmpty ? draft : cleaned)
            } catch {
                out.append(draft)
            }
        }
        return out
        #else
        return drafts
        #endif
    }

    /// Translate a batch of strings on-device with Apple Intelligence — used
    /// when Apple Intelligence is the PRIMARY engine (not just the refine
    /// step). Returns one translation per input in the same order; falls back
    /// to the input on any error or safety-filter refusal so a bubble never
    /// disappears. Caller should check `isReady` first.
    func translate(_ texts: [String], sourceLang: String, targetLanguage: String) async -> [String] {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), isReady, !texts.isEmpty else { return texts }
        guard let session = ensureTranslateSession(sourceLang: sourceLang, targetLang: targetLanguage) else { return texts }

        var out: [String] = []
        out.reserveCapacity(texts.count)
        for original in texts {
            let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { out.append(""); continue }
            do {
                let response = try await session.respond(to: trimmed)
                let cleaned = response.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`「」『』"))
                // Safety-filter refusals ("I can't assist with that request")
                // are treated as "no translation" so we keep the source text
                // instead of painting the refusal into the bubble.
                if cleaned.isEmpty || Self.isRefusal(cleaned) {
                    out.append(original)
                } else {
                    out.append(cleaned)
                }
            } catch {
                out.append(original)
            }
        }
        return out
        #else
        return texts
        #endif
    }

    /// Heuristic detector for Apple Intelligence safety-filter refusals.
    static func isRefusal(_ s: String) -> Bool {
        let lower = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }
        let refusalPrefixes = [
            "i can't", "i cannot", "i'm not able", "i am not able",
            "i'm unable", "i am unable", "i'm sorry, but", "i am sorry, but",
            "sorry, i can", "sorry, but i", "unfortunately, i",
            "as an ai", "as a language model",
        ]
        for prefix in refusalPrefixes where lower.hasPrefix(prefix) { return true }
        let refusalPhrases = [
            "can't assist with that request", "can't help with that request",
            "cannot assist with that request", "cannot help with that request",
            "unable to assist with that", "i don't feel comfortable",
            "i'm not comfortable", "violates my guidelines", "against my guidelines",
        ]
        for phrase in refusalPhrases where lower.contains(phrase) { return true }
        return false
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func ensureSession() -> LanguageModelSession? {
        if let existing = sessionStorage as? LanguageModelSession { return existing }
        let instructions = "You are a professional manga translation editor. You rewrite "
            + "rough machine translations into natural, concise lines for speech bubbles, "
            + "preserving meaning and tone. You output only the rewritten line."
        let s = LanguageModelSession(instructions: instructions)
        sessionStorage = s
        return s
    }

    @available(iOS 26.0, *)
    private func ensureTranslateSession(sourceLang: String, targetLang: String) -> LanguageModelSession? {
        if let existing = translateSessionStorage as? LanguageModelSession,
           translateSessionTargetLang == targetLang {
            return existing
        }
        let instructions = """
        You are an expert manga translator. Translate the given \(sourceLang) \
        dialogue into natural, fluent \(targetLang). Preserve tone, register, \
        and intensity (shouts, whispers, formal/casual). Render SFX with a \
        short evocative equivalent. Output ONLY the translation — no quotes, \
        no source text, no notes, no romaji, no markdown.
        """
        let s = LanguageModelSession(instructions: instructions)
        translateSessionStorage = s
        translateSessionTargetLang = targetLang
        return s
    }
    #endif
}
