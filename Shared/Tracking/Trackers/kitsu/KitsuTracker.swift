//
//  KitsuTracker.swift
//  Aidoku
//
//  Kitsu tracker for Aidoku (username/password OAuth password grant).
//

import AidokuRunner
import Foundation

final class KitsuTracker: Tracker, UsernamePasswordTracker {
    let id = "kitsu"
    let name = "Kitsu"
    let icon = PlatformImage(named: "kitsu")

    let api = KitsuApi()

    var isLoggedIn: Bool {
        api.accessToken != nil
    }

    func login(username: String, password: String) async -> Bool {
        await api.authenticate(username: username, password: password)
    }

    func logout() async {
        await api.logout()
    }

    func getTrackerInfo() async -> TrackerInfo {
        .init(
            supportedStatuses: [.reading, .planning, .completed, .paused, .dropped],
            scoreType: .tenPoint
        )
    }

    func register(trackId: String, highestChapterRead: Float?, earliestReadDate: Date?) async throws -> String? {
        // trackId is the Kitsu manga id
        let existing = await api.findLibraryEntry(mangaId: trackId)
        if existing == nil {
            let status = highestChapterRead != nil ? "current" : "planned"
            let progress = Int(highestChapterRead ?? 0)
            await api.createLibraryEntry(mangaId: trackId, status: status, progress: progress)
        }
        return nil
    }

    func update(trackId: String, update: TrackUpdate) async throws {
        var entry = await api.findLibraryEntry(mangaId: trackId)
        if entry == nil {
            let status = update.status.map(statusToString) ?? "current"
            let progress = update.lastReadChapter.map { Int($0) } ?? 0
            await api.createLibraryEntry(mangaId: trackId, status: status, progress: progress)
            entry = await api.findLibraryEntry(mangaId: trackId)
        }
        guard let entryId = entry?.id else { return }
        await applyUpdate(entryId: entryId, update: update)
    }

    private func applyUpdate(entryId: String, update: TrackUpdate) async {
        var attributes: [String: Any] = [:]
        if let status = update.status {
            attributes["status"] = statusToString(status)
        }
        if let chapter = update.lastReadChapter {
            attributes["progress"] = Int(chapter)
        }
        if let volume = update.lastReadVolume {
            attributes["volumesOwned"] = volume
        }
        if let score = update.score {
            // Aidoku score is 1-10; Kitsu ratingTwenty is 2-20
            attributes["ratingTwenty"] = min(max(score * 2, 2), 20)
        }
        if let start = update.startReadDate {
            attributes["startedAt"] = Self.dateFormatter.string(from: start)
        }
        if let finish = update.finishReadDate {
            attributes["finishedAt"] = Self.dateFormatter.string(from: finish)
        }
        guard !attributes.isEmpty else { return }
        await api.updateLibraryEntry(entryId: entryId, attributes: attributes)
    }

    func getState(trackId: String) async throws -> TrackState {
        let manga = await api.getManga(id: trackId)
        let entry = await api.findLibraryEntry(mangaId: trackId)
        let score: Int? = entry?.attributes.ratingTwenty.map { $0 / 2 }
        return TrackState(
            score: score,
            status: statusFromString(entry?.attributes.status),
            lastReadChapter: entry?.attributes.progress.map { Float($0) },
            lastReadVolume: entry?.attributes.volumesOwned,
            totalChapters: manga?.attributes.chapterCount,
            totalVolumes: manga?.attributes.volumeCount,
            startReadDate: parseDate(entry?.attributes.startedAt),
            finishReadDate: parseDate(entry?.attributes.finishedAt)
        )
    }

    func getUrl(trackId: String) async -> URL? {
        if let manga = await api.getManga(id: trackId), let slug = manga.attributes.slug {
            return URL(string: "\(KitsuApi.baseUrl)/manga/\(slug)")
        }
        return URL(string: "\(KitsuApi.baseUrl)/manga/\(trackId)")
    }

    func search(for manga: AidokuRunner.Manga, includeNsfw: Bool) async throws -> [TrackSearchItem] {
        try await search(title: manga.title, includeNsfw: includeNsfw)
    }

    func search(title: String, includeNsfw: Bool) async throws -> [TrackSearchItem] {
        let results = await api.search(query: title)
        return results.map { resource in
            let attrs = resource.attributes
            return TrackSearchItem(
                id: resource.id,
                title: attrs.canonicalTitle,
                coverUrl: attrs.posterImage?.small ?? attrs.posterImage?.medium ?? attrs.posterImage?.original,
                description: attrs.synopsis,
                status: publishingStatus(attrs.status),
                type: mediaType(attrs.subtype),
                tracked: false
            )
        }
    }
}

private extension KitsuTracker {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) {
            return date
        }
        return Self.dateFormatter.date(from: string)
    }

    func statusToString(_ status: TrackStatus) -> String {
        switch status {
            case .reading, .rereading: return "current"
            case .planning: return "planned"
            case .completed: return "completed"
            case .paused: return "on_hold"
            case .dropped: return "dropped"
            default: return "current"
        }
    }

    func statusFromString(_ string: String?) -> TrackStatus {
        switch string {
            case "current": return .reading
            case "planned": return .planning
            case "completed": return .completed
            case "on_hold": return .paused
            case "dropped": return .dropped
            default: return .none
        }
    }

    func publishingStatus(_ string: String?) -> PublishingStatus {
        switch string {
            case "finished": return .completed
            case "current": return .ongoing
            case "tba", "unreleased", "upcoming": return .notPublished
            default: return .unknown
        }
    }

    func mediaType(_ string: String?) -> MediaType {
        switch string {
            case "manga": return .manga
            case "manhwa": return .manhwa
            case "manhua": return .manhua
            case "novel": return .novel
            case "oneshot": return .oneShot
            case "oel": return .oel
            default: return .unknown
        }
    }
}
