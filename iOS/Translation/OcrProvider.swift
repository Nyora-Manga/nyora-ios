import Vision
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Apple Vision OCR using the same preprocessing + ensemble strategy as nyora-android
/// (`OcrProvider.runEnsembleOcr` / `preprocessBitmapForOcr`):
///   1. Preprocess: 1.5× upscale → grayscale → contrast 1.8 → light unsharp.
///   2. Ensemble: run parallel Vision passes (JA, ZH, KO, EN), score each by
///      text length + CJK bonus, keep the winner. (Android runs one ML Kit recognizer
///      per language; Vision is the iOS-native equivalent.)
///   3. Tile very tall webtoon strips (aspect > 2.5) and dedupe.
actor OcrProvider {
    struct MangaBlock {
        let text: String
        let boundingBox: CGRect   // image pixels, top-left origin
    }
    struct TextResult {
        let blocks: [MangaBlock]
        let language: String
        var isEmpty: Bool { blocks.isEmpty }
    }

    private let scaleFactor: CGFloat = 1.5
    private let tilePixelHeight: CGFloat = 1800
    private let tileOverlap: CGFloat = 200

    func runOcr(cgImage: CGImage, imageSize: CGSize, sourceLang: String) async -> TextResult {
        let aspect = imageSize.height / max(imageSize.width, 1)
        if aspect > 2.5 {
            return await runTiledOcr(cgImage: cgImage, imageSize: imageSize, sourceLang: sourceLang)
        }
        let processed = preprocess(cgImage)
        let blocks = await ensembleOcr(image: processed, sourceLang: sourceLang)
        let mapped = remapToOriginal(blocks: blocks, processed: processed, original: imageSize)
        return TextResult(blocks: mapped, language: Self.detectScript(mapped.map(\.text).joined()))
    }

    // MARK: Tiled OCR for tall webtoons

    private func runTiledOcr(cgImage: CGImage, imageSize: CGSize, sourceLang: String) async -> TextResult {
        let totalH = imageSize.height
        let step = tilePixelHeight - tileOverlap
        var collected: [MangaBlock] = []
        var y: CGFloat = 0
        while y < totalH {
            let h = min(tilePixelHeight, totalH - y)
            if h < 100 { break }
            guard let tile = cgImage.cropping(to: CGRect(x: 0, y: y, width: imageSize.width, height: h)) else {
                y += step; continue
            }
            let processed = preprocess(tile)
            let tileBlocks = await ensembleOcr(image: processed, sourceLang: sourceLang)
            let mapped = remapToOriginal(blocks: tileBlocks, processed: processed,
                                         original: CGSize(width: imageSize.width, height: h))
            let offsetY = y
            collected.append(contentsOf: mapped.map {
                MangaBlock(text: $0.text, boundingBox: $0.boundingBox.offsetBy(dx: 0, dy: offsetY))
            })
            y += step
        }
        let deduped = dedupe(collected)
        return TextResult(blocks: deduped, language: Self.detectScript(deduped.map(\.text).joined()))
    }

    private func dedupe(_ blocks: [MangaBlock]) -> [MangaBlock] {
        var out: [MangaBlock] = []
        for b in blocks {
            let dup = out.contains {
                $0.text == b.text &&
                abs($0.boundingBox.midY - b.boundingBox.midY) < 60 &&
                abs($0.boundingBox.midX - b.boundingBox.midX) < 80
            }
            if !dup { out.append(b) }
        }
        return out
    }

    // MARK: Preprocessing (Android-equivalent CIImage chain)

    private func preprocess(_ cgImage: CGImage) -> CGImage {
        let w = max(1, Int(CGFloat(cgImage.width) * scaleFactor))
        let h = max(1, Int(CGFloat(cgImage.height) * scaleFactor))
        var ci = CIImage(cgImage: cgImage)

        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = ci; lanczos.scale = Float(scaleFactor); lanczos.aspectRatio = 1.0
        if let s = lanczos.outputImage { ci = s }

        let gray = CIFilter.colorControls()
        gray.inputImage = ci; gray.saturation = 0; gray.brightness = 0; gray.contrast = 1.0
        if let g = gray.outputImage { ci = g }

        let contrast = CIFilter.colorControls()
        contrast.inputImage = ci; contrast.contrast = 1.8
        if let c = contrast.outputImage { ci = c }

        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = ci; sharpen.radius = 1.5; sharpen.intensity = 0.5
        if let sh = sharpen.outputImage { ci = sh }

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        let target = CGRect(x: 0, y: 0, width: w, height: h)
        let extent = ci.extent.intersection(target)
        if let out = ctx.createCGImage(ci, from: extent.isEmpty ? target : extent) { return out }
        return cgImage
    }

    // MARK: Ensemble (parallel pass per language, keep best)

    private func ensembleOcr(image: CGImage, sourceLang: String) async -> [MangaBlock] {
        let langPasses: [(name: String, langs: [String])]
        switch sourceLang.lowercased() {
        case "japanese", "ja":
            langPasses = [("ja", ["ja-JP"]), ("zh", ["zh-Hans"]), ("ko", ["ko-KR"]), ("en", ["en-US"])]
        case "korean", "ko":
            langPasses = [("ko", ["ko-KR"]), ("ja", ["ja-JP"]), ("en", ["en-US"])]
        case "chinese", "zh":
            langPasses = [("zh", ["zh-Hans", "zh-Hant"]), ("ja", ["ja-JP"]), ("en", ["en-US"])]
        case "auto", "":
            langPasses = [("ja", ["ja-JP"]), ("zh", ["zh-Hans"]), ("ko", ["ko-KR"]), ("en", ["en-US"])]
        default:
            langPasses = [(sourceLang, Self.recognitionLanguages(for: sourceLang))]
        }

        let results = await withTaskGroup(of: (String, [MangaBlock]).self) { group -> [(String, [MangaBlock])] in
            for pass in langPasses {
                group.addTask { (pass.name, await Self.visionRecognise(cgImage: image, languages: pass.langs)) }
            }
            var out: [(String, [MangaBlock])] = []
            for await r in group { out.append(r) }
            return out
        }
        let best = results.max { Self.score($0.1.map(\.text).joined()) < Self.score($1.1.map(\.text).joined()) }
        return best?.1 ?? []
    }

    private static func score(_ text: String) -> Int {
        if text.isEmpty { return 0 }
        let cjk = text.unicodeScalars.reduce(0) { acc, s in
            acc + (((0x4E00...0x9FFF).contains(s.value) ||
                    (0x3040...0x30FF).contains(s.value) ||
                    (0xAC00...0xD7AF).contains(s.value)) ? 1 : 0)
        }
        return text.count + cjk * 5
    }

    private static func visionRecognise(cgImage: CGImage, languages: [String]) async -> [MangaBlock] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { req, error in
                    guard error == nil,
                          let obs = req.results as? [VNRecognizedTextObservation], !obs.isEmpty
                    else { cont.resume(returning: []); return }
                    let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
                    let blocks: [MangaBlock] = obs.compactMap { o in
                        guard let top = o.topCandidates(1).first,
                              !top.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        else { return nil }
                        let box = CGRect(x: o.boundingBox.minX * w,
                                         y: (1 - o.boundingBox.maxY) * h,
                                         width: o.boundingBox.width * w,
                                         height: o.boundingBox.height * h)
                        return MangaBlock(text: top.string, boundingBox: box)
                    }
                    cont.resume(returning: blocks)
                }
                request.recognitionLevel = .accurate
                let supported = Set((try? request.supportedRecognitionLanguages()) ?? [])
                let usable = languages.filter { supported.contains($0) }
                request.recognitionLanguages = usable.isEmpty ? ["en-US"] : usable
                request.usesLanguageCorrection = true
                if #available(iOS 16, *) {
                    request.automaticallyDetectsLanguage = false
                    request.revision = VNRecognizeTextRequestRevision3
                }
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do { try handler.perform([request]) } catch { cont.resume(returning: []) }
            }
        }
    }

    private func remapToOriginal(blocks: [MangaBlock], processed: CGImage, original: CGSize) -> [MangaBlock] {
        let sx = original.width / CGFloat(processed.width)
        let sy = original.height / CGFloat(processed.height)
        return blocks.map {
            MangaBlock(text: $0.text, boundingBox: CGRect(
                x: $0.boundingBox.minX * sx, y: $0.boundingBox.minY * sy,
                width: $0.boundingBox.width * sx, height: $0.boundingBox.height * sy))
        }
    }

    static func recognitionLanguages(for sourceLang: String) -> [String] {
        switch sourceLang.lowercased() {
        case "japanese", "ja": return ["ja-JP", "en-US"]
        case "chinese", "zh": return ["zh-Hans", "zh-Hant", "en-US"]
        case "korean", "ko": return ["ko-KR", "en-US"]
        case "russian", "ru": return ["ru-RU", "en-US"]
        case "arabic", "ar": return ["ar-SA", "en-US"]
        case "thai", "th": return ["th-TH", "en-US"]
        case "vietnamese", "vi": return ["vi-VT", "en-US"]
        case "indonesian", "id": return ["id-ID", "en-US"]
        case "turkish", "tr": return ["tr-TR", "en-US"]
        case "auto", "english", "en", "": return ["en-US", "ja-JP", "zh-Hans", "ko-KR"]
        default: return ["en-US"]
        }
    }

    static func detectScript(_ text: String) -> String {
        if text.unicodeScalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) { return "ko" }
        if text.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) { return "ja" }
        if text.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) { return "zh" }
        return "en"
    }
}
