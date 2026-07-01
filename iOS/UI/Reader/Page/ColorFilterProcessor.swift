//
//  ColorFilterProcessor.swift
//  Aidoku (iOS)
//
//  Reader color-filter engine (NP-002 foundation).
//
//  A CoreImage colour-matrix pipeline applied to every reader page image,
//  driven by the `Reader.cf*` UserDefaults keys. When all values are at their
//  defaults the settings are "neutral" and the pipeline is a complete no-op
//  (the original image is returned untouched, and no CIFilter work happens).
//
//  This mirrors nyora-android `reader/domain/ReaderColorFilter.kt` and
//  nyora-mac `AI/ColorFilterEngine.swift`, re-implemented natively.
//

import CoreImage
import Foundation
import Nuke
import UIKit

// MARK: - Settings

/// Snapshot of the reader colour-filter settings, read from UserDefaults.
///
/// Neutral (all-default) settings mean the engine performs no work.
struct ReaderColorFilterSettings: Equatable, Hashable {
    /// Additive brightness, neutral at 0. Range roughly -1.0...1.0.
    var brightness: Double
    /// Contrast offset, neutral at 0. Range roughly -1.0...1.0.
    var contrast: Double
    var isInverted: Bool
    var isGrayscale: Bool
    /// Warm "book" background — removes some blue to reduce eye strain.
    var isBookBackground: Bool
    /// Multitone preset id (0 == none). See `ColorFilterPreset`.
    var multitonePreset: Int

    static let neutral = ReaderColorFilterSettings(
        brightness: 0,
        contrast: 0,
        isInverted: false,
        isGrayscale: false,
        isBookBackground: false,
        multitonePreset: 0
    )

    /// Reads the current settings from UserDefaults.
    static var current: ReaderColorFilterSettings {
        let defaults = UserDefaults.standard
        return ReaderColorFilterSettings(
            brightness: defaults.double(forKey: "Reader.cfBrightness"),
            contrast: defaults.double(forKey: "Reader.cfContrast"),
            isInverted: defaults.bool(forKey: "Reader.cfInvert"),
            isGrayscale: defaults.bool(forKey: "Reader.cfGrayscale"),
            isBookBackground: defaults.bool(forKey: "Reader.cfBookBackground"),
            multitonePreset: defaults.integer(forKey: "Reader.cfMultitone")
        )
    }

    /// True when the settings would leave the image unchanged.
    var isNeutral: Bool {
        multitonePreset == 0
            && !isGrayscale
            && !isInverted
            && !isBookBackground
            && abs(brightness) < 0.0001
            && abs(contrast) < 0.0001
    }

    /// Stable string used to key image caches.
    var cacheKey: String {
        "\(brightness)-\(contrast)-\(isInverted)-\(isGrayscale)-\(isBookBackground)-\(multitonePreset)"
    }

    /// Builds the combined 4x5 colour matrix (row-major, RGBA + offset column,
    /// offset expressed in 0...255 space) that represents these settings.
    ///
    /// Mirrors `ReaderColorFilter.toColorFilter()` ordering exactly.
    func colorMatrix() -> ColorMatrix4x5 {
        var cm = ColorMatrix4x5.identity

        if multitonePreset != 0, let preset = ColorFilterPreset.byId(multitonePreset) {
            cm.applyMultitone(preset)
        } else if isGrayscale {
            cm.setSaturation(0)
        }

        if isInverted {
            cm.invert()
        }

        cm.applyBrightness(Float(brightness))
        cm.applyContrast(Float(contrast))

        if isBookBackground {
            cm.applyBookEffect()
        }

        return cm
    }
}

// MARK: - Colour matrix

/// A 4x5 colour matrix (row-major), matching Android's `ColorMatrix` semantics.
/// Rows are output R, G, B, A; the 5th column is a translation term in 0...255.
struct ColorMatrix4x5 {
    /// 20 floats, row-major.
    var values: [Float]

    static let bookBlueFactor: Float = 0.92

    static var identity: ColorMatrix4x5 {
        ColorMatrix4x5(values: [
            1, 0, 0, 0, 0,
            0, 1, 0, 0, 0,
            0, 0, 1, 0, 0,
            0, 0, 0, 1, 0
        ])
    }

    /// `self = other * self` (Android `postConcat` semantics).
    mutating func postConcat(_ other: [Float]) {
        values = Self.concat(other, values)
    }

