//
//  OcrProvider+MLKit.swift
//  Aidoku (iOS)
//
//  Google ML Kit OCR path — mirrors nyora-android's `OcrProvider.runEnsembleOcr`
//  (four parallel recognizers: Japanese, Chinese, Korean, Latin; keep the pass
//  with the most CJK-weighted text). ML Kit's language-specific models read
//  VERTICAL Japanese (tategaki) — which Apple Vision cannot — so this is the
//  real OCR engine on device.
//
//  ML Kit's prebuilt binaries have NO arm64 iOS-Simulator slice, and Xcode 26
//  no longer ships an x86_64 iOS-simulator runtime (so the EXCLUDED_ARCHS +
//  Rosetta trick can't target a simulator here). The file is therefore compiled
//  out on the simulator, where `OcrProvider.runOcr` uses the Apple Vision
//  ensemble; on a real device ML Kit is the OCR engine (it reads tategaki).
//

import CoreGraphics

#if canImport(MLKitTextRecognition) && !targetEnvironment(simulator)

import UIKit
import MLKitVision
import MLKitTextRecognition
import MLKitTextRecognitionJapanese
import MLKitTextRecognitionChinese
import MLKitTextRecognitionKorean

extension OcrProvider {
    /// Compiled-in only on device with the ML Kit package linked.
    static let mlkitAvailable = true

    /// Run the Android-equivalent ML Kit ensemble. Returns blocks in image-pixel
    /// coordinates (top-left origin) — the same shape the Vision path yields, so
    /// `MangaTranslator` consumes it unchanged.
    func runMLKitOcr(cgImage: CGImage, imageSize: CGSize, sourceLang: String) async -> TextResult {
        let uiImage = UIImage(cgImage: cgImage)

        // Four recognizers, run in parallel, best-of by CJK-weighted score —
        // exactly nyora-android's strategy.
        async let ja = Self.recognise(uiImage, recognizer: MLKitRecognizers.shared.japanese)
        async let zh = Self.recognise(uiImage, recognizer: MLKitRecognizers.shared.chinese)
        async let ko = Self.recognise(uiImage, recognizer: MLKitRecognizers.shared.korean)
        async let en = Self.recognise(uiImage, recognizer: MLKitRecognizers.shared.latin)

        let passes = await [ja, zh, ko, en]
        let best = passes.max { Self.score($0.map(\.text).joined()) < Self.score($1.map(\.text).joined()) } ?? []
        return TextResult(blocks: best, language: Self.detectScript(best.map(\.text).joined()))
    }

    /// Bridge one ML Kit `TextRecognizer.process` call to async, mapping its
    /// text blocks into `MangaBlock`s (image-pixel rects, top-left origin).
    private static func recognise(_ image: UIImage, recognizer: TextRecognizer) async -> [MangaBlock] {
        let visionImage = VisionImage(image: image)
        visionImage.orientation = .up
        return await withCheckedContinuation { cont in
            recognizer.process(visionImage) { result, _ in
                guard let result else { cont.resume(returning: []); return }
                let blocks: [MangaBlock] = result.blocks.compactMap { block in
                    let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    return MangaBlock(text: block.text, boundingBox: block.frame)
                }
                cont.resume(returning: blocks)
            }
        }
    }
}

/// Lazily-built, shared ML Kit recognizers (model init is expensive; the
/// recognizers are thread-safe for `process`).
private final class MLKitRecognizers {
    static let shared = MLKitRecognizers()
    let japanese = TextRecognizer.textRecognizer(options: JapaneseTextRecognizerOptions())
    let chinese = TextRecognizer.textRecognizer(options: ChineseTextRecognizerOptions())
    let korean = TextRecognizer.textRecognizer(options: KoreanTextRecognizerOptions())
    let latin = TextRecognizer.textRecognizer(options: TextRecognizerOptions())
    private init() {}
}

#else

extension OcrProvider {
    /// ML Kit isn't linked (simulator / package absent) — the Vision ensemble
    /// in `runOcr` is used instead.
    static let mlkitAvailable = false

    func runMLKitOcr(cgImage: CGImage, imageSize: CGSize, sourceLang: String) async -> TextResult {
        TextResult(blocks: [], language: "en")
    }
}

#endif
