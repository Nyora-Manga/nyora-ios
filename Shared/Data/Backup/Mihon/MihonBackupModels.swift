//
//  MihonBackupModels.swift
//  Nyora
//
//  Wire-compatible mirror of Mihon's `.tachibk` schema.
//

import Foundation

// The field NUMBERS below are the contract with Mihon and with Nyora's JVM
// implementation (nyora-shared `MihonBackup.kt`) — not the property names.
// Two tags are permanently burned and must never be reused:
//   MihonBackup tag 100  — legacy 0.x source model
//   MihonManga  tag 102  — legacy 0.x history model

struct MihonBackup {
    var backupManga: [MihonManga] = []
    var backupCategories: [MihonCategory] = []
    var backupSources: [MihonSource] = []

    func encoded() -> Data {
        var w = ProtoWriter()
        w.write(field: 1, messages: backupManga.map { $0.encoded() })
        w.write(field: 2, messages: backupCategories.map { $0.encoded() })
        w.write(field: 101, messages: backupSources.map { $0.encoded() })
        return w.data
    }

    static func decode(_ data: Data) throws -> MihonBackup {
        var r = ProtoReader(data)
        var out = MihonBackup()
        while !r.isAtEnd {
            let (field, type) = try r.readTag()
            switch (field, type) {
            case (1, .lengthDelimited): out.backupManga.append(try MihonManga.decode(try r.readBytes()))
            case (2, .lengthDelimited): out.backupCategories.append(try MihonCategory.decode(try r.readBytes()))
            case (101, .lengthDelimited): out.backupSources.append(try MihonSource.decode(try r.readBytes()))
            default: try r.skip(type)   // preferences, extension stores, future fields
            }
        }
        return out
    }
}

struct MihonManga {
    var source: Int64 = 0
    var url: String = ""
    var title: String = ""
    var artist: String?
    var author: String?
    var desc: String?
    var genre: [String] = []
    var status: Int = 0
    var thumbnailUrl: String?
    var dateAdded: Int64 = 0
    var viewer: Int = 0
    var chapters: [MihonChapter] = []
    var categories: [Int64] = []
    var tracking: [MihonTracking] = []
    var favorite: Bool = true
    var chapterFlags: Int = 0
    var viewerFlags: Int = 0
    var history: [MihonHistory] = []
    var lastModifiedAt: Int64 = 0
    var excludedScanlators: [String] = []
    var version: Int64 = 0
    var notes: String = ""
    var initialized: Bool = false
    var memo: Data = MihonMemo.emptyBytes

    func encoded() -> Data {
        var w = ProtoWriter()
        w.write(field: 1, int64: source)
        w.write(field: 2, string: url)
        w.write(field: 3, string: title)
        w.write(field: 4, string: artist)
        w.write(field: 5, string: author)
        w.write(field: 6, string: desc)
        w.write(field: 7, strings: genre)
        w.write(field: 8, int32: status)
        w.write(field: 9, string: thumbnailUrl)
        w.write(field: 13, int64: dateAdded)
        w.write(field: 14, int32: viewer)
        w.write(field: 16, messages: chapters.map { $0.encoded() })
        w.write(field: 17, int64s: categories)
        w.write(field: 18, messages: tracking.map { $0.encoded() })
        w.write(field: 100, bool: favorite, default: true)   // schema default is true
        w.write(field: 101, int32: chapterFlags)
        w.write(field: 103, int32: viewerFlags)
        w.write(field: 104, messages: history.map { $0.encoded() })
        w.write(field: 106, int64: lastModifiedAt)
        w.write(field: 108, strings: excludedScanlators)
        w.write(field: 109, int64: version)
        w.write(field: 110, string: notes)
        w.write(field: 111, bool: initialized)
        if memo != MihonMemo.emptyBytes { w.write(field: 112, bytes: memo) }
        return w.data
    }