    /// Returns `a * b`, treating both as 5x5 with an implicit `[0,0,0,0,1]` last row.
    static func concat(_ a: [Float], _ b: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: 20)
        for i in 0..<4 {
            for j in 0..<5 {
                var sum: Float = 0
                for k in 0..<4 {
                    sum += a[i * 5 + k] * b[k * 5 + j]
                }
                if j == 4 {
                    sum += a[i * 5 + 4]
                }
                result[i * 5 + j] = sum
            }
        }
        return result
    }

    /// Replaces the matrix with a saturation matrix (0 == full grayscale).
    mutating func setSaturation(_ sat: Float) {
        let invSat = 1 - sat
        let red = 0.213 * invSat
        let green = 0.715 * invSat
        let blue = 0.072 * invSat
        values = [
            red + sat, green, blue, 0, 0,
            red, green + sat, blue, 0, 0,
            red, green, blue + sat, 0, 0,
            0, 0, 0, 1, 0
        ]
    }

    mutating func invert() {
        postConcat([
            -1, 0, 0, 0, 255,
            0, -1, 0, 0, 255,
            0, 0, -1, 0, 255,
            0, 0, 0, 1, 0
        ])
    }

    mutating func applyBrightness(_ brightness: Float) {
        guard abs(brightness) > 0.0001 else { return }
        let scale = brightness + 1
        postConcat([
            scale, 0, 0, 0, 0,
            0, scale, 0, 0, 0,
            0, 0, scale, 0, 0,
            0, 0, 0, 1, 0
        ])
    }

    mutating func applyContrast(_ contrast: Float) {
        guard abs(contrast) > 0.0001 else { return }
        let scale = contrast + 1
        let translate = (-0.5 * scale + 0.5) * 255
        postConcat([
            scale, 0, 0, 0, translate,
            0, scale, 0, 0, translate,
            0, 0, scale, 0, translate,
            0, 0, 0, 1, 0
        ])
    }

    mutating func applyBookEffect() {
        postConcat([
            1, 0, 0, 0, 0,
            0, 1, 0, 0, 0,
            0, 0, Self.bookBlueFactor, 0, 0,
            0, 0, 0, 1, 0
        ])
    }

    mutating func applyMultitone(_ preset: ColorFilterPreset) {
        setSaturation(0)

        if preset.contrastOffset != 0 {
            applyContrast(preset.contrastOffset)
        }

        if let matrix = preset.matrixArray {
            postConcat(matrix)
            return
        }

        guard let dark = preset.darkColor, let light = preset.lightColor else { return }

        let rDark = Float(dark.0) / 255
        let gDark = Float(dark.1) / 255
        let bDark = Float(dark.2) / 255
        let rLight = Float(light.0) / 255
        let gLight = Float(light.1) / 255
        let bLight = Float(light.2) / 255

        postConcat([
            rLight - rDark, 0, 0, 0, rDark * 255,
            0, gLight - gDark, 0, 0, gDark * 255,
            0, 0, bLight - bDark, 0, bDark * 255,
            0, 0, 0, 1, 0
        ])
    }
}

// MARK: - Presets

/// Multitone presets ported from Android `ReaderColorFilter.Preset`.
struct ColorFilterPreset {
    let id: Int
    /// Duotone dark colour (r, g, b), if this preset is a two-colour gradient.
    let darkColor: (Int, Int, Int)?
    let lightColor: (Int, Int, Int)?
    let contrastOffset: Float
    /// Explicit 4x5 matrix for multitone (3+) presets, if provided.
    let matrixArray: [Float]?

    init(
        id: Int,
        darkColor: (Int, Int, Int)? = nil,
        lightColor: (Int, Int, Int)? = nil,
        contrastOffset: Float = 0,
        matrixArray: [Float]? = nil
    ) {
        self.id = id
        self.darkColor = darkColor
        self.lightColor = lightColor
        self.contrastOffset = contrastOffset
        self.matrixArray = matrixArray
    }

    static func byId(_ id: Int) -> ColorFilterPreset? {
        all.first { $0.id == id }
    }

