import Foundation

/// Machine translation via the free Google web endpoint (`client=gtx`, no API
/// key) — a port of nyora-web's `core/translate/mt.js`, which is itself a port of
/// nyora-android's `translator/Translator.kt`.
///
/// All bubbles of a page are joined with the same `|||` delimiter Android and the
/// web reader use and translated in ONE request. The raw endpoint output is then
/// run through `MTPolish`, the shared manga-specific repair layer.
actor GoogleTranslate {
    private let session = URLSession.shared

    private static let delimiter = "\n\n\n|||\n\n\n"

    /// OCR language → Google translate source code.
    private static let gtxSource = ["ja": "ja", "zh": "zh-CN", "ko": "ko", "en": "en"]

    /// `URLComponents`/`.urlQueryAllowed` both leave `&`, `+` and `=` unescaped,
    /// which silently truncates or corrupts any bubble containing them. This is
    /// the `encodeURIComponent` set the web port relies on.
    private static let queryAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    // MARK: - Endpoint

    private func gtx(_ text: String, target: String, source: String) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        guard let q = text.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed),
              let sl = source.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed),
              let tl = target.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed),
              let url = URL(string: "https://translate.googleapis.com/translate_a/single"
                            + "?client=gtx&dt=t&sl=\(sl)&tl=\(tl)&q=\(q)")
        else { return text }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [[Any]]
        else { throw URLError(.cannotParseResponse) }
        return segments.compactMap { $0.first as? String }.joined()
    }

    // MARK: - Batching

    /// Split a joined reply back into segments; nil when it can't align.
    private func splitParts(_ full: String, _ count: Int) -> [String]? {
        // Google frequently spaces the delimiter out ("| | |"), so the splitter
        // has to tolerate whitespace between the bars as well as around them.
        let parts = full
            .replacingOccurrences(of: "\\s*\\|\\s*\\|\\s*\\|\\s*", with: "\u{1}",
                                  options: .regularExpression)
            .components(separatedBy: "\u{1}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return parts.count == count ? parts : nil
    }

    /// Translate a run of segments, halving on misalignment. Going straight to
    /// one request per block (what this used to do) cost 30 round trips for a
    /// single bad split on a 30-bubble page; bisecting costs ~log2(n) and usually
    /// isolates the one segment that confused the splitter.
    private func translateRun(_ texts: [String], target: String, source: String) async -> [String] {
        if texts.isEmpty { return [] }
        if texts.count == 1 {
            // A failed segment keeps its source text rather than going blank — a
            // bubble must never disappear off the page.
            let single = (try? await gtx(texts[0], target: target, source: source))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return [single ?? texts[0]]
        }
        if let joined = try? await gtx(texts.joined(separator: Self.delimiter),
                                       target: target, source: source),
           let parts = splitParts(joined, texts.count) {
            return parts
        }
        let mid = (texts.count + 1) / 2
        async let head = translateRun(Array(texts[..<mid]), target: target, source: source)
        async let tail = translateRun(Array(texts[mid...]), target: target, source: source)
        return await head + tail
    }

    // MARK: - Public API

    /// One prepared bubble on its way through the pipeline.
    private struct Prepared {
        /// Answered locally from the lexicon — never sent to Google.
        var direct: String?
        /// The text actually sent (stutter and held vowels stripped).
        var send: String?
        var src: String
        var stutter = false
        var hold = 0
        var names: [(name: String, suffix: String)] = []
        var out: String = ""
    }

    /// Translate every bubble of a page.
    /// - source: the OCR/source language as a bare code (`ja`, `ko`, `zh`, `en`)
    ///   or `auto`. Pinning it matters: `sl=auto` lets Google re-detect per
    ///   request, so a bisected page could translate its halves as two different
    ///   languages, and the honorific/SFX rules key off it too.
    func translateBatch(_ texts: [String], to target: String, from source: String = "auto") async -> [String] {
        guard !texts.isEmpty else { return [] }
        let lang = source                                    // before the gtx code mapping
        let sourceCode = Self.gtxSource[source] ?? (source.isEmpty ? "auto" : source)

        var prepared: [Prepared] = texts.map { raw in
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let hit = MTPolish.lexiconHit(for: t, target: target) {
                return Prepared(direct: hit, send: nil, src: t)
            }
            let (unstuttered, stutter) = MTPolish.stripStutter(t)
            let (held, hold) = MTPolish.stripHold(unstuttered)
            // After stripStutter, so a leading "え、え…" keeps its stutter handling
            // and only the pauses inside the remaining word are closed up.
            //
            // Per-line, NOT batch-wide: if this line writes the name bare, the
            // author dropped the honorific on purpose and it must stay dropped.
            // Collecting them batch-wide leaked 「ナハトさん」's -san onto
            // 「天才だナハト…！」.
            return Prepared(
                direct: nil,
                send: MTPolish.joinSplitWords(held),
                src: t,
                stutter: stutter,
                hold: hold,
                names: MTPolish.findNamedHonorifics([t], lang: lang))
        }

        let pendingIndices = prepared.indices.filter { prepared[$0].send != nil }

        // Names carrying an honorific ride along as extra segments so gtx's own
        // romanisation comes back in the SAME request — see `findNamedHonorifics`.
        // English targets only: the -san convention is an English scanlation habit.
        let names = target == "en" ? MTPolish.findNamedHonorifics(texts, lang: lang) : []
        let nameList = names.map(\.name)

        let sent = pendingIndices.map { prepared[$0].send ?? "" } + nameList
        let got = await translateRun(sent, target: target, source: sourceCode)
        guard got.count == sent.count else { return texts }

        for (slot, idx) in pendingIndices.enumerated() { prepared[idx].out = got[slot] }
        var englishName: [String: String] = [:]
        for (i, jp) in nameList.enumerated() { englishName[jp] = got[pendingIndices.count + i] }

        return prepared.map { p in
            if let direct = p.direct { return direct }
            var out = MTPolish.applyHold(
                MTPolish.polish(p.out, src: p.src, stutter: p.stutter, lang: lang),
                hold: p.hold)
            for (jp, suffix) in p.names {
                out = MTPolish.reattachHonorific(out, englishName: englishName[jp], suffix: suffix)
            }
            return out
        }
    }

    /// Single-string convenience (settings previews, tests).
    func translate(_ text: String, to target: String, from source: String = "auto") async -> String {
        await translateBatch([text], to: target, from: source).first ?? text
    }
}
