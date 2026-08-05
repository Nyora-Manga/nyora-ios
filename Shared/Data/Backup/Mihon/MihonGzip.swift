//
//  MihonGzip.swift
//  Nyora
//

import Compression
import Foundation

/// Gzip container around Apple's raw-DEFLATE `Compression` framework.
///
/// `COMPRESSION_ZLIB` on Darwin is raw deflate with no gzip header or trailer,
/// so the 10-byte header, CRC32 and ISIZE are assembled here. Mihon requires a
/// real gzip stream — its decoder sniffs the 0x1f8b magic.
enum MihonGzip {

    enum GzipError: Error { case malformed, failed }

    static func compress(_ data: Data) throws -> Data {
        let deflated = try transform(data, operation: COMPRESSION_STREAM_ENCODE, skipHeader: false)
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])  // fixed mtime = 0
        out.append(deflated)
        var crc = crc32(data).littleEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        var size = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &size) { out.append(contentsOf: $0) }
        return out
    }

    static func decompress(_ data: Data) throws -> Data {
        guard data.count > 18, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else {
            throw GzipError.malformed
        }
        let flags = data[data.startIndex + 3]
        var offset = data.startIndex + 10
        if flags & 0x04 != 0 {                      // FEXTRA
            guard offset + 2 <= data.endIndex else { throw GzipError.malformed }
            let xlen = Int(data[offset]) | Int(data[offset + 1]) << 8
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 { offset = try skipCString(data, from: offset) }   // FNAME
        if flags & 0x10 != 0 { offset = try skipCString(data, from: offset) }   // FCOMMENT
        if flags & 0x02 != 0 { offset += 2 }                                    // FHCRC
        guard offset < data.endIndex - 8 else { throw GzipError.malformed }
        let body = data.subdata(in: offset..<(data.endIndex - 8))
        return try transform(body, operation: COMPRESSION_STREAM_DECODE, skipHeader: true)
    }

    private static func skipCString(_ data: Data, from start: Int) throws -> Int {
        var i = start
        while i < data.endIndex, data[i] != 0 { i += 1 }
        guard i < data.endIndex else { throw GzipError.malformed }
        return i + 1
    }

    private static func transform(
        _ input: Data,
        operation: compression_stream_operation,
        skipHeader: Bool
    ) throws -> Data {
        guard !input.isEmpty else { return Data() }
        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0, state: nil
        )
        guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw GzipError.failed
        }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var output = Data()
        var result: Data?
        var thrown: Error?
        input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.src_ptr = base
            stream.src_size = input.count
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            repeat {
                stream.dst_ptr = buffer
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, flags)
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    output.append(buffer, count: bufferSize - stream.dst_size)
                    if status == COMPRESSION_STATUS_END { result = output; return }
                default:
                    thrown = GzipError.failed
                    return
                }
            } while true
        }
        if let thrown { throw thrown }
        guard let result else { throw GzipError.failed }
        _ = skipHeader
        return result
    }

    /// Standard CRC-32 (IEEE), computed on the fly to avoid a table constant.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xffff_ffff
    }
}