    static func decode(_ data: Data) throws -> MihonManga {
        var r = ProtoReader(data)
        var m = MihonManga()
        while !r.isAtEnd {
            let (field, type) = try r.readTag()
            switch (field, type) {
            case (1, .varint): m.source = try r.readInt64()
            case (2, .lengthDelimited): m.url = try r.readString()
            case (3, .lengthDelimited): m.title = try r.readString()
            case (4, .lengthDelimited): m.artist = try r.readString()
            case (5, .lengthDelimited): m.author = try r.readString()
            case (6, .lengthDelimited): m.desc = try r.readString()
            case (7, .lengthDelimited): m.genre.append(try r.readString())
            case (8, .varint): m.status = Int(try r.readInt64())
            case (9, .lengthDelimited): m.thumbnailUrl = try r.readString()
            case (13, .varint): m.dateAdded = try r.readInt64()
            case (14, .varint): m.viewer = Int(try r.readInt64())
            case (16, .lengthDelimited): m.chapters.append(try MihonChapter.decode(try r.readBytes()))
            case (17, .varint): m.categories.append(try r.readInt64())
            case (18, .lengthDelimited): m.tracking.append(try MihonTracking.decode(try r.readBytes()))
            case (100, .varint): m.favorite = try r.readBool()
            case (101, .varint): m.chapterFlags = Int(try r.readInt64())
            case (103, .varint): m.viewerFlags = Int(try r.readInt64())
            case (104, .lengthDelimited): m.history.append(try MihonHistory.decode(try r.readBytes()))
            case (106, .varint): m.lastModifiedAt = try r.readInt64()
            case (108, .lengthDelimited): m.excludedScanlators.append(try r.readString())
            case (109, .varint): m.version = try r.readInt64()
            case (110, .lengthDelimited): m.notes = try r.readString()
            case (111, .varint): m.initialized = try r.readBool()
            case (112, .lengthDelimited): m.memo = try r.readBytes()
            default: try r.skip(type)
            }
        }
        return m
    }
}

struct MihonChapter {
    var url: String = ""
    var name: String = ""
    var scanlator: String?
    var read: Bool = false
    var bookmark: Bool = false
    var lastPageRead: Int64 = 0
    var dateFetch: Int64 = 0
    var dateUpload: Int64 = 0
    var chapterNumber: Float = 0
    var sourceOrder: Int64 = 0
    var lastModifiedAt: Int64 = 0
    var version: Int64 = 0
    var memo: Data = MihonMemo.emptyBytes

    func encoded() -> Data {
        var w = ProtoWriter()
        w.write(field: 1, string: url)
        w.write(field: 2, string: name)
        w.write(field: 3, string: scanlator)
        w.write(field: 4, bool: read)
        w.write(field: 5, bool: bookmark)
        w.write(field: 6, int64: lastPageRead)
        w.write(field: 7, int64: dateFetch)
        w.write(field: 8, int64: dateUpload)
        w.write(field: 9, float: chapterNumber)
        w.write(field: 10, int64: sourceOrder)
        w.write(field: 11, int64: lastModifiedAt)
        w.write(field: 12, int64: version)
        if memo != MihonMemo.emptyBytes { w.write(field: 13, bytes: memo) }
        return w.data
    }

    static func decode(_ data: Data) throws -> MihonChapter {
        var r = ProtoReader(data)
        var c = MihonChapter()
        while !r.isAtEnd {
            let (field, type) = try r.readTag()
            switch (field, type) {
            case (1, .lengthDelimited): c.url = try r.readString()
            case (2, .lengthDelimited): c.name = try r.readString()
            case (3, .lengthDelimited): c.scanlator = try r.readString()
            case (4, .varint): c.read = try r.readBool()
            case (5, .varint): c.bookmark = try r.readBool()
            case (6, .varint): c.lastPageRead = try r.readInt64()
            case (7, .varint): c.dateFetch = try r.readInt64()
            case (8, .varint): c.dateUpload = try r.readInt64()
            case (9, .fixed32): c.chapterNumber = try r.readFloat()
            case (10, .varint): c.sourceOrder = try r.readInt64()
            case (11, .varint): c.lastModifiedAt = try r.readInt64()
            case (12, .varint): c.version = try r.readInt64()
            case (13, .lengthDelimited): c.memo = try r.readBytes()
            default: try r.skip(type)
            }
        }
        return c
    }
}

struct MihonCategory {
    var name: String = ""
    var order: Int64 = 0
    var id: Int64 = 0
    var flags: Int64 = 0

    func encoded() -> Data {
        var w = ProtoWriter()
        w.write(field: 1, string: name)
        w.write(field: 2, int64: order)
        w.write(field: 3, int64: id)
        w.write(field: 100, int64: flags)
        return w.data
    }

