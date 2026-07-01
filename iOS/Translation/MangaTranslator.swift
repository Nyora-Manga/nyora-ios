import Foundation
import CoreGraphics
import SwiftUI

/// Orchestrates the manga-translation pipeline, mirroring nyora-android's `MangaTranslator`:
/// OCR → merge blocks into bubbles → machine translation (Google) → Apple Intelligence
/// refine. Emits an `AsyncStream` of the page's blocks at each stage so the overlay updates
/// progressively (TRANSLATING → MT → REFINED).
actor MangaTranslator {
    private let ocr = OcrProvider()
    private let googleTranslate = GoogleTranslate()

    /// Stream the translation of one page.
    /// - useAppleIntelligence: run the on-device refine layer when available.
    nonisolated func translatePageStream(
        cgImage: CGImage,
        imageSize: CGSize,
        sourceLang: String,
        targetLang: String,
        useAppleIntelligence: Bool
    ) -> AsyncStream<[TranslatedBlock]> {
        AsyncStream { continuation in
            Task {
                let targetCode = TranslationConfig.googleLangCode(for: targetLang)

                // 1) OCR → bubbles
                let result = await ocr.runOcr(cgImage: cgImage, imageSize: imageSize, sourceLang: sourceLang)
                if result.isEmpty { continuation.finish(); return }
                let bubbles = mergeBlocksIntoBubbles(result.blocks)

                // 2) Initial blocks (TRANSLATING) with sampled bubble background colour
                var blocks: [TranslatedBlock] = bubbles.enumerated().map { idx, b in
                    TranslatedBlock(
                        id: "\(idx)",
                        originalText: b.text,
                        translatedText: b.text,
                        boundingBox: b.box,
                        state: .translating,
                        backgroundColor: sampleBgColor(cgImage: cgImage, box: b.box)
                    )
                }
                continuation.yield(blocks)

                // 3) Machine translation (fast layer)
                let originals = blocks.map(\.originalText)
                let mt = (try? await googleTranslate.translateBatch(originals, to: targetCode)) ?? originals
                for i in blocks.indices where i < mt.count {
                    blocks[i].translatedText = mt[i]
                    blocks[i].state = .mt
                }
                continuation.yield(blocks)

                // 4) Apple Intelligence refine (on-device polish)
                if useAppleIntelligence, await AppleIntelligenceRefiner.shared.isReady {
                    let polished = await AppleIntelligenceRefiner.shared.refine(
                        originals: originals, drafts: blocks.map(\.translatedText), targetLanguage: targetLang)
                    for i in blocks.indices where i < polished.count {
                        if !polished[i].isEmpty { blocks[i].translatedText = polished[i] }
                        blocks[i].state = .refined
                    }
                    continuation.yield(blocks)
                }
                continuation.finish()
            }
        }
    }

    // MARK: Bubble clustering (Enhanced with 8-direction ray casting)

    private struct MangaBubble { let text: String; let box: CGRect }

    private nonisolated func mergeBlocksIntoBubbles(_ blocks: [OcrProvider.MangaBlock]) -> [MangaBubble] {
        if blocks.isEmpty { return [] }
        
        let n = blocks.count
        var adj = Array(repeating: Set<Int>(), count: n)
        
        // Thresholds derived from average block dimensions
        let avgW = blocks.map { $0.boundingBox.width }.reduce(0, +) / CGFloat(n)
        let avgH = blocks.map { $0.boundingBox.height }.reduce(0, +) / CGFloat(n)
        let maxGap = max(avgW, avgH) * 1.5
        
        // 1) 8-Direction Ray Casting / Proximity Pass
        let centers = blocks.map { CGPoint(x: $0.boundingBox.midX, y: $0.boundingBox.midY) }
        
        for i in 0..<n {
            let a = blocks[i].boundingBox
            let centerA = centers[i]
            
            for j in (i+1)..<n {
                let b = blocks[j].boundingBox
                let centerB = centers[j]
                
                let dx = centerB.x - centerA.x
                let dy = centerB.y - centerA.y
                let dist = sqrt(dx*dx + dy*dy)
                
                if dist > maxGap * 2.0 { continue }
                if a.intersects(b) {
                    adj[i].insert(j); adj[j].insert(i)
                    continue
                }
                
                // Directional analysis
                let angle = atan2(dy, dx) // -pi to pi
                
                // Buckets for N, NE, E, SE, S, SW, W, NW
                // We check if the blocks are aligned along these axes and within a reasonable gap.
                let hOverlap = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
                let vOverlap = max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
                let minW = min(a.width, b.width)
                let minH = min(a.height, b.height)
                
                var connected = false
                
                // Vertical N/S: high horizontal overlap, reasonable vertical gap
                if hOverlap > minW * 0.4 {
                    let vGap = abs(dy) - (a.height + b.height) / 2
                    if vGap < maxGap { connected = true }
                }
                
                // Horizontal E/W: high vertical overlap, reasonable horizontal gap
                if !connected && vOverlap > minH * 0.4 {
                    let hGap = abs(dx) - (a.width + b.width) / 2
                    if hGap < maxGap { connected = true }
                }
                
                // Diagonal NE/SE/SW/NW: reasonable combined gap
                if !connected {
                    let hGap = abs(dx) - (a.width + b.width) / 2
                    let vGap = abs(dy) - (a.height + b.height) / 2
                    if hGap < maxGap * 0.5 && vGap < maxGap * 0.5 {
                        connected = true
                    }
                }

                if connected {
                    adj[i].insert(j); adj[j].insert(i)
                }
            }
        }
        
        // 2) Connected Components (Graph BFS)
        var components: [[Int]] = []
        var visited = Set<Int>()
        for i in 0..<n {
            if visited.contains(i) { continue }
            var component: [Int] = []
            var stack = [i]
            visited.insert(i)
            while !stack.isEmpty {
                let curr = stack.removeLast()
                component.append(curr)
                for neighbor in adj[curr] {
                    if !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        stack.append(neighbor)
                    }
                }
            }
            components.append(component)
        }
        
        // 3) Reconstruct Bubbles
        return components.map { indices in
            let cluster = indices.map { blocks[$0] }
            
            // Sort reading order based on dominant direction
            let box = cluster.reduce(cluster[0].boundingBox) { $0.union($1.boundingBox) }
            let isVertical = box.height > box.width * 1.2
            
            let sorted: [OcrProvider.MangaBlock]
            if isVertical {
                // Vertical Japanese: Right-to-left columns, Top-to-bottom rows
                sorted = cluster.sorted {
                    if abs($0.boundingBox.midX - $1.boundingBox.midX) > avgW * 0.5 {
                        return $0.boundingBox.midX > $1.boundingBox.midX // RTL
                    }
                    return $0.boundingBox.midY < $1.boundingBox.midY // TTB
                }
            } else {
                // Horizontal: Top-to-bottom, Left-to-right
                sorted = cluster.sorted {
                    if abs($0.boundingBox.midY - $1.boundingBox.midY) > avgH * 0.5 {
                        return $0.boundingBox.midY < $1.boundingBox.midY // TTB
                    }
                    return $0.boundingBox.midX < $1.boundingBox.midX // LTR
                }
            }
            
            return MangaBubble(text: sorted.map(\.text).joined(separator: " "), box: box)
        }
    }

    // MARK: Bubble background colour (brightest interior sample)

    private nonisolated func sampleBgColor(cgImage: CGImage, box: CGRect) -> Color {
        let w = cgImage.width, h = cgImage.height
        let xs = [box.minX + box.width * 0.25, box.midX, box.minX + box.width * 0.75]
        let ys = [box.minY + box.height * 0.25, box.midY, box.minY + box.height * 0.75]
        let points = xs.flatMap { x in ys.map { y in (Int(x), Int(y)) } }
            .filter { $0.0 >= 0 && $0.0 < w && $0.1 >= 0 && $0.1 < h }
        guard !points.isEmpty,
              let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return .white }
        let bpp = cgImage.bitsPerPixel / 8
        let bpr = cgImage.bytesPerRow
        let len = CFDataGetLength(data)
        var best: (Int, Color) = (-1, .white)
        for (x, y) in points {
            let offset = y * bpr + x * bpp
            guard offset + 2 < len else { continue }
            let r = Int(ptr[offset]), g = Int(ptr[offset + 1]), b = Int(ptr[offset + 2])
            let brightness = r + g + b
            if brightness > best.0 {
                best = (brightness, Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255))
            }
        }
        return best.1
    }
}
