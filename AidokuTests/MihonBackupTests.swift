//
//  MihonBackupTests.swift
//  AidokuTests
//

import Foundation
import Testing

@testable import Aidoku

struct MihonBackupTests {

    private func sampleBackup() -> MihonBackup {
        MihonBackup(
            backupManga: [
                MihonManga(
                    source: 2_499_283_573_021_220_255,
                    url: "/manga/berserk",
                    title: "Berserk",
                    author: "Kentaro Miura",
                    genre: ["Action", "Dark Fantasy"],
                    status: 6,
                    thumbnailUrl: "https://example.invalid/b.jpg",
                    chapters: [
                        MihonChapter(
                            url: "/manga/berserk/1",
                            name: "Chapter 1",
                            read: true,
                            lastPageRead: 12,
                            chapterNumber: 1,
                            sourceOrder: 0
                        )
                    ],
                    categories: [0, 1],
                    tracking: [MihonTracking(syncId: 2, title: "Berserk", score: 9.5, status: 1, mediaId: 30002)],
                    favorite: true,
                    history: [MihonHistory(url: "/manga/berserk/1", lastRead: 1_700_000_000_000)]
                )
            ],
            backupCategories: [
                MihonCategory(name: "Reading", order: 0, id: 1),
                MihonCategory(name: "Read later", order: 1, id: 2),
            ],
            backupSources: [MihonSource(name: "MangaDex", sourceId: 2_499_283_573_021_220_255)]
        )
    }

    @Test func roundTripsThroughGzippedProtobuf() throws {
        let data = try MihonBackupCodec.encode(sampleBackup())

        // Mihon identifies its backups by the gzip magic bytes.
        #expect(data[data.startIndex] == 0x1f)
        #expect(data[data.startIndex + 1] == 0x8b)

        let decoded = try MihonBackupCodec.decode(data)
        #expect(decoded.backupManga.count == 1)
        let manga = try #require(decoded.backupManga.first)
        #expect(manga.title == "Berserk")
        #expect(manga.url == "/manga/berserk")
        #expect(manga.source == 2_499_283_573_021_220_255)
        #expect(manga.genre == ["Action", "Dark Fantasy"])
        #expect(manga.categories == [0, 1])
        #expect(manga.status == 6)
        #expect(manga.favorite)
        #expect(manga.chapters.count == 1)
        #expect(manga.chapters[0].lastPageRead == 12)
        #expect(manga.chapters[0].read)
        #expect(manga.chapters[0].chapterNumber == 1)
        #expect(manga.history.first?.lastRead == 1_700_000_000_000)
        #expect(manga.tracking.first?.syncId == 2)
        #expect(manga.tracking.first?.remoteId == 30002)
        #expect(manga.tracking.first?.score == 9.5)
        #expect(decoded.backupCategories.count == 2)
        #expect(decoded.backupSources.first?.name == "MangaDex")
    }

    @Test func favoriteFalseSurvivesTheDefaultTrueSchema() throws {
        // `favorite` defaults to TRUE in the schema, so a read-but-not-in-library
        // entry only round-trips if the writer emits the non-default value.
        var backup = sampleBackup()
        backup.backupManga[0].favorite = false
        let decoded = try MihonBackupCodec.decode(try MihonBackupCodec.encode(backup))
        #expect(decoded.backupManga[0].favorite == false)
    }

    @Test func acceptsBareUngzippedProtobufLikeMihonDoes() throws {
        let raw = sampleBackup().encoded()
        let decoded = try MihonBackupCodec.decode(raw)
        #expect(decoded.backupManga.first?.title == "Berserk")
    }