    static func decode(_ data: Data) throws -> MihonCategory {
        var r = ProtoReader(data)
        var c = MihonCategory()
        while !r.isAtEnd {
            let (field, type) = try r.readTag()
            switch (field, type) {
            case (1, .lengthDelimited): c.name = try r.readString()
            case (2, .varint): c.order = try r.readInt64()
            case (3, .varint): c.id = try r.readInt64()
            case (100, .varint): c.flags = try r.readInt64()
            default: try r.skip(type)
            }
        }
        return c
    }
}

struct MihonSource {
    var name: String = ""
    var sourceId: Int64 = 0

    func encoded() -> Data {
        var w = ProtoWriter()
        w.write(field: 1, string: name)
        w.write(field: 2, int64: sourceId)
        return w.data
    }

    static func decode(_ data: Data) throws -> MihonSource {
        var r = ProtoReader(data)
        var s = MihonSource()
        while !r.isAtEnd {
            let (field, type) = try r.readTag()
            switch (field, type) {
            case (1, .lengthDelimited): s.name = try r.readString()
            case (2, .varint): s.sourceId = try r.readInt64()
            default: try r.skip(type)
            }
        }
        return s
    }
}

struct MihonHistory {
    var url: String = ""
    var lastRead: Int64 = 0
    var readDuration: Int64 = 0

    func encoded() -> Data {
        var w = ProtoWriter()
        w.write(field: 1, string: url)
        w.write(field: 2, int64: lastRead)
        w.write(field: 3, int64: readDuration)
        return w.data
    }

    static func decode(_ data: Data) throws -> MihonHistory {
        var r = ProtoReader(data)
        var h = MihonHistory()
        while !r.isAtEnd {
            let (field, type) = try r.readTag()
            switch (field, type) {
            case (1, .lengthDelimited): h.url = try r.readString()
            case (2, .varint): h.lastRead = try r.readInt64()
            case (3, .varint): h.readDuration = try r.readInt64()
            default: try r.skip(type)
            }
        }
        return h
    }
}

struct MihonTracking {
    var syncId: Int = 0
    var libraryId: Int64 = 0
    var mediaIdInt: Int = 0
    var trackingUrl: String = ""
    var title: String = ""
    var lastChapterRead: Float = 0
    var totalChapters: Int = 0
    var score: Float = 0
    var status: Int = 0
    var startedReadingDate: Int64 = 0
    var finishedReadingDate: Int64 = 0
    var isPrivate: Bool = false
    var mediaId: Int64 = 0

    /// 1.x wrote the remote id into `mediaIdInt`; current builds use `mediaId`.
    var remoteId: Int64 { mediaIdInt != 0 ? Int64(mediaIdInt) : mediaId }

    func encoded() -> Data {
        var w = ProtoWriter()
        w.write(field: 1, int32: syncId)
        w.write(field: 2, int64: libraryId)
        w.write(field: 3, int32: mediaIdInt)
        w.write(field: 4, string: trackingUrl)
        w.write(field: 5, string: title)
        w.write(field: 6, float: lastChapterRead)
        w.write(field: 7, int32: totalChapters)
        w.write(field: 8, float: score)
        w.write(field: 9, int32: status)
        w.write(field: 10, int64: startedReadingDate)
        w.write(field: 11, int64: finishedReadingDate)
        w.write(field: 12, bool: isPrivate)
        w.write(field: 100, int64: mediaId)
        return w.data
    }

    static func decode(_ data: Data) throws -> MihonTracking {
        var r = ProtoReader(data)
        var t = MihonTracking()
        while !r.isAtEnd {
            let (field, type) = try r.readTag()
            switch (field, type) {
            case (1, .varint): t.syncId = Int(try r.readInt64())
            case (2, .varint): t.libraryId = try r.readInt64()
            case (3, .varint): t.mediaIdInt = Int(try r.readInt64())
            case (4, .lengthDelimited): t.trackingUrl = try r.readString()
            case (5, .lengthDelimited): t.title = try r.readString()
            case (6, .fixed32): t.lastChapterRead = try r.readFloat()
            case (7, .varint): t.totalChapters = Int(try r.readInt64())
            case (8, .fixed32): t.score = try r.readFloat()
            case (9, .varint): t.status = Int(try r.readInt64())
            case (10, .varint): t.startedReadingDate = try r.readInt64()
            case (11, .varint): t.finishedReadingDate = try r.readInt64()
            case (12, .varint): t.isPrivate = try r.readBool()
            case (100, .varint): t.mediaId = try r.readInt64()
            default: try r.skip(type)
            }
        }
        return t
    }
}
