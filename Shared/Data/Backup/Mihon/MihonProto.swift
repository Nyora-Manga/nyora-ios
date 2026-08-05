//
//  MihonProto.swift
//  Nyora
//
//  Minimal protobuf wire codec for Mihon `.tachibk` backups.
//

import Foundation

/// Protobuf wire types used by the Mihon backup schema.
enum ProtoWireType: Int {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

/// Writes protobuf wire format.
///
/// The Mihon schema only needs varints, length-delimited fields and fixed32
/// floats, so this is deliberately a few hundred bytes of logic rather than a
/// SwiftProtobuf dependency plus generated code — and it keeps the field numbers
/// visible next to the model, which is the part that must not drift.
///
/// Defaults are never written, matching `ProtoBuf { }` on the Kotlin side: proto
/// has no wire representation for an explicit null, and Mihon omits unset fields.
struct ProtoWriter {
    private(set) var data = Data()

    mutating func writeVarint(_ value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7f)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            data.append(byte)
        } while v != 0
    }

    private mutating func writeTag(_ field: Int, _ type: ProtoWireType) {
        writeVarint(UInt64(field << 3 | type.rawValue))
    }

    /// Protobuf encodes negative ints as 10-byte varints (two's complement).
    mutating func write(field: Int, int64 value: Int64, skipDefault: Bool = true) {
        if skipDefault && value == 0 { return }
        writeTag(field, .varint)
        writeVarint(UInt64(bitPattern: value))
    }

    mutating func write(field: Int, int32 value: Int, skipDefault: Bool = true) {
        write(field: field, int64: Int64(value), skipDefault: skipDefault)
    }

    mutating func write(field: Int, bool value: Bool, default def: Bool = false) {
        if value == def { return }
        writeTag(field, .varint)
        writeVarint(value ? 1 : 0)
    }

    mutating func write(field: Int, float value: Float, skipDefault: Bool = true) {
        if skipDefault && value == 0 { return }
        writeTag(field, .fixed32)
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    mutating func write(field: Int, string value: String?, skipEmpty: Bool = true) {
        guard let value else { return }
        if skipEmpty && value.isEmpty { return }
        write(field: field, bytes: Data(value.utf8))
    }

    mutating func write(field: Int, bytes value: Data) {
        writeTag(field, .lengthDelimited)
        writeVarint(UInt64(value.count))
        data.append(value)
    }

    /// Repeated string / message fields: one length-delimited entry each.
    mutating func write(field: Int, strings values: [String]) {
        for v in values { write(field: field, bytes: Data(v.utf8)) }
    }

    mutating func write(field: Int, messages: [Data]) {
        for m in messages { write(field: field, bytes: m) }
    }

    /// Repeated int64 — Mihon writes these unpacked, one tag per value.
    mutating func write(field: Int, int64s values: [Int64]) {
        for v in values {
            writeTag(field, .varint)
            writeVarint(UInt64(bitPattern: v))
        }
    }
}

/// Reads protobuf wire format, skipping fields it does not know.
///
/// Tolerating unknown fields is the whole point of the format: a backup written
/// by a newer Mihon must still restore here, minus whatever we cannot model.
struct ProtoReader {
    private let data: Data
    private var index: Int

    init(_ data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    var isAtEnd: Bool { index >= data.endIndex }

    struct MalformedError: Error {}

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < data.endIndex else { throw MalformedError() }
            let byte = data[index]
            index += 1
            // At shift 63 only bit 0 of the 7-bit payload lands inside the 64
            // result bits — anything above that silently overflows out of the
            // UInt64 rather than trapping, so a 10th byte with any higher bit
            // set must be rejected explicitly instead of being dropped.
            if shift == 63 && (byte & 0x7e) != 0 { throw MalformedError() }
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
            guard shift < 64 else { throw MalformedError() }
        }
        return result
    }

    /// Returns the next field number and wire type.
    mutating func readTag() throws -> (field: Int, type: ProtoWireType) {
        let key = try readVarint()
        guard let type = ProtoWireType(rawValue: Int(key & 0x7)) else { throw MalformedError() }
        // A hostile field number can be any 61-bit value; `Int(UInt64)` traps
        // once it overflows Int64.max, so this must fail the same way every
        // other malformed byte does — by throwing, not crashing.
        guard let field = Int(exactly: key >> 3) else { throw MalformedError() }
        return (field, type)
    }

    mutating func readBytes() throws -> Data {
        // A corrupt or malicious backup can put an arbitrary UInt64 in the
        // length prefix. `Int(UInt64)` traps at runtime once it exceeds
        // Int64.max, which would crash the app instead of surfacing the
        // "corrupt backup" alert — so this must go through `Int(exactly:)`
        // and throw like every other malformed-input path.
        guard let length = Int(exactly: try readVarint()) else { throw MalformedError() }
        // `index + length` can itself overflow Int and trap when `length` is a
        // huge-but-representable value from a crafted backup (e.g. Int.max - 1);
        // comparing via subtraction of two in-bounds indices cannot overflow.
        guard length >= 0, length <= data.endIndex - index else { throw MalformedError() }
        let slice = data.subdata(in: index..<(index + length))
        index += length
        return slice
    }

    mutating func readString() throws -> String {
        String(decoding: try readBytes(), as: UTF8.self)
    }

    mutating func readFloat() throws -> Float {
        guard index + 4 <= data.endIndex else { throw MalformedError() }
        let slice = data.subdata(in: index..<(index + 4))
        index += 4
        return Float(bitPattern: UInt32(littleEndian: slice.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
    }

    mutating func readInt64() throws -> Int64 { Int64(bitPattern: try readVarint()) }

    mutating func readBool() throws -> Bool { try readVarint() != 0 }

    /// Advances past a field this build does not model.
    mutating func skip(_ type: ProtoWireType) throws {
        switch type {
        case .varint: _ = try readVarint()
        case .fixed64: index += 8
        case .fixed32: index += 4
        case .lengthDelimited: _ = try readBytes()
        }
        guard index <= data.endIndex else { throw MalformedError() }
    }
}
