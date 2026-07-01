import SwiftUI
import UIKit

/// Draws translated bubbles over a manga page: pass 1 paints an opaque fill to erase the
/// original text, pass 2 draws the translated line. Maps image-pixel boxes into the
/// aspect-fit display rect. Ported from the macApp's `TranslationOverlayView` (AppKit→UIKit).
struct TranslationOverlayView: View {
    let blocks: [TranslatedBlock]
    let imageSize: CGSize
    let containerSize: CGSize

    private let coverExpand: CGFloat = 6
    private let textPad: CGFloat = 5
    private let minFont: CGFloat = 8
    private let maxFont: CGFloat = 38

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            // Pass 1 — erase original text
            ForEach(blocks) { block in
                if block.state != .translating {
                    let vr = coverRect(for: block.boundingBox)
                    block.backgroundColor
                        .frame(width: vr.width, height: vr.height)
                        .position(x: vr.midX, y: vr.midY)
                }
            }
            // Pass 2 — translated text
            ForEach(blocks) { block in
                if block.state != .translating, !block.translatedText.isEmpty {
                    let vr = coverRect(for: block.boundingBox)
                    let isDark = block.backgroundColor.luminance < 0.45
                    let fs = fitFontSize(text: block.translatedText, box: vr.insetBy(dx: textPad, dy: textPad))
                    Text(block.translatedText)
                        .font(.system(size: fs, weight: .medium, design: .rounded))
                        .foregroundStyle(isDark ? Color.white : Color.black)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .frame(width: vr.width - textPad * 2, height: vr.height - textPad * 2, alignment: .center)
                        .position(x: vr.midX, y: vr.midY)
                }
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .allowsHitTesting(false)
    }

    private var aspectFitTransform: (scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        guard imageSize.width > 0, imageSize.height > 0 else { return (1, 0, 0) }
        let s = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        return (s,
                (containerSize.width - imageSize.width * s) / 2,
                (containerSize.height - imageSize.height * s) / 2)
    }

    private func viewRect(for imgBox: CGRect) -> CGRect {
        let (s, dx, dy) = aspectFitTransform
        return CGRect(x: imgBox.minX * s + dx, y: imgBox.minY * s + dy,
                      width: imgBox.width * s, height: imgBox.height * s)
    }

    private func coverRect(for imgBox: CGRect) -> CGRect {
        viewRect(for: imgBox).insetBy(dx: -coverExpand, dy: -coverExpand)
    }

    private func fitFontSize(text: String, box: CGRect) -> CGFloat {
        guard box.width > 0, box.height > 0 else { return minFont }
        let base = min(max(box.height * 0.45, minFont), maxFont)
        for size in stride(from: base, through: minFont, by: -1) {
            if measureHeight(text, fontSize: size, maxWidth: box.width) <= box.height { return size }
        }
        return minFont
    }

    private func measureHeight(_ text: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let size = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        return (text as NSString).boundingRect(
            with: size, options: [.usesLineFragmentOrigin],
            attributes: [.font: font], context: nil).height
    }
}

extension Color {
    var luminance: Double {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Double(r) * 0.299 + Double(g) * 0.587 + Double(b) * 0.114
    }
}
