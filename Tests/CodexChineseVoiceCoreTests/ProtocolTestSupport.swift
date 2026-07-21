import Foundation
@testable import CodexChineseVoiceCore

enum ProtocolTestSupport {
    static func serverFrame(
        text: String? = nil,
        json: String? = nil,
        payload: Data? = nil,
        sequence: Int32,
        flags: UInt8,
        compression: UInt8 = 1,
        type: UInt8 = 0x9
    ) throws -> Data {
        let body: Data
        if let payload {
            body = payload
        } else {
            let source = json ?? #"{"result":{"text":"\#(text ?? "")"}}"#
            body = try GzipCodec.compress(Data(source.utf8))
        }
        var frame = Data([0x11, (type << 4) | flags, 0x10 | compression, 0x00])
        if flags & 0x1 != 0 {
            frame.append(sequence.protocolBigEndianData)
        }
        if flags & 0x4 != 0 {
            frame.append(Int32(0).protocolBigEndianData)
        }
        frame.append(UInt32(body.count).protocolBigEndianData)
        frame.append(body)
        return frame
    }

    static func errorFrame(
        code: Int32,
        message: String,
        flags: UInt8 = 0
    ) throws -> Data {
        let body = try GzipCodec.compress(Data(message.utf8))
        var frame = Data([0x11, 0xf0 | flags, 0x01, 0x00])
        if flags & 0x1 != 0 {
            frame.append(Int32(1).protocolBigEndianData)
        }
        if flags & 0x4 != 0 {
            frame.append(Int32(0).protocolBigEndianData)
        }
        frame.append(code.protocolBigEndianData)
        frame.append(UInt32(body.count).protocolBigEndianData)
        frame.append(body)
        return frame
    }
}

extension Data {
    func protocolReadInt32(at offset: Int) -> Int32 {
        Int32(bitPattern: protocolReadUInt32(at: offset))
    }

    func protocolReadUInt32(at offset: Int) -> UInt32 {
        precondition(offset >= 0 && offset + 4 <= count)
        return withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return (UInt32(bytes[offset]) << 24)
                | (UInt32(bytes[offset + 1]) << 16)
                | (UInt32(bytes[offset + 2]) << 8)
                | UInt32(bytes[offset + 3])
        }
    }

    func protocolSizedPayload(at offset: Int) -> Data? {
        guard offset + 4 <= count else { return nil }
        let size = Int(protocolReadUInt32(at: offset))
        guard size <= count - offset - 4 else { return nil }
        return subdata(in: (offset + 4)..<(offset + 4 + size))
    }
}

extension FixedWidthInteger {
    var protocolBigEndianData: Data {
        withUnsafeBytes(of: bigEndian) { Data($0) }
    }
}
