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
    #endif
}
