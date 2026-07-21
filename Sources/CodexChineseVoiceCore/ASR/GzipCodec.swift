import Foundation
import zlib

public enum GzipCodecError: Error, Equatable, Sendable {
    case invalidOutputLimit
    case inputTooLarge
    case compressionFailed(Int32)
    case invalidGzip
    case outputLimitExceeded
}

public struct GzipCodec: Sendable {
    public static let defaultMaximumOutputBytes = 4 * 1024 * 1024

    private let maximumOutputBytes: Int

    public init(maxOutputBytes: Int = Self.defaultMaximumOutputBytes) {
        self.maximumOutputBytes = maxOutputBytes
    }

    public static func compress(_ input: Data) throws -> Data {
        try compressData(input)
    }

    public static func decompress(
        _ input: Data,
        maxOutputBytes: Int = defaultMaximumOutputBytes
    ) throws -> Data {
        try decompressData(input, maximumOutputBytes: maxOutputBytes)
    }

    public func compress(_ input: Data) throws -> Data {
        try Self.compress(input)
    }

    public func decompress(_ input: Data) throws -> Data {
        try Self.decompress(input, maxOutputBytes: maximumOutputBytes)
    }
}

private extension GzipCodec {
    static func compressData(_ input: Data) throws -> Data {
        guard input.count <= Int(UInt32.max) else {
            throw GzipCodecError.inputTooLarge
        }

        var stream = z_stream()
        let initialization = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            MAX_WBITS + 16,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initialization == Z_OK else {
            throw GzipCodecError.compressionFailed(initialization)
        }
        defer { deflateEnd(&stream) }

        return try input.withUnsafeBytes { rawInput in
            stream.next_in = UnsafeMutablePointer(
                mutating: rawInput.bindMemory(to: Bytef.self).baseAddress
            )
            stream.avail_in = uInt(rawInput.count)

            var output = Data()
            var status: Int32 = Z_OK
            repeat {
                var buffer = [UInt8](repeating: 0, count: 16 * 1024)
                let produced = buffer.withUnsafeMutableBytes { rawOutput -> Int in
                    stream.next_out = rawOutput.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(rawOutput.count)
                    status = deflate(&stream, Z_FINISH)
                    return rawOutput.count - Int(stream.avail_out)
                }
                output.append(contentsOf: buffer.prefix(produced))
                if status != Z_OK && status != Z_STREAM_END {
                    throw GzipCodecError.compressionFailed(status)
                }
            } while status != Z_STREAM_END
            return output
        }
    }

    static func decompressData(
        _ input: Data,
        maximumOutputBytes: Int
    ) throws -> Data {
        guard maximumOutputBytes > 0 else {
            throw GzipCodecError.invalidOutputLimit
        }
        guard input.count <= Int(UInt32.max) else {
            throw GzipCodecError.inputTooLarge
        }

        var stream = z_stream()
        let initialization = inflateInit2_(
            &stream,
            MAX_WBITS + 16,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initialization == Z_OK else {
            throw GzipCodecError.invalidGzip
        }
        defer { inflateEnd(&stream) }

        return try input.withUnsafeBytes { rawInput in
            stream.next_in = UnsafeMutablePointer(
                mutating: rawInput.bindMemory(to: Bytef.self).baseAddress
            )
            stream.avail_in = uInt(rawInput.count)

            var output = Data()
            var status: Int32 = Z_OK
            repeat {
                var buffer = [UInt8](repeating: 0, count: 16 * 1024)
                let produced = buffer.withUnsafeMutableBytes { rawOutput -> Int in
                    stream.next_out = rawOutput.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(rawOutput.count)
                    status = inflate(&stream, Z_NO_FLUSH)
                    return rawOutput.count - Int(stream.avail_out)
                }

                guard produced <= maximumOutputBytes - output.count else {
                    throw GzipCodecError.outputLimitExceeded
                }
                output.append(contentsOf: buffer.prefix(produced))

                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else {
                        throw GzipCodecError.invalidGzip
                    }
                    return output
                }
                guard status == Z_OK else {
                    throw GzipCodecError.invalidGzip
                }
                guard produced > 0 || stream.avail_in > 0 else {
                    throw GzipCodecError.invalidGzip
                }
            } while true
        }
    }
}
