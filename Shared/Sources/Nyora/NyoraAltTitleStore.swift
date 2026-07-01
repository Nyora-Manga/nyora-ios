//
//  NyoraAltTitleStore.swift
//  Aidoku
//
//  Side channel for a manga's alternate/localized titles. The AidokuRunner.Manga
//  model has no `altTitles` field, so the Nyora runner stashes them here (keyed by
//  the manga's encoded key) when details load, and the details header reads them
//  back to render the subtitle. Mirrors nyora-android's DetailsActivity subtitle
//  and nyora-mac's HelperManga.altTitles.
//

import Foundation

final class NyoraAltTitleStore: @unchecked Sendable {
    static let shared = NyoraAltTitleStore()

    private let lock = NSLock()
    private var storage: [String: [String]] = [:]

    private init() {}

    func set(_ titles: [String], for key: String) {
        lock.lock()
        defer { lock.unlock() }
        let cleaned = titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if cleaned.isEmpty {
            storage[key] = nil
        } else {
            storage[key] = cleaned
        }
    }

    func get(for key: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage[key] ?? []
    }
}
