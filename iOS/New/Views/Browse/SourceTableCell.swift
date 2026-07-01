//
//  SourceTableCell.swift
//  Aidoku
//
//  Created by Skitty on 8/18/23.
//

import SwiftUI
import AidokuRunner

struct SourceTableCell: View {
    let source: AidokuRunner.Source

    var body: some View {
        HStack(spacing: 12) {
            SourceIconView(sourceId: source.key, imageUrl: source.imageUrl)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(source.name)
                        .font(.poppins(16, weight: .semibold))
                    Text("v\(source.version)")
                        .font(.poppins(13))
                        .foregroundStyle(.secondary)

                    if source.contentRating != .safe {
                        let (text, background) = if source.contentRating == .containsNsfw {
                            ("17+", Color.orange.opacity(0.3))
                        } else {
                            ("18+", Color.red.opacity(0.3))
                        }

                        Text(text)
                            .foregroundStyle(.secondary)
                            .font(.poppins(10, weight: .medium))
                            .padding(.vertical, 3)
                            .padding(.horizontal, 5)
                            .background(background)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(.leading, 3)
                    }
                }
                Text(
                    (source.languages.count > 1 || source.languages.first == "multi")
                        ? NSLocalizedString("MULTI_LANGUAGE")
                        : Locale.current.localizedString(forIdentifier: source.languages[0]) ?? ""
                )
                .font(.poppins(13))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .nyoraTintedCard()
        .contentShape(Rectangle())
    }
}
