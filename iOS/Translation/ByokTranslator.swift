import Foundation

/// Bring-your-own-key translation engine. Talks to any OpenAI-compatible
/// `/chat/completions` endpoint (OpenAI, Groq, Mistral, Together, Ollama,
/// LM Studio, …) using the user-supplied base URL, API key, and model.
/// Ported from the macApp's `AiRepository` + the chapter-translation DTOs.
///
/// The whole page's merged OCR bubbles are sent in a single JSON request and
/// the model returns one translation per bubble, keyed by id — so context
/// (who's speaking, prior lines) is preserved across the page, which a
/// per-string MT call can't do.
actor ByokTranslator {
    struct Config {
        let endpoint: String   // base URL, e.g. https://api.openai.com/v1
        let apiKey: String
        let model: String
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Translate a batch of OCR strings. Returns one line per input, same
    /// order. On any failure the corresponding `mtDraft` (or the original)
    /// is kept so a bubble never disappears.
    /// - originals: the raw OCR text per bubble.
    /// - mtDrafts: optional machine-translation drafts (same order) to seed the model.
    func translate(
        originals: [String],
        mtDrafts: [String],
        sourceLang: String,
        targetLang: String,
        config: Config
    ) async -> [String] {
        let fallback = mtDrafts.count == originals.count ? mtDrafts : originals
        guard !originals.isEmpty else { return [] }

        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty,
              let url = AIEndpointPolicy.chatCompletionsURL(baseURL: config.endpoint) else {
            return fallback
        }

        let dialogues: [DialogueBlock] = originals.enumerated().map { i, original in
            DialogueBlock(
                id: "\(i)",
                original: original,
                mt_draft: i < fallback.count ? fallback[i] : ""
            )
        }
        let payload = ChapterTranslationRequest(
            source_lang: sourceLang,
            target_lang: targetLang,
            dialogues: dialogues
        )

        let systemPrompt = """
        You are an expert manga translator. You are given a JSON object with a \
        list of `dialogues`, each having an `id`, the raw OCR `original` text, \
        and a rough machine-translation `mt_draft`. Translate every dialogue \
        from \(sourceLang) into natural, fluent \(targetLang), preserving tone, \
        register, and intensity (shouts, whispers, formal/casual). Render SFX \
        with a short evocative equivalent. Reply with ONLY a JSON object of the \
        form {"translations":[{"id":"0","translated":"..."}, ...]} covering \
        every id exactly once. No prose, no markdown, no notes.
        """

        let userJSON: String
        do {
            let data = try encoder.encode(payload)
            userJSON = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return fallback
        }

        let body = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userJSON)
            ],
            temperature: 0.3,
            response_format: ResponseFormat(type: "json_object")
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            req.httpBody = try encoder.encode(body)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpCookieStorage = nil
            let delegate = BoundedAIResponseDelegate(
                origin: url,
                maximumResponseBytes: AIEndpointPolicy.maximumBYOKResponseBytes
            )
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (data, resp) = try await delegate.data(for: req, session: session)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return fallback
            }
            let chat = try decoder.decode(ChatResponse.self, from: data)
            guard let content = chat.choices.first?.message.content else { return fallback }
            return parse(content: content, count: originals.count, fallback: fallback)
        } catch {
            return fallback
        }
    }

    /// Parse the model's JSON reply into an ordered array. Tolerates a bare
    /// array, a wrapped object, and stray markdown fences.
    private func parse(content: String, count: Int, fallback: [String]) -> [String] {
        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        guard let data = cleaned.data(using: .utf8) else { return fallback }

        var byId: [String: String] = [:]
        if let decoded = try? decoder.decode(ChapterTranslationResponse.self, from: data) {
            for t in decoded.translations { byId[t.id] = t.translated }
        } else if let arr = try? decoder.decode([ChapterTranslationResponse.TranslatedDialogue].self, from: data) {
            for t in arr { byId[t.id] = t.translated }
        } else {
            return fallback
        }

        var out = fallback
        for i in 0..<count {
            if let v = byId["\(i)"], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if i < out.count { out[i] = v } else { out.append(v) }
            }
        }
        return out
    }
}
