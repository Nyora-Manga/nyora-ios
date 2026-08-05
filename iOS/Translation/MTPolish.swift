import Foundation

/// Manga-specific repair of plain machine-translation output — a direct port of
/// nyora-web's `core/translate/mt.js`.
///
/// Google Translate is a general-purpose translator, so it mangles a handful of
/// things that are ubiquitous in manga: it reads set-phrase interjections as
/// literal statements, sends katakana sound effects to the dictionary, drops
/// honorifics, inflates repeated characters, and parses a word drawn across a
/// dramatic pause as separate fragments. Every rule below was written against
/// observed live `client=gtx` output (the examples in the comments are measured,
/// not guessed) and is shared verbatim with the web reader so a page reads the
/// same on both platforms.
enum MTPolish {

    // MARK: - Regex plumbing

    /// Thin wrapper over `NSRegularExpression`. All patterns here are fixed
    /// literals, so a compile failure is a programming error, not a runtime one.
    private struct RX {
        let re: NSRegularExpression

        init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
            // swiftlint:disable:next force_try
            re = try! NSRegularExpression(pattern: pattern, options: options)
        }

        func matches(_ ns: NSString) -> [NSTextCheckingResult] {
            re.matches(in: ns as String, range: NSRange(location: 0, length: ns.length))
        }

        func firstMatch(_ ns: NSString) -> NSTextCheckingResult? {
            re.firstMatch(in: ns as String, range: NSRange(location: 0, length: ns.length))
        }

        func test(_ s: String) -> Bool { firstMatch(s as NSString) != nil }

        func replacingAll(_ s: String, with template: String) -> String {
            let ns = s as NSString
            return re.stringByReplacingMatches(
                in: s, range: NSRange(location: 0, length: ns.length), withTemplate: template)
        }

        /// Replace every match with the result of `body` — the closure form JS
        /// `String.replace(re, fn)` provides and `NSRegularExpression` does not.
        func replacingAll(_ s: String, _ body: (NSTextCheckingResult, NSString) -> String) -> String {
            let ns = s as NSString
            var out = ""
            var cursor = 0
            for m in matches(ns) {
                out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                out += body(m, ns)
                cursor = m.range.location + m.range.length
            }
            out += ns.substring(from: cursor)
            return out
        }