    static let all: [ColorFilterPreset] = [
        // Duotones (1 - 5)
        .init(id: 1, darkColor: (28, 22, 14), lightColor: (252, 245, 229), contrastOffset: 0.05),
        .init(id: 2, darkColor: (15, 23, 42), lightColor: (241, 245, 249), contrastOffset: -0.05),
        .init(id: 3, darkColor: (46, 8, 84), lightColor: (224, 247, 250), contrastOffset: 0.18),
        .init(id: 4, darkColor: (12, 35, 24), lightColor: (232, 245, 233), contrastOffset: 0.02),
        .init(id: 5, darkColor: (46, 26, 22), lightColor: (251, 239, 239), contrastOffset: 0.06),
        // Tritones (6 - 10)
        .init(id: 6, matrixArray: [1.4, 0, 0, 0, 10, 1.1, 0, 0, 0, 25, 0.7, 0, 0, 0, 50, 0, 0, 0, 1, 0]),
        .init(id: 7, matrixArray: [1.3, 0, 0, 0, 30, 0.9, 0, 0, 0, 15, 0.6, 0, 0, 0, 10, 0, 0, 0, 1, 0]),
        .init(id: 8, contrastOffset: 0.05, matrixArray: [1.5, 0, 0, 0, 30, 0.8, 0, 0, 0, 10, 0.6, 0, 0, 0, 15, 0, 0, 0, 1, 0]),
        .init(id: 9, contrastOffset: -0.02, matrixArray: [0.6, 0, 0, 0, 10, 1.2, 0, 0, 0, 28, 1.4, 0, 0, 0, 42, 0, 0, 0, 1, 0]),
        .init(id: 10, contrastOffset: 0.04, matrixArray: [0.9, 0, 0, 0, 28, 1.3, 0, 0, 0, 30, 0.8, 0, 0, 0, 26, 0, 0, 0, 1, 0]),
        // Quadratones (11 - 15)
        .init(id: 11, contrastOffset: 0.1, matrixArray: [1.5, 0, 0, 0, 11, 0.9, 0, 0, 0, 15, 1.3, 0, 0, 0, 25, 0, 0, 0, 1, 0]),
        .init(id: 12, contrastOffset: -0.05, matrixArray: [1.1, 0, 0, 0, 30, 1.2, 0, 0, 0, 27, 1.4, 0, 0, 0, 75, 0, 0, 0, 1, 0]),
        .init(id: 13, contrastOffset: 0.02, matrixArray: [1.0, 0, 0, 0, 30, 1.1, 0, 0, 0, 27, 1.5, 0, 0, 0, 75, 0, 0, 0, 1, 0]),
        .init(id: 14, contrastOffset: 0.08, matrixArray: [1.4, 0, 0, 0, 28, 1.1, 0, 0, 0, 25, 0.6, 0, 0, 0, 22, 0, 0, 0, 1, 0]),
        .init(id: 15, contrastOffset: -0.03, matrixArray: [0.5, 0, 0, 0, 2, 1.4, 0, 0, 0, 44, 1.1, 0, 0, 0, 34, 0, 0, 0, 1, 0]),
        // Pentatones (16 - 20)
        .init(id: 16, matrixArray: [1.6, 0, 0, 0, 26, 1.1, 0, 0, 0, 11, 1.3, 0, 0, 0, 46, 0, 0, 0, 1, 0]),
        .init(id: 17, matrixArray: [1.5, 0, 0, 0, 36, 1.2, 0, 0, 0, 0, 0.9, 0, 0, 0, 70, 0, 0, 0, 1, 0]),
        .init(id: 18, contrastOffset: 0.04, matrixArray: [0.7, 0, 0, 0, 6, 1.4, 0, 0, 0, 20, 0.9, 0, 0, 0, 13, 0, 0, 0, 1, 0]),
        .init(id: 19, contrastOffset: 0.12, matrixArray: [1.4, 0, 0, 0, 30, 0.9, 0, 0, 0, 17, 1.3, 0, 0, 0, 42, 0, 0, 0, 1, 0]),
        .init(id: 20, contrastOffset: -0.06, matrixArray: [1.1, 0, 0, 0, 30, 1.3, 0, 0, 0, 27, 1.4, 0, 0, 0, 75, 0, 0, 0, 1, 0]),
        // Hexatones (21 - 25)
        .init(id: 21, contrastOffset: -0.05, matrixArray: [0.7, 0, 0, 0, 3, 1.1, 0, 0, 0, 7, 1.5, 0, 0, 0, 24, 0, 0, 0, 1, 0]),
        .init(id: 22, contrastOffset: 0.15, matrixArray: [1.7, 0, 0, 0, 15, 1.1, 0, 0, 0, 5, 0.6, 0, 0, 0, 5, 0, 0, 0, 1, 0]),
        .init(id: 23, contrastOffset: 0.08, matrixArray: [1.5, 0, 0, 0, 30, 1.0, 0, 0, 0, 27, 0.8, 0, 0, 0, 75, 0, 0, 0, 1, 0]),
        .init(id: 24, contrastOffset: 0.03, matrixArray: [0.8, 0, 0, 0, 13, 1.4, 0, 0, 0, 19, 0.9, 0, 0, 0, 13, 0, 0, 0, 1, 0]),
        .init(id: 25, contrastOffset: 0.05, matrixArray: [1.5, 0, 0, 0, 24, 0.7, 0, 0, 0, 2, 1.3, 0, 0, 0, 44, 0, 0, 0, 1, 0]),
        // Heptatones (26 - 30)
        .init(id: 26, contrastOffset: 0.02, matrixArray: [1.2, 0, 0, 0, 11, 0.9, 0, 0, 0, 9, 1.5, 0, 0, 0, 26, 0, 0, 0, 1, 0]),
        .init(id: 27, contrastOffset: 0.14, matrixArray: [1.6, 0, 0, 0, 3, 1.3, 0, 0, 0, 7, 1.4, 0, 0, 0, 18, 0, 0, 0, 1, 0]),
        .init(id: 28, contrastOffset: 0.06, matrixArray: [1.4, 0, 0, 0, 28, 1.1, 0, 0, 0, 22, 0.7, 0, 0, 0, 14, 0, 0, 0, 1, 0]),
        .init(id: 29, contrastOffset: 0.04, matrixArray: [0.7, 0, 0, 0, 2, 1.4, 0, 0, 0, 44, 0.9, 0, 0, 0, 35, 0, 0, 0, 1, 0]),
        .init(id: 30, contrastOffset: 0.01, matrixArray: [1.1, 0, 0, 0, 23, 0.9, 0, 0, 0, 36, 1.4, 0, 0, 0, 84, 0, 0, 0, 1, 0]),
        // Octatones (31 - 35)
        .init(id: 31, contrastOffset: 0.15, matrixArray: [1.6, 0, 0, 0, 30, 1.3, 0, 0, 0, 5, 1.0, 0, 0, 0, 43, 0, 0, 0, 1, 0]),
        .init(id: 32, contrastOffset: 0.08, matrixArray: [1.4, 0, 0, 0, 9, 1.3, 0, 0, 0, 5, 1.5, 0, 0, 0, 20, 0, 0, 0, 1, 0]),
        .init(id: 33, contrastOffset: 0.05, matrixArray: [0.6, 0, 0, 0, 2, 1.5, 0, 0, 0, 44, 0.9, 0, 0, 0, 35, 0, 0, 0, 1, 0]),
        .init(id: 34, contrastOffset: -0.04, matrixArray: [1.2, 0, 0, 0, 31, 0.9, 0, 0, 0, 22, 1.4, 0, 0, 0, 75, 0, 0, 0, 1, 0]),
        .init(id: 35, contrastOffset: 0.02, matrixArray: [0.8, 0, 0, 0, 8, 1.2, 0, 0, 0, 20, 1.5, 0, 0, 0, 38, 0, 0, 0, 1, 0])
    ]
}

