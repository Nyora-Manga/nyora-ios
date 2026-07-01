//
//  ChapterTableCell.swift
//  Aidoku
//
//  Created by Skitty on 8/17/23.
//

import AidokuRunner
import SwiftUI

struct ChapterTableCell: View {
    let source: AidokuRunner.Source?
    let sourceKey: String
    let chapter: AidokuRunner.Chapter
    let read: Bool
    let page: Int?
    let downloadStatus: DownloadStatus
    var downloadProgress: Float?
    let displayMode: ChapterTitleDisplayMode

    var downloaded: Bool {
        downloadStatus == .finished
    }

    var locked: Bool {
        chapter.locked && !downloaded
    }

    var progress: Float? {
        downloadProgress ?? (downloadStatus == .queued || downloadStatus == .downloading ? 0 : nil)
    }

    // nyora-android item_chapter.xml: each chapter row is its own outlined card
    // (16pt corners, 1px indigo-tint outline, flat — no fill/elevation) with
    // Poppins title + subtitle.
    private let cardCorner: CGFloat = 16

    var body: some View {
        let content = HStack {
            if let thumbnail = chapter.thumbnail {
                MangaCoverView(
                    source: source,
                    coverImage: thumbnail,
                    width: 40,
                    height: 40
                )
            }

            VStack(alignment: .leading, spacing: 8 / 3) {
                let title = chapter.formattedTitle(forceMode: displayMode)
                Text(title)
                    .foregroundStyle(locked || read ? .secondary : .primary)
                    .font(.poppins(15, weight: .semibold))
                    .lineLimit(1)
                if let subtitle = chapter.formattedSubtitle(page: page, sourceKey: sourceKey) {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .font(.poppins(13))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if downloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            } else if let progress {
                DownloadProgressView(progress: progress)
                    .frame(width: 13, height: 13)
            } else if locked {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        content
            .overlay(
                RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                    .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
    }
}

private struct DownloadProgressView: UIViewRepresentable {
    var progress: Float

    func makeUIView(context: Context) -> CircularProgressView {
        let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 13, height: 13))
        progressView.radius = 13 / 2
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = progressView.tintColor
        return progressView
    }

    func updateUIView(_ uiView: CircularProgressView, context: Context) {
        uiView.setProgress(value: progress, withAnimation: false)
    }
}
