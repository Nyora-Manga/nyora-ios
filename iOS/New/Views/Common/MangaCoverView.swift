//
//  MangaCoverView.swift
//  Aidoku
//
//  Created by Skitty on 9/8/23.
//

import AidokuRunner
import SwiftUI
import Nuke
import NukeUI

struct MangaCoverView: View {
    var source: AidokuRunner.Source?
    /// Fallback source key so the cover can re-resolve the source after the source list loads
    /// (see `SourceImageView.sourceId`) — avoids a cold-launch race dropping the hotlink Referer.
    var sourceId: String?

    let coverImage: String
    var width: CGFloat?
    var height: CGFloat?
    var downsampleWidth: CGFloat?
    var contentMode: ContentMode = .fill
    var placeholder = "MangaPlaceholder"
    var bookmarked: Bool = false

    var body: some View {
        SourceImageView(
            source: source,
            sourceId: sourceId,
            imageUrl: coverImage,
            width: width,
            height: height,
            downsampleWidth: downsampleWidth,
            contentMode: contentMode,
            placeholder: placeholder
        )
        .overlay(
            bookmarkView,
            alignment: .topTrailing
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color(UIColor.quaternarySystemFill), lineWidth: 1)
        )
    }

    @ViewBuilder
    var bookmarkView: some View {
        if bookmarked {
            Image("bookmark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.tint)
                .frame(width: 17, height: 27, alignment: .topTrailing)
                .padding(.trailing, 8)
        } else {
            EmptyView()
        }
    }
}
