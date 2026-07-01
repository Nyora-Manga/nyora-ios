//
//  NyoraRatingStore.swift
//  Aidoku
//
//  Side channel for a manga's numeric rating. The AidokuRunner.Manga model only
//  carries a content-rating enum (safe/suggestive/nsfw), not the normalized 0...1
//  quality rating the Nyora helper returns, so the runner stashes it here (keyed by
//  the manga's encoded key) when details load, and the details header reads it back
//  to render the rating value. Mirrors nyora-android's DetailsActivity
//  textViewRatingValue (rating * 5, one decimal) and nyora-mac's HelperManga.rating.
//

import Foundation

final class NyoraRatingStore: @unchecked Sendable {
    static let shared = NyoraRatingStore()

    private let lock = NSLock()
    private var storage: [String: Float] = [:]

    private init() {}

    /// Stores a normalized rating (0...1). Values outside that range are treated as unknown.
    func set(_ rating: Float?, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let rating, rating > 0, rating <= 1 {
            storage[key] = rating
        } else {
            storage[key] = nil
        }
    }

    /// Returns the normalized rating (0...1) if known, otherwise nil.
    func get(for key: String) -> Float? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }
}
