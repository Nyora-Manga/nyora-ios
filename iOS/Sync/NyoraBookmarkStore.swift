//
//  NyoraBookmarkStore.swift
//  Aidoku (iOS) — Nyora fork
//
//  Page bookmarks — a saved reader page (manga + chapter + page), matching nyora-android's
//  Bookmark feature and nyora-web's `nyora_bookmark` table. Persisted locally as JSON in
//  UserDefaults (small data, no CoreData migration) and synced via NyoraSyncClient.
//

import Foundation

/// A saved reader page. `id` is the stable local key (source+manga+chapter+page).
struct NyoraBookmark: Codable, Identifiable, Hashable, Sendable {
    let sourceId: String        // Aidoku source key (e.g. "nyora.mangadex")
    let mangaId: String         // manga.key
    let mangaTitle: String
    let mangaCover: String?
    let chapterId: String       // chapter.key
    let chapterTitle: String?
    let page: Int               // 1-based page number
    var note: String?
    let imageUrl: String?
    let createdAt: Date

    var id: String { "\(sourceId)\u{1}\(mangaId)\u{1}\(chapterId)\u{1}\(page)" }

    /// Grouping key — one section per manga in the bookmarks list.
    var mangaKey: String { "\(sourceId)\u{1}\(mangaId)" }
}

extension Notification.Name {
    /// Posted whenever the bookmark set changes (add / remove / sync merge).
    static let nyoraBookmarksChanged = Notification.Name("Nyora.bookmarksChanged")
}

@MainActor
final class NyoraBookmarkStore: ObservableObject {
    static let shared = NyoraBookmarkStore()

    @Published private(set) var bookmarks: [NyoraBookmark] = []

    private let key = "Nyora.bookmarks.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([NyoraBookmark].self, from: data) {
            bookmarks = decoded
        }
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(bookmarks), forKey: key)
        NotificationCenter.default.post(name: .nyoraBookmarksChanged, object: nil)
    }

    func isBookmarked(sourceId: String, mangaId: String, chapterId: String, page: Int) -> Bool {
        bookmarks.contains {
            $0.sourceId == sourceId && $0.mangaId == mangaId && $0.chapterId == chapterId && $0.page == page
        }
    }

    /// Toggle a bookmark; returns the new state (true = now bookmarked).
    @discardableResult
    func toggle(_ bookmark: NyoraBookmark) -> Bool {
        if let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks.remove(at: idx)
            persist()
            return false
        }
        bookmarks.insert(bookmark, at: 0)
        persist()
        return true
    }

    func remove(_ bookmark: NyoraBookmark) {
        guard bookmarks.contains(where: { $0.id == bookmark.id }) else { return }
        bookmarks.removeAll { $0.id == bookmark.id }
        persist()
    }

    /// Bookmarks grouped by manga, most-recent manga first, pages ascending within a manga.
    var grouped: [(key: String, title: String, cover: String?, sourceId: String, mangaId: String, items: [NyoraBookmark])] {
        var order: [String] = []
        var byManga: [String: [NyoraBookmark]] = [:]
        for bm in bookmarks {
            if byManga[bm.mangaKey] == nil { order.append(bm.mangaKey) }
            byManga[bm.mangaKey, default: []].append(bm)
        }
        return order.compactMap { mangaKey in
            guard let items = byManga[mangaKey], let first = items.first else { return nil }
            let sorted = items.sorted {
                $0.chapterId == $1.chapterId ? $0.page < $1.page : $0.createdAt > $1.createdAt
            }
            return (mangaKey, first.mangaTitle, first.mangaCover, first.sourceId, first.mangaId, sorted)
        }
    }

    // MARK: - Sync hooks (used by NyoraSyncClient)

    /// Insert or update a bookmark without emitting a change per-item (caller persists once).
    func mergeIn(_ items: [NyoraBookmark]) {
        var map = Dictionary(bookmarks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for item in items { map[item.id] = item }
        bookmarks = Array(map.values).sorted { $0.createdAt > $1.createdAt }
        persist()
    }

    func removeIDs(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let before = bookmarks.count
        bookmarks.removeAll { ids.contains($0.id) }
        if bookmarks.count != before { persist() }
    }
}
