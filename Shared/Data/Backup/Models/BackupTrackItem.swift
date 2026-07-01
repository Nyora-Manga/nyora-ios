//
//  BackupTrackItem.swift
//  Aidoku
//
//  Created by Skitty on 7/21/22.
//

import CoreData

struct BackupTrackItem: Codable, Hashable {
    var id: String
    var trackerId: String
    var mangaId: String
    var sourceId: String
    var title: String?
    var chapterOffset: Int?

    // Canonical tracking state (see NYORA_TRACKING_SCHEMA.md). All optional so older
    // backups (which only carried the link) still decode cleanly.
    var status: Int?          // TrackStatus.rawValue
    var score: Int?
    var lastReadChapter: Float?
    var lastReadVolume: Int?
    var totalChapters: Int?
    var totalVolumes: Int?
    var startedAt: Date?
    var finishedAt: Date?

    init(trackObject: TrackObject, state: TrackState? = nil) {
        id = trackObject.id ?? ""
        trackerId = trackObject.trackerId ?? ""
        mangaId = trackObject.mangaId ?? ""
        sourceId = trackObject.sourceId ?? ""
        title = trackObject.title
        chapterOffset = Int(trackObject.chapterOffset)
        if let state {
            status = state.status?.rawValue
            score = state.score
            lastReadChapter = state.lastReadChapter
            lastReadVolume = state.lastReadVolume
            totalChapters = state.totalChapters
            totalVolumes = state.totalVolumes
            startedAt = state.startReadDate
            finishedAt = state.finishReadDate
        }
    }

    func toObject(context: NSManagedObjectContext? = nil) -> TrackObject {
        let obj: TrackObject
        if let context = context {
            obj = TrackObject(context: context)
        } else {
            obj = TrackObject()
        }
        obj.id = id
        obj.trackerId = trackerId
        obj.mangaId = mangaId
        obj.sourceId = sourceId
        obj.title = title
        obj.chapterOffset = Int16(chapterOffset ?? 0)
        return obj
    }

    /// The canonical tracking state captured in this backup, if any state fields are present.
    var trackState: TrackState? {
        guard
            status != nil || score != nil || lastReadChapter != nil || lastReadVolume != nil
                || totalChapters != nil || totalVolumes != nil || startedAt != nil || finishedAt != nil
        else { return nil }
        return TrackState(
            score: score,
            status: status.map { TrackStatus($0) },
            lastReadChapter: lastReadChapter,
            lastReadVolume: lastReadVolume,
            totalChapters: totalChapters,
            totalVolumes: totalVolumes,
            startReadDate: startedAt,
            finishReadDate: finishedAt
        )
    }

    /// A `TrackUpdate` reconstructed from the backed-up state, used to write the state back
    /// to a tracker service on restore so the restore feeds sync.
    var trackUpdate: TrackUpdate? {
        guard let state = trackState else { return nil }
        return TrackUpdate(
            score: state.score,
            status: state.status,
            lastReadChapter: state.lastReadChapter,
            lastReadVolume: state.lastReadVolume,
            startReadDate: state.startReadDate,
            finishReadDate: state.finishReadDate
        )
    }
}
