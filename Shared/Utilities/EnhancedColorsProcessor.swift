//
//  EnhancedColorsProcessor.swift
//  Aidoku
//
//  Port of nyora-android `enhanced_colors` (32-bit color mode).
//

import Foundation
import Nuke
import CoreGraphics

#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Re-renders reader pages at full-depth (16 bits-per-component) color to reduce
/// banding, mirroring nyora-android's `enhanced_colors` toggle which swaps the
/// decode bitmap config between `RGB_565` (16-bit, default) and `ARGB_8888`
/// (32-bit, enhanced). iOS decodes at 8-bit ARGB by default; enabling this
/// promotes the final page bitmap to a deep-color (64bpp) buffer so gradients on
/// capable sources band less, at the cost of extra memory/CPU. No-op-safe: if the
/// deep-color context can't be created it returns the original image unchanged.
struct EnhancedColorsProcessor: ImageProcessing {
    var identifier: String {
        "com.github.Aidoku/Aidoku/enhancedColors"
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        Self.apply(image)
    }

    /// Redraws the image into a 16-bits-per-component RGBA bitmap. Returns the
    /// original image if the source has no backing `CGImage` or the deep-color
    /// context can't be allocated.
    static func apply(_ image: PlatformImage) -> PlatformImage? {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return image }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitsPerComponent = 16
        let bytesPerRow = width * 8 // 4 components * 2 bytes each
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let output = context.makeImage() else { return image }

#if os(iOS) || os(tvOS)
        return PlatformImage(cgImage: output, scale: image.scale, orientation: image.imageOrientation)
#else
        return PlatformImage(cgImage: output, size: image.size)
#endif
    }
}