        /// Replace only the first match (JS regex without the `g` flag).
        func replacingFirst(_ s: String, _ body: (NSTextCheckingResult, NSString) -> String) -> String {
            let ns = s as NSString
            guard let m = firstMatch(ns) else { return s }
            return ns.substring(to: m.range.location)
                + body(m, ns)
                + ns.substring(from: m.range.location + m.range.length)
        }
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ ns: NSString) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : ns.substring(with: r)
    }

    // MARK: - Set phrases

    /// Set phrases gtx reliably gets WRONG. It reads these as literal statements
    /// instead of the interjections they are: しまった！→ "It's gone!",
    /// ヤバい → "It's dangerous". Short, high-frequency and unambiguous inside a
    /// speech bubble, so we answer them directly and never send them to Google.
    static let lexicon: [String: String] = [
        "しまった": "Damn it", "ヤバい": "This is bad", "やばい": "This is bad",
        "まずい": "This is bad", "くそ": "Damn", "くそっ": "Damn it",
        "ちくしょう": "Dammit", "やめろ": "Stop it", "まさか": "No way",
        "さすが": "As expected", "よし": "All right", "なるほど": "I see",
        "うるさい": "Shut up", "てめえ": "You bastard", "ざけんな": "Screw you",
        "どういうことだ": "What do you mean", "ありえない": "Impossible",
    ]

    // MARK: - Punctuation

    /// gtx renders repeated full-width marks as spaced ASCII — 逃げろ！！ comes
    /// back "Run away! !" and なんだと！？ as "What! ?". It also leaves … untouched
    /// in some segments while converting it to ... in others.
    private static let fullwidth: [Character: String] = [
        "！": "!", "？": "?", "。": ".", "、": ",", "．": ".", "，": ",",
    ]

    static func asciiPunct(_ s: String) -> String {
        String(s.map { fullwidth[$0].map(Character.init) ?? $0 })
    }

    private static let rxSpacedMarks = RX("([!?])(\\s+[!?])+")
    private static let rxEllipsis = RX("…")
    private static let rxLongDots = RX("\\.{4,}")
    private static let rxSpaceBeforePunct = RX("\\s+([,.!?;:])")
    private static let rxDoubleSpace = RX("\\s{2,}")
    private static let rxWhitespaceRun = RX("\\s+")

    static func fixPunct(_ s: String) -> String {
        var out = rxSpacedMarks.replacingAll(s) { m, ns in
            rxWhitespaceRun.replacingAll(ns.substring(with: m.range), with: "")   // "! ! !" → "!!!"
        }
        out = rxEllipsis.replacingAll(out, with: "...")
        out = rxLongDots.replacingAll(out, with: "...")
        out = rxSpaceBeforePunct.replacingAll(out, with: "$1")
        out = rxDoubleSpace.replacingAll(out, with: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Character runs

    private static let rxSrcRun = RX("(.)\\1+")
    private static let rxEnRun = RX("(\\p{L})\\1{2,}")

    /// gtx inflates repeated characters far past the source: うわああああ (4 あ)
    /// comes back "Uwaaaaaaaaaaaaaaaaaaaa" (20 a). Clamp any run in the output to
    /// the longest run in the source so screams keep their original length.
    static func clampRuns(_ en: String, src: String) -> String {
        let runs = rxSrcRun.matches(src as NSString)
        // No run in the source means there is nothing to clamp AGAINST — bailing
        // out matters, because otherwise a max of 1 would flatten legitimate
        // English elongation the translation introduced on its own
        // (ぐっ → "Nnngh" must not become "Ngh").
        guard !runs.isEmpty else { return en }
        var maxRun = 2
        for r in runs { maxRun = max(maxRun, r.range.length) }
        return rxEnRun.replacingAll(en) { m, ns in
            let ch = group(m, 1, ns)
            return String(repeating: ch, count: min(m.range.length, maxRun))
        }
    }

    // MARK: - Sound effects
    //
    // A katakana-only bubble is a sound effect (or a name), never a sentence —
    // but gtx does not know that and reaches for a dictionary. Measured on real
    // pages:
    //
    //   グググ   → "Google"                 バキバキ… → "Breaking fast..."
    //   ペラペラ → "Fluent"                 カラン    → "Callan"
    //   ドキドキ → "My heart is pounding"   キラキラ  → "Sparkling"
    //
    // Blanket-romanising them all would be worse, though, because sometimes gtx
    // picks a genuinely better English onomatopoeia than a transliteration would:
    // バタン → "Bang", ふふふ → "Hehehe". So the test is not "is it katakana" but
    // "did gtx TRANSLITERATE or TRANSLATE it" — romanise the source ourselves and
    // compare. Close to our romaji means it transliterated (keep its nicer
    // spelling); far from it means it went to the dictionary (use the romaji).

    private static let kanaRomaji: [Character: String] = [
        "ア": "a", "イ": "i", "ウ": "u", "エ": "e", "オ": "o",
        "カ": "ka", "キ": "ki", "ク": "ku", "ケ": "ke", "コ": "ko",
        "サ": "sa", "シ": "shi", "ス": "su", "セ": "se", "ソ": "so",
        "タ": "ta", "チ": "chi", "ツ": "tsu", "テ": "te", "ト": "to",
        "ナ": "na", "ニ": "ni", "ヌ": "nu", "ネ": "ne", "ノ": "no",
        "ハ": "ha", "ヒ": "hi", "フ": "fu", "ヘ": "he", "ホ": "ho",
        "マ": "ma", "ミ": "mi", "ム": "mu", "メ": "me", "モ": "mo",
        "ヤ": "ya", "ユ": "yu", "ヨ": "yo",
        "ラ": "ra", "リ": "ri", "ル": "ru", "レ": "re", "ロ": "ro",
        "ワ": "wa", "ヲ": "o", "ン": "n",
        "ガ": "ga", "ギ": "gi", "グ": "gu", "ゲ": "ge", "ゴ": "go",
        "ザ": "za", "ジ": "ji", "ズ": "zu", "ゼ": "ze", "ゾ": "zo",
        "ダ": "da", "ヂ": "ji", "ヅ": "zu", "デ": "de", "ド": "do",
        "バ": "ba", "ビ": "bi", "ブ": "bu", "ベ": "be", "ボ": "bo",
        "パ": "pa", "ピ": "pi", "プ": "pu", "ペ": "pe", "ポ": "po",
        "ヴ": "vu",
    ]
    private static let kanaSmall: [Character: String] = [
        "ャ": "ya", "ュ": "yu", "ョ": "yo", "ァ": "a", "ィ": "i", "ゥ": "u", "ェ": "e", "ォ": "o",
    ]

    /// Hepburn-ish transliteration. Handles ー (long vowel), ッ (gemination) and
    /// small-kana digraphs (キャ → kya, シュ → shu).
    static func katakanaToRomaji(_ s: String) -> String {
        var out = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            if c == "ー" {                                   // long vowel: double the last
                if let last = out.last { out.append(last) }
                i += 1
                continue
            }
            if c == "ッ" {                                   // gemination
                if let n = next, let mapped = kanaRomaji[n], let first = mapped.first {
                    out.append(first)
                }
                i += 1
                continue
            }
            guard let base = kanaRomaji[c] else { i += 1; continue }
            if let n = next, let small = kanaSmall[n] {
                // キャ = ki + ya → kya;  シャ = shi + ya → sha (drop the i, keep sh)
                let stem = base.hasSuffix("i") ? String(base.dropLast()) : base
                let glide: String
                if small.hasPrefix("y"), "aou".contains(small.dropFirst().first ?? " ") {
                    glide = (base.hasSuffix("i") && base.count > 2) ? String(small.dropFirst()) : small
                } else {
                    glide = small
                }
                out += stem + glide
                i += 2
                continue
            }
            out += base
            i += 1
        }
        return out
    }

    // Hangul is compositional, so romanisation is arithmetic rather than a table:
    // a syllable's code point encodes (initial × 21 + medial) × 28 + final.
    // Revised Romanization of the jamo, which is all the SFX test needs.
    private static let jamoInitial = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "",
                                      "j", "jj", "ch", "k", "t", "p", "h"]
    private static let jamoMedial = ["a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae",
                                     "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"]
    private static let jamoFinal = ["", "k", "k", "k", "n", "n", "n", "t", "l", "l", "l", "l", "l", "l",
                                    "l", "l", "m", "p", "p", "t", "t", "ng", "t", "t", "k", "t", "p", "t"]

    static func hangulToRomaja(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            let code = Int(ch.value) - 0xAC00
            guard code >= 0, code <= 11171 else { continue }
            out += jamoInitial[code / 588] + jamoMedial[(code % 588) / 28] + jamoFinal[code % 28]
        }
        return out
    }

    /// 0 = identical, 1 = nothing in common. Case- and length-normalised.
    private static func phoneticDistance(_ a: String, _ b: String) -> Double {
        let x = a.lowercased().filter { $0.isASCII && $0.isLetter }
        let y = b.lowercased().filter { $0.isASCII && $0.isLetter }
        if x.isEmpty || y.isEmpty { return 1 }
        return Double(editDistance(Array(x), Array(y))) / Double(max(x.count, y.count))
    }

    private static func editDistance(_ s: [Character], _ t: [Character]) -> Int {
        var prev = Array(0...t.count)
        for i in 1...max(s.count, 1) where !s.isEmpty {
            var cur = [i]
            for j in 1...max(t.count, 1) where !t.isEmpty {
                cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (s[i - 1] == t[j - 1] ? 0 : 1)))
            }
            prev = cur
        }
        return prev[t.count]
    }

    /// Katakana, long marks and small kana only — plus trailing punctuation. A
    /// sentence has particles in hiragana or kanji, so this cannot match dialogue.
    ///
    /// NOT applied to Korean, and the asymmetry is the reason. Katakana is a
    /// SEPARATE script, reserved for foreign words and sound effects, so
    /// "katakana-only" is real evidence that a bubble is an effect. Hangul is
    /// Korean's ONLY script, so "Hangul-only" is evidence of nothing — short,
    /// space-free Korean sentences are completely ordinary. Trying it anyway
    /// turned 조심해！("Be careful!") into "Josimhae!", 쿵 ("Thump") into "Kung"
    /// and 반짝반짝 ("Twinkle") into "Banjjakbanjjak". Korean SFX would need a
    /// different signal — this one does not transfer.
    private static let rxKatakanaOnly = RX("^[\u{30A0}-\u{30FF}\u{30FC}]+[\\s!?！？.。…、,ッっ]*$")
    private static let rxTrailingJunk = RX("[\\s!?！？.。…、,~]+$")
    private static let rxTrailingPunctSpace = RX("[\\s!?！？.。…、,]+$")
    private static let rxTrailingPunct = RX("[!?！？.。…、,]+$")

    /// gtx sent a katakana bubble to the dictionary — take the romaji instead.
    static func fixSfx(_ en: String, src: String) -> String {
        let core = rxTrailingJunk.replacingAll(src, with: "")
        guard rxKatakanaOnly.test(core), core.count <= 8 else { return en }
        let romaji = katakanaToRomaji(core)
        guard romaji.count >= 2 else { return en }
        // Measured distances — note they do NOT separate cleanly:
        //
        //   keep    Gacha/Doki/Zawazawa 0.00 · Zabun 0.17 · Bang 0.60
        //   replace Callan 0.50 · "Breaking fast" 0.58 · Google 0.83 ·
        //           Sparkling 0.78 · "My heart is pounding" 0.82
        //
        // バタン → "Bang" (0.60) sits ABOVE バキバキ → "Breaking fast" (0.58), so
        // no threshold keeps the good English onomatopoeia without also keeping
        // the mistranslations. 0.5 deliberately sacrifices "Bang" → "Batan": a
        // plain transliteration is never WRONG, only less colourful, whereas a
        // confident mistranslation puts a false sentence on the page.
        if phoneticDistance(en, romaji) <= 0.5 { return en }
        let cap = romaji.prefix(1).uppercased() + romaji.dropFirst()
        guard rxTrailingPunctSpace.test(src) else { return cap }
        let ns = src as NSString
        let tail = rxTrailingPunct.firstMatch(ns).map { ns.substring(with: $0.range) } ?? ""
        return cap + asciiPunct(tail)
    }

    // MARK: - Stutters, held vowels and words split across a pause

    /// A scream is a word with its last sound HELD: いやあああ, そんなーーー,
    /// ええええっ！？. gtx translates the word and then mishandles the hold three
    /// different ways — いやあああ → "Noaaa" (Japanese vowel glued onto English),
    /// そんなーーー → "That's so..." (hold dropped), ええええっ！？ → "Yeah yeah!?"
    /// (hold became a repeated WORD). So the hold comes off before translating and
    /// goes back onto the English, which is what a letterer would draw.
    private static let rxHold = RX("([ぁ-おァ-オー아-이])\\1+(?=[っッ]?[^ぁ-んァ-ヶ一-\u{9FFF}가-힣]*$)")

    static func stripHold(_ t: String) -> (text: String, hold: Int) {
        let ns = t as NSString
        guard let m = rxHold.firstMatch(ns) else { return (t, 0) }
        let atStart = m.range.location == 0
        // Keep one instance so the base is still a word (いやあああ → いや + hold 3;
        // ええええ → え + hold 3, not an empty base).
        let base = ns.substring(to: m.range.location)
            + (atStart ? group(m, 1, ns) : "")
            + ns.substring(from: m.range.location + m.range.length)
        return (base, m.range.length - (atStart ? 1 : 0))
    }

    private static let rxLastLetter = RX("(\\p{L})(\\P{L}*)$")

    static func applyHold(_ en: String, hold: Int) -> String {
        guard hold >= 2 else { return en }
        // Repeat the final LETTER of the last word — "No"→"Nooo", "Eh"→"Ehhh",
        // "That's so"→"That's sooo" — leaving trailing punctuation where it is.
        return rxLastLetter.replacingFirst(en) { m, ns in
            String(repeating: group(m, 1, ns), count: 1 + min(hold, 5)) + group(m, 2, ns)
        }
    }

    /// A stutter (ま、まさか… / だ、誰だお前は) is a first-mora repeat. Sent as-is,
    /// gtx translates the stray mora as its own word — "Well, no way..." and
    /// "Who are you?" (stutter dropped). So we strip it before translating and
    /// re-apply it to the English, the way a scanlator letters it:
    /// "N-no way..." / "W-who are you?"
    private static let rxStutter = RX("^(.)[、,]\\s*(?=\\1)")

    static func stripStutter(_ t: String) -> (text: String, stutter: Bool) {
        guard rxStutter.test(t) else { return (t, false) }
        return (rxStutter.replacingAll(t, with: ""), true)
    }

    private static let rxFirstWord = RX("^([A-Za-z])(\\w*)")

    static func restoreStutter(_ en: String) -> String {
        let ns = en as NSString
        guard let m = rxFirstWord.firstMatch(ns) else { return en }
        let first = group(m, 1, ns)
        return "\(first)-\(first.lowercased())\(ns.substring(from: 1))"
    }

    /// Letterers break a word across a dramatic pause — 帰らな…くて…は… is one word,
    /// 帰らなくては, drawn with the ellipses spread through it. Sent as drawn, gtx
    /// parses the fragments separately and can invert the meaning outright:
    ///
    ///   帰らな…くて…は…   → "I don't want to go home..."
    ///   帰らなくては…      → "I have to go home..."      (what it actually says)
    ///
    /// So the interior ellipses come out before translating. Only when the run
    /// BEFORE the pause is two or more Japanese characters, though: a single kana
    /// ahead of a pause is a gasp or a stutter that carries real meaning, and
    /// joining it loses that — え…ええっ！？ is "Eh...ehh!?", and stripping its
    /// ellipsis translated it as a flat "Yeah!?".
    private static let rxSplitWord = RX("([\u{3040}-\u{30FF}一-\u{9FFF}]{2,})…+(?=[\u{3040}-\u{30FF}一-\u{9FFF}])")

    static func joinSplitWords(_ t: String) -> String {
        rxSplitWord.replacingAll(t, with: "$1")
    }

    // MARK: - Honorifics
    //
    // Keep them as suffixes, the way a scanlator letters them.
    //
    // gtx is inconsistent about this — 「…アカネさん？」 comes back "...Akane-san?"
    // but 「丸山さん…」 comes back "Mr. Maruyama...", so the same page can address
    // two characters in two different conventions. Where the SOURCE carried an
    // honorific and the English turned it into a title, put the suffix back.
    //
    // Only rewrites "Title + Name": a bare noun must be left alone, or
    // 「僕はこの子達の先生だから」 ("I am the teacher of these children") would
    // become "...the -sensei of these children".

    private struct Honorific {
        let jp: RX
        let en: String
        let titles: String   // pattern source, combined with the name matcher below
    }

    private static let honorifics: [Honorific] = [
        // Longest/most specific first — 兄さん must not be matched by the さん rule.
        Honorific(jp: RX("姉(さん|ちゃん)|お姉[さち]ゃん"), en: "nee",
                  titles: "\\b(?:Sister|Big Sister)\\s+"),
        Honorific(jp: RX("兄(さん|ちゃん)|お兄[さち]ゃん"), en: "nii",
                  titles: "\\b(?:Brother|Big Brother)\\s+"),
        Honorific(jp: RX("先輩"), en: "senpai", titles: "\\b(?:Senior|Senpai)\\s+"),
        Honorific(jp: RX("先生"), en: "sensei", titles: "\\b(?:Teacher|Doctor|Dr)\\.?\\s+"),
        Honorific(jp: RX("[様さ]ま|様"), en: "sama", titles: "\\b(?:Lord|Lady|Master|Sir)\\s+"),
        Honorific(jp: RX("殿(?![ぁ-ん])|どの(?=[、。！？…\\s]|$)"), en: "dono",
                  titles: "\\b(?:Lord|Sir)\\s+"),
        Honorific(jp: RX("ちゃん"), en: "chan", titles: "\\b(?:Little|Miss)\\s+"),
        Honorific(jp: RX("(?:君|くん)(?![ぁ-ん])"), en: "kun", titles: "\\b(?:Master|Mr)\\.?\\s+"),
        Honorific(jp: RX("さん(?![ぁ-ん])"), en: "san", titles: "\\b(?:Mr|Mrs|Ms|Miss)\\.?\\s+"),
    ]

    // The commoner honorific failure is not a title — it is a SILENT DROP. gtx
    // transliterates the name correctly and throws the suffix away:
    //
    //   ローズさん、こんにちは  → "Hello Rose,"      (-san gone)
    //   ベル君、こんにちは      → "Hello Bell,"      (-kun gone)
    //
    // Measured over 16 katakana names: 7 dropped the honorific, 3 kept it, 2
    // turned it into a title, 2 read the name as a common noun. So this is the
    // single biggest honorific bug, and it needs the name's ENGLISH spelling to
    // fix. Rather than transliterate ourselves — mechanical Hepburn would turn
    // ルフィ into "Rufi" where gtx gives "Luffy" — the bare names ride along as
    // extra segments in the batch request that is already going out. Same one
    // request, and gtx's own romanisation is reused.
    private static let rxNameHonorific = RX(
        "([\u{30A0}-\u{30FF}一-\u{9FFF}][\u{30A0}-\u{30FF}一-\u{9FFF}ー]{1,7})"
        + "(さん|ちゃん|くん|君|様|さま|殿|先輩)(?![ぁ-ん])")
    private static let jpSuffix = [
        "さん": "san", "ちゃん": "chan", "くん": "kun", "君": "kun",
        "様": "sama", "さま": "sama", "殿": "dono", "先輩": "senpai",
    ]
    private static let rxRelationName = RX("^[兄姉母父]")

    // Korean: 씨/님 attach directly, the relationship terms follow a space. gtx
    // drops 씨 outright (민수씨 → "Minsu.") and is inconsistent with the rest —
    // 준호 오빠 → "Junho oppa" but 지은 언니 → "Ji-eun sister".
    private static let rxKoNameHonorific = RX("([가-힣]{2,4})\\s*(씨|님|선배|오빠|언니|형|누나)(?![가-힣])")
    private static let koSuffix = [
        "씨": "ssi", "님": "nim", "선배": "sunbae", "오빠": "oppa",
        "언니": "eonni", "형": "hyung", "누나": "noona",
    ]
    // Role words, not names — 사장님/선생님 read better as "boss"/"teacher".
    // 선배님/후배님 are roles too — 선배 only acts as a SUFFIX after a real name
    // (민수 선배). Without this, 선배님 parsed as name=선배 + 님 → "senior-nim".
    private static let rxKoRole = RX("^(사장|선생|부장|과장|회장|팀장|손님|고객|선배|후배|아저씨|아주머니)$")

    /// `lang` is REQUIRED, because these characters are not language-specific.
    /// 殿, 君 and 先輩 are ordinary Chinese words — 殿 is "hall" — so running the
    /// Japanese patterns over Chinese produced "Jinluan-dono Palace is very big"
    /// for 金鑾殿很大. Honorific suffixing is a Japanese/Korean scanlation
    /// convention; Chinese translations use plain English titles and are left alone.
    ///
    /// Returned in encounter order (the web port relies on a JS `Map`'s insertion
    /// order to line the extra request segments back up with their names).
    static func findNamedHonorifics(_ texts: [String], lang: String) -> [(name: String, suffix: String)] {
        var found: [(name: String, suffix: String)] = []
        var seen = Set<String>()
        let ja = lang.hasPrefix("ja")
        let ko = lang.hasPrefix("ko")
        guard ja || ko else { return found }

        func add(_ name: String, _ suffix: String) {
            if seen.insert(name).inserted { found.append((name, suffix)) }
            // A repeat of the same name keeps its FIRST suffix, matching Map.set
            // semantics closely enough — a page rarely addresses one character
            // two ways, and when it does the first spelling is the one gtx saw.
        }

        if ko {
            for t in texts {
                let ns = t as NSString
                for m in rxKoNameHonorific.matches(ns) {
                    let name = group(m, 1, ns)
                    if rxKoRole.test(name) { continue }
                    if let suffix = koSuffix[group(m, 2, ns)] { add(name, suffix) }
                }
            }
        }
        if ja {
            for t in texts {
                let ns = t as NSString
                for m in rxNameHonorific.matches(ns) {
                    let name = group(m, 1, ns)
                    // 兄さん / お姉ちゃん are relationship words, not names — the
                    // -nee/-nii rules above already cover those.
                    if rxRelationName.test(name) || name.count < 2 { continue }
                    if let suffix = jpSuffix[group(m, 2, ns)] { add(name, suffix) }
                }
            }
        }
        return found
    }

    private static let rxNameShape = RX("^[\\p{L}][\\p{L}'-]*$")
    private static let rxNameTrim = RX("^[^\\p{L}]+|[^\\p{L}]+$")
    private static let allSuffixes =
        "san|chan|kun|sama|dono|senpai|sensei|nee|nii|ssi|nim|sunbae|oppa|eonni|hyung|noona"

    /// Append `-suffix` to the name where gtx dropped it. Skips a name that
    /// already carries any honorific, so a correct "Luffy-sama" is never touched.
    static func reattachHonorific(_ en: String, englishName: String?, suffix: String) -> String {
        let name = rxNameTrim.replacingAll(
            (englishName ?? "").trimmingCharacters(in: .whitespacesAndNewlines), with: "")
        // Case-INSENSITIVE on purpose. gtx lowercases any name it reads as an
        // ordinary word — ローズ comes back "rose", ベル "bell", even ルフィ
        // "luffy" — while the sentence itself capitalises it ("Hello Rose,").
        // Matching on the bare translation's capitalisation missed exactly the
        // names that need this most. Two characters minimum, so a stray "a"/"I"
        // cannot match.
        guard name.count >= 2, rxNameShape.test(name) else { return en }
        let quoted = NSRegularExpression.escapedPattern(for: name)
        // Match the SPACE form as well as the hyphen: gtx already writes
        // "Junho oppa" for 준호 오빠, and only checking for "Junho-oppa" produced
        // "Junho-oppa oppa".
        let already = RX("\\b\(quoted)[\\s-](?:\(allSuffixes))\\b", .caseInsensitive)
        if already.test(en) { return en }
        // Keep whatever casing the sentence used; only add the suffix.
        return RX("\\b\(quoted)\\b", .caseInsensitive).replacingAll(en) { m, ns in
            ns.substring(with: m.range) + "-" + suffix
        }
    }

    static func restoreHonorifics(_ en: String, src: String, lang: String) -> String {
        guard lang.hasPrefix("ja") else { return en }   // see findNamedHonorifics
        var out = en
        for h in honorifics {
            guard h.jp.test(src) else { continue }
            // The name has to look like a name: a capitalised word right after
            // the title. `Mr. Maruyama` → `Maruyama-san`; `the teacher of` is
            // untouched.
            out = RX(h.titles + "([A-Z][\\w'-]*)").replacingAll(out, with: "$1-\(h.en)")
            if out != en { break }   // one honorific per line is the normal case
        }
        return out
    }

    // MARK: - Assembly

    /// gtx leaves subject-less fragments lowercase
    /// (俺たちは仲間だろ → "we are friends").
    static func capitalize(_ s: String) -> String {
        s.isEmpty ? s : s.prefix(1).uppercased() + s.dropFirst()
    }

    static func polish(_ en: String, src: String, stutter: Bool, lang: String) -> String {
        var out = fixPunct(en)
        out = fixSfx(out, src: src)
        out = restoreHonorifics(out, src: src, lang: lang)
        out = clampRuns(out, src: src)
        if stutter { out = restoreStutter(out) }
        return capitalize(out)
    }

    /// The lexicon short-circuit: an exact set-phrase hit answered locally,
    /// carrying the source's own punctuation across as ASCII (the lexicon
    /// bypasses gtx, which is what would normally fold ！？ down for us).
    /// English targets only — the phrasings are English.
    static func lexiconHit(for text: String, target: String) -> String? {
        guard target == "en" else { return nil }
        let bare = RX("[！？!?。．.…、,\\s]+$").replacingAll(text, with: "")
        guard let hit = lexicon[bare] else { return nil }
        let ns = text as NSString
        let tail = ns.length > (bare as NSString).length
            ? ns.substring(from: (bare as NSString).length)
            : ""
        return fixPunct(hit + asciiPunct(tail))
    }
}
