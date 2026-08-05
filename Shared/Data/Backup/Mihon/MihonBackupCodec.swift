//
//  MihonBackupCodec.swift
//  Nyora
//

import Foundation

/// Reads and writes Mihon `.tachibk` files: protobuf, gzipped.
///
/// Byte sniffing mirrors Mihon's own `BackupDecoder` (and Nyora's JVM codec) so
/// we accept every file Mihon does — gzipped or bare protobuf — and reject
/// legacy JSON/plist backups with a message that says what actually went wrong.
enum MihonBackupCodec {

    enum InvalidBackup: LocalizedError {
        case json, plist, truncated, corrupt, notMihon, empty

        var errorDescription: String? {
            switch self {
            case .json, .plist:
                return NSLocalizedString(
                    "This is an old-format backup. Nyora now uses the Mihon .tachibk format — "
                        + "re-export from the app that produced this file.",
                    comment: ""
                )
            case .truncated: return NSLocalizedString("Backup file is empty or truncated", comment: "")
            case .corrupt: return NSLocalizedString("Backup file is corrupt", comment: "")
            case .notMihon: return NSLocalizedString("Not a valid Mihon backup file", comment: "")
            case .empty: return NSLocalizedString("Refusing to write an empty backup", comment: "")
            }
        }
    }

    static func encode(_ backup: MihonBackup) throws -> Data {
        let raw = backup.encoded()
        guard !raw.isEmpty else { throw InvalidBackup.empty }
        return try MihonGzip.compress(raw)
    }

    static func decode(_ data: Data) throws -> MihonBackup {
        guard data.count >= 2 else { throw InvalidBackup.truncated }
        let b0 = data[data.startIndex], b1 = data[data.startIndex + 1]

        if b0 == 0x1f && b1 == 0x8b {
            let raw: Data
            do { raw = try MihonGzip.decompress(data) } catch { throw InvalidBackup.corrupt }
            return try decodeProto(raw)
        }
        // '{}' '{"' '{\n' — a JSON backup (Tachiyomi 0.x or old Nyora v2).
        if b0 == 0x7b { throw InvalidBackup.json }
        // "bplist" — Aidoku's old property-list backup.
        if b0 == 0x62 && b1 == 0x70 { throw InvalidBackup.plist }
        // Mihon tolerates a bare, ungzipped protobuf payload; so do we.
        return try decodeProto(data)
    }

    private static func decodeProto(_ raw: Data) throws -> MihonBackup {
        do {
            return try MihonBackup.decode(raw)
        } catch {
            throw InvalidBackup.notMihon
        }
    }

    /// Re-decodes freshly written bytes to prove the file we hand the user is
    /// readable, exactly as Mihon does before reporting a backup complete.
    @discardableResult
    static func verify(_ data: Data) throws -> MihonBackup { try decode(data) }
}
