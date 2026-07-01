# Nyora Unified Tracking Schema

Canonical cross-platform contract for tracking (scrobbler) records synced through
the self-hosted sync server (`nyora-sync-server`) and carried in backups.

All clients (iOS Aidoku, Android, and the JVM desktop apps mac/linux/windows via
`nyora-shared`) MUST serialize tracking records identically, using **snake_case**
keys, so that a record written by one platform round-trips losslessly through
another.

Server table: **`nyora_tracking`** (see `nyora-sync-server/app/models.py`,
`Tracking` model). The sync endpoint is generic over the `TABLES` registry, so no
endpoint changes are needed — clients just push/pull rows of this shape.

---

## 1. Canonical tracking record

| Field               | Type          | Notes |
|---------------------|---------------|-------|
| `tracker_id`        | str           | Normalized tracker/service identifier (see §3). |
| `remote_id`         | str           | The tracking entry id on the remote service (the media list entry / rate id, NOT the media id). |
| `source_id`         | str           | Nyora source id of the tracked manga. |
| `manga_id`          | str           | Source-scoped manga id. |
| `title`             | str           | Manga title (display cache). |
| `status`            | str           | Canonical status enum string (see §2). |
| `score`             | float         | Rating score. `0` / null means unscored. |
| `last_read_chapter` | float         | Latest read chapter number (fractional allowed). |
| `last_read_volume`  | int           | Latest read volume number. |
| `total_chapters`    | int           | Total chapters, if known (`0` = unknown). |
| `total_volumes`     | int           | Total volumes, if known (`0` = unknown). |
| `chapter_offset`    | int           | Offset added to local chapter number before scrobbling. |
| `started_at`        | str (ISO8601) | Date reading began. Empty string / null if unset. |
| `finished_at`       | str (ISO8601) | Date reading completed. Empty string / null if unset. |
| `comment`           | str           | Free-text note. |
| `updated_at`        | str (ISO8601) | Last-write timestamp. Used for last-writer-wins (LWW) merge. |
| `deleted_at`        | str (ISO8601) | Soft-delete tombstone. Null/empty = live row. |

Server primary key: `(user_id, manga_id, tracker_id)`. A row is uniquely a given
user's link between one manga and one tracking service.

### Merge / conflict resolution
- **LWW by `updated_at`**: on both push and pull, the record with the newer
  `updated_at` wins. Clients must set `updated_at` whenever any field changes.
- **Soft delete**: unlinking a tracker sets `deleted_at` rather than removing the
  row, so the tombstone propagates. A non-null `deleted_at` that is newer than the
  peer's `updated_at` removes the local link.

---

## 2. Status enum mapping

Canonical status strings (lowercase): `reading`, `planning`, `completed`,
`paused`, `dropped`, `rereading`.

| Canonical    | iOS `TrackStatus` (rawValue)        | Android `ScrobblingStatus` (name) |
|--------------|-------------------------------------|-----------------------------------|
| `reading`    | `.reading` (1)                      | `READING`                         |
| `planning`   | `.planning` (2)                     | `PLANNED`                         |
| `completed`  | `.completed` (3)                    | `COMPLETED`                       |
| `paused`     | `.paused` (4)                       | `ON_HOLD`                         |
| `dropped`    | `.dropped` (5)                      | `DROPPED`                         |
| `rereading`  | `.rereading` (6)                    | `RE_READING`                      |
| _(none)_     | `.none` (7)                         | — (row absent / `null` status)    |

Notes:
- iOS `TrackStatus` is an `Int`-wrapping struct (`Shared/Tracking/Models/TrackStatus.swift`);
  serialize by mapping rawValue → canonical string via the table above. `.none` (7)
  and any unknown value serialize to an empty string / no status.
- Android `ScrobblingStatus` (`scrobbling/common/domain/model/ScrobblingStatus.kt`)
  is stored as the enum **name** string in `ScrobblingEntity.status` (nullable).
  Enum order there is `PLANNED, READING, RE_READING, COMPLETED, ON_HOLD, DROPPED`
  — map by name, never by ordinal.

---

## 3. Tracker id normalization

Clients identify services differently; the canonical `tracker_id` is a **lowercase
string slug**.

