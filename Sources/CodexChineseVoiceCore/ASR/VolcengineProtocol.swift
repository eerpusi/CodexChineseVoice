import Foundation

public enum VolcengineProtocolError: Error, Equatable, Sendable {
    case truncatedFrame
    case invalidHeader
    case unsupportedMessageType(UInt8)
    case unsupportedFlags(UInt8)
    case unsupportedSerialization(UInt8)
    case unsupportedCompression(UInt8)
    case invalidSequence
    case invalidPayloadLength
    case invalidPayload
    case invalidJSON
    case invalidGzip
    case missingTranscript
    case providerError(code: Int32, message: String)
}

public struct VolcengineServerMessage: Equatable, Sendable {
    public let transcript: TranscriptEvent?
    public let sequence: Int32?
    public let event: Int32?

    public init(
        transcript: TranscriptEvent?,
        sequence: Int32?,
        event: Int32?
    ) {
        self.transcript = transcript
        self.sequence = sequence
        self.event = event
    }
}

public enum VolcengineProtocol {
    public static let endpoint = URL(
        string: "wss://openspeech.bytedance.com/api/v3/plan/sauc/bigmodel_async"
    )!
    public static let webSocketURL = endpoint
    public static let resourceID = "volc.seedasr.sauc.duration"

    public static func clientRequest(
        requestID: String,
        language: String = "zh-CN",
        sequence: Int = 1
    ) throws -> Data {
        guard !requestID.isEmpty, !language.isEmpty else {
            throw VolcengineProtocolError.invalidPayload
        }
        let payload: [String: Any] = [
            "user": ["uid": requestID],
            "audio": [
                "format": "pcm",
                "codec": "raw",
                "rate": 16_000,
                "bits": 16,
                "channel": 1,
                "language": language,
            ],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": false,
                "show_utterances": true,
                "enable_nonstream": false,
                "result_type": "full",
            ],
        ]
        let json: Data
        do {
            json = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw VolcengineProtocolError.invalidPayload
        }
        return try fullClientRequest(json, sequence: sequence)
    }

    public static func requestFrame(
        requestID: String,
        language: String = "zh-CN",
        sequence: Int = 1
    ) throws -> Data {
        try clientRequest(requestID: requestID, language: language, sequence: sequence)
    }

    public static func fullClientRequest(
        _ payload: Data,
        sequence: Int = 1
    ) throws -> Data {
        let sequenceValue = try checkedSequence(sequence)
        let compressed: Data
        do {
            compressed = try GzipCodec.compress(payload)
        } catch {
            throw VolcengineProtocolError.invalidGzip
        }
        return try frame(
            type: 0x1,
            flags: 0x1,
            serialization: 0x1,
            compression: 0x1,
            sequence: sequenceValue,
            payload: compressed
        )
    }

    public static func audioFrame(
        _ audio: Data,
        sequence: Int,
        isFinal: Bool
    ) throws -> Data {
        let sequenceValue = try checkedSequence(sequence)
        let wireSequence = isFinal ? -sequenceValue : sequenceValue
        let compressed: Data
        do {
            compressed = try GzipCodec.compress(audio)
        } catch {
            throw VolcengineProtocolError.invalidGzip
        }
        return try frame(
            type: 0x2,
            flags: isFinal ? 0x3 : 0x1,
            serialization: 0,
            compression: 0x1,
            sequence: wireSequence,
            payload: compressed
        )
    }

    static func frame(
        type: UInt8,
        flags: UInt8,
        serialization: UInt8,
        compression: UInt8,
        sequence: Int32?,
        payload: Data
    ) throws -> Data {
        guard payload.count <= Int(UInt32.max) else {
            throw VolcengineProtocolError.invalidPayloadLength
        }
        var frame = Data([0x11, (type << 4) | flags, (serialization << 4) | compression, 0])
        if let sequence {
            frame.append(sequence.bigEndianData)
        }
        frame.append(UInt32(payload.count).bigEndianData)
        frame.append(payload)
        return frame
    }

    static func checkedSequence(_ sequence: Int) throws -> Int32 {
        guard sequence > 0, sequence <= Int(Int32.max) else {
            throw VolcengineProtocolError.invalidSequence
        }
        return Int32(sequence)
    }

}

private extension FixedWidthInteger {
    var bigEndianData: Data {
        withUnsafeBytes(of: bigEndian) { Data($0) }
    }
}