// MARK: - Engine

enum ColorFilterEngine {
    nonisolated(unsafe) private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Applies the given colour-filter settings to `image`.
    /// Returns the original image unchanged when settings are neutral or on failure.
    static func apply(_ image: UIImage, settings: ReaderColorFilterSettings) -> UIImage {
        guard !settings.isNeutral, let cgInput = image.cgImage else { return image }

        let matrix = settings.colorMatrix().values

        let ciInput = CIImage(cgImage: cgInput)
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        filter.setValue(ciInput, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: CGFloat(matrix[0]), y: CGFloat(matrix[5]), z: CGFloat(matrix[10]), w: CGFloat(matrix[15])), forKey: "inputRVector")
        filter.setValue(CIVector(x: CGFloat(matrix[1]), y: CGFloat(matrix[6]), z: CGFloat(matrix[11]), w: CGFloat(matrix[16])), forKey: "inputGVector")
        filter.setValue(CIVector(x: CGFloat(matrix[2]), y: CGFloat(matrix[7]), z: CGFloat(matrix[12]), w: CGFloat(matrix[17])), forKey: "inputBVector")
        filter.setValue(CIVector(x: CGFloat(matrix[3]), y: CGFloat(matrix[8]), z: CGFloat(matrix[13]), w: CGFloat(matrix[18])), forKey: "inputAVector")
        filter.setValue(
            CIVector(
                x: CGFloat(matrix[4]) / 255,
                y: CGFloat(matrix[9]) / 255,
                z: CGFloat(matrix[14]) / 255,
                w: CGFloat(matrix[19]) / 255
            ),
            forKey: "inputBiasVector"
        )

        guard
            let output = filter.outputImage,
            let cgOutput = ciContext.createCGImage(output, from: ciInput.extent)
        else {
            return image
        }

        return UIImage(cgImage: cgOutput, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - Nuke processor

struct ColorFilterProcessor: ImageProcessing {
    let settings: ReaderColorFilterSettings

    init(settings: ReaderColorFilterSettings = .current) {
        self.settings = settings
    }

    var identifier: String {
        "com.github.Aidoku/Aidoku/colorFilter?\(settings.cacheKey)"
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        guard !settings.isNeutral else { return image }
        return ColorFilterEngine.apply(image, settings: settings)
    }
}
