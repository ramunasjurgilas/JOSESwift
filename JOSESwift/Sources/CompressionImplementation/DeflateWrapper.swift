//
//  DeflateWrapper.swift
//  JOSESwift
//
//  Modified by Florian Häser on 24.12.18.
//  Removed all but the only supported and required compression algorithm.
//  [JOSE compression algorithm](https://www.iana.org/assignments/jose/jose.xhtml#web-encryption-compression-algorithms)
//  [Compression Algorithm) Header Parameter](https://tools.ietf.org/html/rfc7516#section-4.1.3)
//
//  Originally created by mw99 (Markus Wanke) in his libcompression wrapper https://github.com/mw99/DataCompression
//  licensed under Apache License, Version 2.0
//

import Foundation
import Compression

struct DeflateCompressor: CompressorProtocol {
    /// Compresses the data using the zlib deflate algorithm.
    /// - returns: raw deflated data according to [RFC-1951](https://tools.ietf.org/html/rfc1951).
    /// - note: Fixed at compression level 5 (best trade off between speed and time)
    public func compress(data: Data) throws -> Data {
        let config = (operation: COMPRESSION_STREAM_ENCODE, algorithm: COMPRESSION_ZLIB)
        let optionalData = data.withUnsafeBytes { (sourcePtr: UnsafePointer<UInt8>) -> Data? in
            return perform(config, source: sourcePtr, sourceSize: data.count)
        }
        if let _data = optionalData {
            return _data
        }
        throw JOSESwiftError.compressionFailed
    }

    /// Decompresses the data using the zlib deflate algorithm. Self is expected to be a raw deflate
    /// stream according to [RFC-1951](https://tools.ietf.org/html/rfc1951).
    /// - returns: uncompressed data
    public func decompress(data: Data) throws -> Data {
        let config = (operation: COMPRESSION_STREAM_DECODE, algorithm: COMPRESSION_ZLIB)
        let optionalData = data.withUnsafeBytes { (sourcePtr: UnsafePointer<UInt8>) -> Data? in
            return perform(config, source: sourcePtr, sourceSize: data.count)
        }
        if let _data = optionalData {
            return _data
        }
        throw JOSESwiftError.decompressionFailed
    }
}

private typealias Config = (operation: compression_stream_operation, algorithm: compression_algorithm)

private func perform(_ config: Config, source: UnsafePointer<UInt8>, sourceSize: Int, preload: Data = Data()) -> Data? {
    guard config.operation == COMPRESSION_STREAM_ENCODE || sourceSize > 0 else { return nil }

    let streamBase = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    defer { streamBase.deallocate() }
    var stream = streamBase.pointee

    let status = compression_stream_init(&stream, config.operation, config.algorithm)
    guard status != COMPRESSION_STATUS_ERROR else { return nil }
    defer { compression_stream_destroy(&stream) }

    let bufferSize = Swift.max( Swift.min(sourceSize, 64 * 1024), 64)
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    stream.dst_ptr  = buffer
    stream.dst_size = bufferSize
    stream.src_ptr  = source
    stream.src_size = sourceSize

    var res = preload
    let flags: Int32 = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)

    while true {
        switch compression_stream_process(&stream, flags) {
        case COMPRESSION_STATUS_OK:
            guard stream.dst_size == 0 else { return nil }
            res.append(buffer, count: stream.dst_ptr - buffer)
            stream.dst_ptr = buffer
            stream.dst_size = bufferSize

        case COMPRESSION_STATUS_END:
            res.append(buffer, count: stream.dst_ptr - buffer)
            return res

        default:
            return nil
        }
    }
}