    @Test func rejectsOldFormatBackups() {
        #expect(throws: MihonBackupCodec.InvalidBackup.self) {
            try MihonBackupCodec.decode(Data(#"{"favourites":[]}"#.utf8))
        }
        #expect(throws: MihonBackupCodec.InvalidBackup.self) {
            try MihonBackupCodec.decode(Data("bplist00".utf8))
        }
        #expect(throws: MihonBackupCodec.InvalidBackup.self) {
            try MihonBackupCodec.decode(Data([0x1f]))
        }
        #expect(throws: MihonBackupCodec.InvalidBackup.self) {
            try MihonBackupCodec.decode(Data([0x1f, 0x8b, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]))
        }
    }

    @Test func rejectsAnOversizedLengthPrefixInsteadOfCrashing() {
        // A hand-crafted field-1 (backupManga) tag whose length-delimited size
        // is a 10-byte varint encoding 2^63 — one past Int64.max, and therefore
        // a value `Int(UInt64)` traps on rather than throws. A corrupt or
        // malicious .tachibk can put this in the length prefix; decoding must
        // surface the corrupt-backup error, not crash the app.
        let tag: UInt8 = 0x0A   // (field 1 << 3) | wireType 2 (lengthDelimited)
        let oversizedLength: [UInt8] = [0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01]
        let malformed = Data([tag] + oversizedLength)
        #expect(throws: MihonBackupCodec.InvalidBackup.self) {
            try MihonBackupCodec.decode(malformed)
        }
    }

    @Test func unknownFieldsFromANewerMihonAreSkipped() throws {
        // Append a field this build does not model (tag 999, varint) to a manga
        // message; decoding must ignore it rather than fail.
        var writer = ProtoWriter()
        writer.write(field: 1, int64: 42)
        writer.write(field: 2, string: "/u")
        writer.write(field: 3, string: "Title")
        writer.write(field: 999, int64: 12345)
        let manga = try MihonManga.decode(writer.data)
        #expect(manga.source == 42)
        #expect(manga.title == "Title")
    }

    @Test func gzipRoundTripsAndProducesARealContainer() throws {
        let payload = Data((0..<5000).map { UInt8($0 % 251) })
        let zipped = try MihonGzip.compress(payload)
        #expect(zipped[zipped.startIndex] == 0x1f)
        #expect(zipped[zipped.startIndex + 1] == 0x8b)
        #expect(zipped[zipped.startIndex + 2] == 0x08)   // DEFLATE
        #expect(try MihonGzip.decompress(zipped) == payload)
    }

    @Test func gzipCrcMatchesTheKnownIeeeValue() {
        // "123456789" -> 0xCBF43926 is the standard CRC-32 check value.
        #expect(MihonGzip.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func memoRoundTripsInsideTheMihonContainer() throws {
        var memo = NyoraMangaMemo()
        memo.nyoraId = "mangadex:abc"
        memo.sourceRef = "MANGADEX"
        memo.altTitles = ["ベルセルク"]
        memo.rating = 9.4
        var backup = sampleBackup()
        backup.backupManga[0].memo = MihonMemo.encode(memo)
        let decoded = try MihonBackupCodec.decode(try MihonBackupCodec.encode(backup))
        #expect(MihonMemo.manga(from: decoded.backupManga[0].memo) == memo)
    }

    @Test func foreignMemoDecodesToDefaults() {
        // Stock Mihon writes its own memo contents; we must not choke on them.
        #expect(MihonMemo.manga(from: Data(#"{"someMihonKey":123}"#.utf8)) == NyoraMangaMemo())
        #expect(MihonMemo.chapter(from: Data("not json".utf8)) == NyoraChapterMemo())
        #expect(MihonMemo.manga(from: nil) == NyoraMangaMemo())
    }

    // MARK: - Source bridge

    @Test func bridgeLoadsAndMatchesTheJvmResource() {
        #expect(MihonSourceBridge.size > 500)
        #expect(MihonSourceBridge.reverse.count > 300)
        #expect(MihonSourceBridge.map.values.allSatisfy { $0.hasPrefix("parser:") })
        #expect(MihonSourceBridge.map.keys.allSatisfy { $0 > 0 })
    }

    @Test func bridgeIsConsistentInBothDirections() {
        for (nyoraId, candidates) in MihonSourceBridge.reverse {
            for candidate in candidates {
                #expect(MihonSourceBridge.map[candidate.sourceId] == nyoraId)
            }
        }
    }

    @Test func translationPrefersALanguageMatch() throws {
        let entry = MihonSourceBridge.reverse.first { Set($0.value.map(\.lang)).count > 1 }
        guard let entry else { return }
        for lang in Set(entry.value.map(\.lang)) where !lang.isEmpty {
            #expect(MihonSourceBridge.mihonSource(for: entry.key, lang: lang)?.lang == lang)
        }
    }

    @Test func unknownSourcesReturnNilRatherThanGuessing() {
        #expect(MihonSourceBridge.nyoraSourceId(for: 1) == nil)
        #expect(MihonSourceBridge.mihonSource(for: "parser:DOES_NOT_EXIST") == nil)
        #expect(MihonSourceBridge.mihonSource(for: "") == nil)
    }

    // MARK: - Namespacing (shared with the JVM implementation)

    @Test func mihonRowSourceIdsSurviveTheSyncWireFormat() {
        // The sync layer re-adds a "parser:" prefix to any id without a colon, so
        // "MIHON_123" would come back as "parser:MIHON_123". "mihon:123" does not.
        func roundTrip(_ id: String) -> String {
            let wire = id.hasPrefix("parser:") ? String(id.dropFirst(7)) : id
            return wire.isEmpty || wire.contains(":") ? wire : "parser:\(wire)"
        }
        let id = MihonSourceIds.sourceId(123)
        #expect(id == "mihon:123")
        #expect(roundTrip(id) == id)
        #expect(roundTrip("MIHON_123") == "parser:MIHON_123")   // the shape that used to corrupt
        #expect(roundTrip("parser:MANGADEX") == "parser:MANGADEX")
        #expect(MihonSourceIds.mihonSourceId(from: id) == 123)
        #expect(MihonSourceIds.isUnresolved(id))
        #expect(!MihonSourceIds.isUnresolved("parser:MANGADEX"))
    }

    @Test func trackerStatusCodesAreMappedPerTracker() {
        // MyAnimeList uses 6/7 for plan/rereading; AniList and MangaBaka use 5/6.
        #expect(MihonTrackerCodec.nyoraStatus(syncId: 1, status: 6) == "planning")
        #expect(MihonTrackerCodec.nyoraStatus(syncId: 1, status: 7) == "rereading")
        #expect(MihonTrackerCodec.nyoraStatus(syncId: 2, status: 5) == "planning")
        #expect(MihonTrackerCodec.nyoraStatus(syncId: 2, status: 6) == "rereading")
        #expect(MihonTrackerCodec.mihonStatus(syncId: 1, status: "planning") == 6)
        #expect(MihonTrackerCodec.mihonStatus(syncId: 2, status: "planning") == 5)
        #expect(MihonTrackerCodec.mihonTrackerId(for: "anilist") == 2)
        #expect(MihonTrackerCodec.mihonTrackerId(for: "mangabaka") == 11)
        #expect(MihonTrackerCodec.mihonTrackerId(for: "kitsu") == nil)
        #expect(MihonTrackerCodec.nyoraTrackerId(for: 4) == nil)   // Shikimori
    }

    @Test func legacyTrackingRowsUsingMediaIdIntStillResolve() {
        #expect(MihonTracking(syncId: 2, mediaIdInt: 4242).remoteId == 4242)
        #expect(MihonTracking(syncId: 2, mediaId: 99).remoteId == 99)
    }

    @Test func cjkOnlySourceNamesDoNotCollide() {
        // Regression shared with the JVM mapper: normalising "性感美女" strips to
        // "" and would otherwise match any source.
        #expect(MihonBackupManager.matchByName("性感美女", installed: ["mangadex", "sodsaime"]) == nil)
        #expect(MihonBackupManager.matchByName("", installed: ["mangadex"]) == nil)
        #expect(MihonBackupManager.matchByName("mangadex", installed: ["mangadex"]) == "mangadex")
    }

    @Test func syntheticSourceIdsAreStableAndPositive() {
        let a = MihonBackupConverter.syntheticSourceId("parser:MANGADEX")
        #expect(a == MihonBackupConverter.syntheticSourceId("parser:MANGADEX"))
        #expect(a > 0)
        #expect(a != MihonBackupConverter.syntheticSourceId("parser:OTHER"))
    }
}
