//
//  Chapter.swift
//  Aidoku
//
//  Created by Skitty on 12/22/21.
//

import Foundation
import AidokuRunner

class Chapter: Codable, Identifiable {

    let sourceId: String
    let id: String
    var mangaId: String
    var title: String?
    var scanlator: String?
    var url: String?
    var lang: String
    var chapterNum: Float?
    var volumeNum: Float?
    var dateUploaded: Date?
    var thumbnail: String?
    var locked: Bool = false
    var sourceOrder: Int

    init(
        sourceId: String,
        id: String,
        mangaId: String,
        title: String?,
        scanlator: String? = nil,
        url: String? = nil,
        lang: String = "en",
        chapterNum: Float? = nil,
        volumeNum: Float? = nil,
        dateUploaded: Date? = nil,
        thumbnail: String? = nil,
        locked: Bool = false,
        sourceOrder: Int
    ) {
        self.sourceId = sourceId
        self.id = id
        self.mangaId = mangaId
        self.title = title == "" ? nil : title
        self.scanlator = scanlator == "" ? nil : scanlator
        self.url = url == "" ? nil : url
        self.lang = lang
        self.chapterNum = chapterNum
        self.volumeNum = volumeNum
        self.dateUploaded = dateUploaded
        self.thumbnail = thumbnail
        self.locked = locked
        self.sourceOrder = sourceOrder
    }
}

extension Chapter: KVCObject {
    func valueByPropertyName(name: String) -> Any? {
        switch name {
            case "id": return id
            case "mangaId": return mangaId
            case "title": return title
            case "scanlator": return scanlator
            case "chapterNum": return chapterNum
            case "volumeNum": return volumeNum
            default: return nil
        }
    }
}

extension Chapter: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(sourceId)
        hasher.combine(mangaId)
        hasher.combine(id)
    }
}

extension Chapter: Equatable {
    static func == (lhs: Chapter, rhs: Chapter) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}

extension Chapter {
    func toNew() -> AidokuRunner.Chapter {
        let normalized = ChapterMetadataNormalizer.normalize(title: title, url: url, number: chapterNum)
        return AidokuRunner.Chapter(
            key: id,
            title: normalized.title,
            chapterNumber: normalized.number,
            volumeNumber: volumeNum,
            dateUploaded: dateUploaded,
            scanlators: scanlator?.components(separatedBy: ", "),
            url: url.flatMap({ URL(string: $0) }),
            language: lang,
            thumbnail: thumbnail,
            locked: locked
        )
    }

    /// Returns a formatted title for this chapter.
    /// `Vol.X Ch.X - Title`
    func makeTitle() -> String {
        if volumeNum == nil && title == nil, let chapterNum = chapterNum {
            // Chapter X
            return String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapterNum)
        } else {
            var components: [String] = []
            // Vol.X
            if let volumeNum = volumeNum {
                components.append(
                    String(format: NSLocalizedString("VOL_X", comment: ""), volumeNum)
                )
            }
            // Ch.X
            if let chapterNum = chapterNum {
                components.append(
                    String(format: NSLocalizedString("CH_X", comment: ""), chapterNum)
                )
            }
            // title
            if let title = title {
                if !components.isEmpty {
                    components.append("-")
                }
                components.append(title)
            }
            return components.joined(separator: " ")
        }
    }

    var mangaIdentifier: MangaIdentifier {
        .init(sourceKey: sourceId, mangaKey: mangaId)
    }

    var identifier: ChapterIdentifier {
        .init(sourceKey: sourceId, mangaKey: mangaId, chapterKey: id)
    }
}

private enum ChapterMetadataNormalizer {
    static func normalize(title: String?, url: String?, number: Float?) -> (title: String?, number: Float?) {
        let rawTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceNumber = number.flatMap { $0 > 0 ? $0 : nil }

        if let rawTitle,
           let duplicate = duplicateLeadingLabels(rawTitle) {
            return (emptyToNil(duplicate.cleanTitle), duplicate.number)
        }

        if let rawTitle,
           let leading = leadingLabel(rawTitle) {
            return (emptyToNil(leading.cleanTitle), leading.number ?? sourceNumber)
        }

        if let sourceNumber {
            return (emptyToNil(rawTitle), sourceNumber)
        }

        if let rawTitle,
           let parsed = firstChapterNumber(in: rawTitle) {
            return (emptyToNil(rawTitle), parsed)
        }

        if let url,
           let parsed = firstChapterNumber(in: url) {
            return (emptyToNil(rawTitle), parsed)
        }

        return (emptyToNil(rawTitle), sourceNumber)
    }

    private static func duplicateLeadingLabels(_ title: String) -> (number: Float, cleanTitle: String)? {
        let pattern = #"(?i)^\s*(?:chapter|chap|ch\.?|episode|ep\.?|c)\s*\d+(?:\.\d+)?\s*[-:–—]\s*(?:chapter|chap|ch\.?|episode|ep\.?|c)\s*(\d+(?:\.\d+)?)(?:\s*[-:–—]\s*(.*))?$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
            match.numberOfRanges > 1,
            let numberRange = Range(match.range(at: 1), in: title),
            let number = Float(title[numberRange])
        else { return nil }
        let rest = match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound
            ? Range(match.range(at: 2), in: title).map { String(title[$0]) }
            : nil
        return (number, rest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    private static func leadingLabel(_ title: String) -> (number: Float?, cleanTitle: String)? {
        let pattern = #"(?i)^\s*(?:chapter|chap|ch\.?|episode|ep\.?|c)\s*(\d+(?:\.\d+)?)(?:\s*[-:–—]\s*(.*))?$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
            match.numberOfRanges > 1
        else { return nil }
        let number = Range(match.range(at: 1), in: title).flatMap { Float(title[$0]) }
        let rest = match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound
            ? Range(match.range(at: 2), in: title).map { String(title[$0]) }
            : nil
        return (number, rest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    private static func firstChapterNumber(in text: String) -> Float? {
        let pattern = #"(?i)(?:chapter|chap|ch\.?|episode|ep\.?|c)[\s._:-]*(\d+(?:\.\d+)?)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Float(text[range])
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
