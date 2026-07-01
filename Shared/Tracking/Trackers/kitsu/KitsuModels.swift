//
//  KitsuModels.swift
//  Aidoku
//
//  JSON:API response models for the Kitsu tracker.
//

import Foundation

/// A JSON:API top-level document wrapping a `data` member.
struct KitsuDataResponse<T: Decodable>: Decodable {
    let data: T
}

/// A JSON:API resource object with a string id and typed attributes.
struct KitsuResource<A: Decodable>: Decodable {
    let id: String
    let attributes: A
}

struct KitsuUserAttributes: Decodable {
    let name: String?
}

struct KitsuImage: Decodable {
    let tiny: String?
    let small: String?
    let medium: String?
    let large: String?
    let original: String?
}

struct KitsuMangaAttributes: Decodable {
    let canonicalTitle: String?
    let slug: String?
    let synopsis: String?
    let posterImage: KitsuImage?
    let chapterCount: Int?
    let volumeCount: Int?
    let status: String?
    let subtype: String?
    let averageRating: String?
}

struct KitsuLibraryAttributes: Decodable {
    let status: String?
    let progress: Int?
    let volumesOwned: Int?
    let ratingTwenty: Int?
    let startedAt: String?
    let finishedAt: String?
}