| Canonical `tracker_id` | iOS `Tracker.id` (String) | Android `ScrobblerService` (Int id) |
|------------------------|---------------------------|-------------------------------------|
| `anilist`              | `"anilist"`               | `ANILIST` (2)                       |
| `myanimelist`          | `"myanimelist"`           | `MAL` (3)                           |
| `kitsu`                | `"kitsu"`                 | `KITSU` (4)                         |
| `shikimori`            | `"shikimori"`             | `SHIKIMORI` (1)                     |
| `bangumi`              | `"bangumi"`               | — (iOS only)                        |
| `komga`                | `"komga"`                 | — (iOS only)                        |
| `mangabaka`            | `"mangabaka"`             | — (iOS only)                        |

Notes:
- iOS already uses the canonical slug as its `Tracker.id` (e.g. `AniListTracker.id = "anilist"`,
  `MyAnimeListTracker.id = "myanimelist"`), so no transform is needed on iOS —
  emit `Tracker.id` directly as `tracker_id`.
- Android uses integer `ScrobblerService.id`; map int → slug via the table above
  when serializing, and slug → int (or drop unknown services) when deserializing.
- Trackers with no counterpart on a platform (e.g. `komga` on Android) are simply
  ignored by that platform on pull; they still round-trip through the server.

---

## 4. Per-platform field sources

### iOS (Aidoku)
The link lives in CoreData `TrackObject` and the live state is fetched from the
tracker service (`TrackState`).

| Canonical            | iOS source |
|----------------------|------------|
| `tracker_id`         | `TrackObject.trackerId` / `TrackItem.trackerId` |
| `remote_id`          | `TrackObject.id` / `TrackItem.id` |
| `source_id`          | `TrackObject.sourceId` |
| `manga_id`           | `TrackObject.mangaId` |
| `title`              | `TrackObject.title` |
| `chapter_offset`     | `TrackObject.chapterOffset` (Int) |
| `status`             | `TrackState.status` (`TrackStatus` → §2) |
| `score`              | `TrackState.score` (Int? → float) |
| `last_read_chapter`  | `TrackState.lastReadChapter` (Float?) |
| `last_read_volume`   | `TrackState.lastReadVolume` (Int?) |
| `total_chapters`     | `TrackState.totalChapters` (Int?) |
| `total_volumes`      | `TrackState.totalVolumes` (Int?) |
| `started_at`         | `TrackState.startReadDate` (Date → ISO8601) |
| `finished_at`        | `TrackState.finishReadDate` (Date → ISO8601) |

`TrackState` has no `comment`/`updated_at`/`deleted_at`; the sync client supplies
`updated_at` (now) and manages `deleted_at`, and `comment` maps to empty when
unavailable.

### Android
The link + state both live in Room `ScrobblingEntity` (table `scrobblings`).

| Canonical            | Android source (`ScrobblingEntity`) |
|----------------------|-------------------------------------|
| `tracker_id`         | `scrobbler` (Int → slug, §3) |
| `remote_id`          | `target_id` (Long → str) |
| `manga_id`           | `manga_id` |
| `source_id`          | — (derive from manga id / repository) |
| `status`             | `status` (enum name → §2) |
| `last_read_chapter`  | `chapter` (Int → float) |
| `score`              | `rating` (Float) |
| `comment`            | `comment` |
| _(entity `id`)_      | local surrogate id, not synced |

`ScrobblingEntity` has no volume/totals/dates/updated_at/deleted_at columns; those
fields serialize as their zero/empty defaults from Android until the entity is
extended. Clients merging Android rows must not clobber richer values from other
platforms with these zero defaults when Android's `updated_at` is older (LWW).

### Desktop (nyora-shared, JVM: mac/linux/windows)
Desktop is being built out (TS-008..TS-012); it will persist a local tracking
store keyed to this exact schema and sync it via `SupabaseSync` using the same
push/pull + LWW semantics.

---

## 5. Serialization rules (all clients)

1. Keys are snake_case exactly as in §1.
2. Missing optional strings serialize as `""` (empty), missing numerics as `0`.
3. Dates are ISO8601 (`yyyy-MM-dd'T'HH:mm:ssZ`). Empty string = unset.
4. `updated_at` is always set to the moment of the local change; never leave it
   empty on a live row.
5. `deleted_at` is set (not the row removed) on unlink; a live row keeps it empty.
6. Unknown `tracker_id` / `status` values are preserved verbatim on pass-through
   but ignored (not applied locally) by a platform that doesn't recognize them.
