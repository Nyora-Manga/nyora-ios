//
//  SourceImageView.swift
//  Aidoku
//
//  Created by Skitty on 4/26/25.
//

import AidokuRunner
import NukeUI
import SwiftUI

/// Animated shimmer skeleton shown while a cover loads (opt-in, used by Discover).
struct ShimmerSkeleton: View {
    @State private var animating = false

    var body: some View {
        Color(uiColor: .secondarySystemFill)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, Color.white.opacity(0.28), .clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.7)
                    .offset(x: animating ? geo.size.width : -geo.size.width * 0.7)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    animating = true
                }
            }
    }
}

struct SourceImageView: View {
    var source: AidokuRunner.Source?
    /// Fallback source key. The source list loads asynchronously, so SwiftUI cover views that resolve
    /// `source` synchronously in `body` get `nil` on first render and the hotlink Referer is dropped
    /// (Nyora covers 403). Passing `sourceId` lets this view re-resolve the source AFTER the sources
    /// finish loading, so covers come up correctly without a race.
    var sourceId: String?

    let imageUrl: String
    var width: CGFloat?
    var height: CGFloat?
    var downsampleWidth: CGFloat?
    var contentMode: ContentMode = .fill
    var placeholder = "MangaPlaceholder"
    /// When true, shows an animated shimmer while loading instead of the static
    /// placeholder image — the "lazy loader" used by the Discover feed's covers.
    var showsLoadingIndicator = false

    @State private var imageRequest: ImageRequest?

    var body: some View {
        LazyImage(
            request: imageRequest,
            transaction: .init(animation: .default)
        ) { state in
            if state.imageContainer?.type == .gif, let data = state.imageContainer?.data {
                GIFImage(
                    data: data,
                    contentMode: contentMode
                )
                    .frame(width: width, height: height)
                    .id(state.image != nil ? imageUrl : "placeholder") // ensures only opacity is animated
            } else if showsLoadingIndicator && state.image == nil && state.error == nil {
                // still loading + caller opted in → shimmer skeleton
                ShimmerSkeleton()
                    .frame(width: width, height: height)
                    .id("loading")
            } else {
                let result = if let image = state.image {
                    image
                } else {
                    Image(placeholder)
                }
                result
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
                    .id(state.image != nil ? imageUrl : "placeholder") // ensures only opacity is animated
            }
        }
        .processors({
            if let downsampleWidth {
                [DownsampleProcessor(width: downsampleWidth)]
            } else {
                []
            }
        }())
        .onAppear {
            guard imageRequest == nil else { return }
            Task {
                await loadImageRequest(url: imageUrl)
            }
        }
        .onChange(of: imageUrl) { newValue in
            imageRequest = nil
            Task {
                await loadImageRequest(url: newValue)
            }
        }
    }

    func loadImageRequest(url: String) async {
        let url = URL(string: url)
        if let fileUrl = url?.toAidokuFileUrl() {
            imageRequest = ImageRequest(url: fileUrl)
            return
        }
        // Prefer an explicitly-passed source; otherwise resolve by id AFTER the source list loads so
        // the hotlink Referer is applied even on a cold-launch race (mirrors the UIKit cover cells).
        var resolvedSource = source
        if resolvedSource == nil, let sourceId, !sourceId.isEmpty {
            await SourceManager.shared.waitForSourcesLoad()
            resolvedSource = SourceManager.shared.source(for: sourceId)
        }
        guard let resolvedSource, let url, !url.isFileURL else {
            imageRequest = ImageRequest(url: url)
            return
        }
        imageRequest = ImageRequest(urlRequest: await resolvedSource.getModifiedImageRequest(url: url, context: nil))
    }
}
