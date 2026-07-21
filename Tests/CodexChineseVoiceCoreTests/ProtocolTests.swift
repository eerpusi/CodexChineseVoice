import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class ProtocolTests: XCTestCase {
    func testFinalAudioFrameUsesNegativeSequenceAndFinalFlag() throws {
        let frame = try VolcengineProtocol.audioFrame(
            Data("pcm".utf8),
            sequence: 7,
            isFinal: true
        )

        XCTAssertEqual(Array(frame.prefix(4)), [0x11, 0x23, 0x01, 0x00])
        XCTAssertEqual(frame.readInt32(at: 4), -7)
        let payload = try XCTUnwrap(frame.sizedPayload(at: 8))
        XCTAssertEqual(try GzipCodec.decompress(payload), Data("pcm".utf8))
    }

    func testNonFinalAudioFrameUsesPositiveSequence() throws {
        let frame = try VolcengineProtocol.audioFrame(
            Data([1, 2, 3]),
            sequence: 2,
            isFinal: false
        )

        XCTAssertEqual(Array(frame.prefix(4)), [0x11, 0x21, 0x01, 0x00])
        XCTAssertEqual(frame.readInt32(at: 4), 2)
    }

    func testClientRequestContainsGzippedJSONAndSequence() throws {
        let frame = try VolcengineProtocol.clientRequest(
            requestID: "request-id",
            language: "zh-CN",
            sequence: 1
        )

        XCTAssertEqual(Array(frame.prefix(4)), [0x11, 0x11, 0x11, 0x00])
        XCTAssertEqual(frame.readInt32(at: 4), 1)
        let payload = try XCTUnwrap(frame.sizedPayload(at: 8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: GzipCodec.decompress(payload),
                options: []
            ) as? [String: Any]
        )
        let user = try XCTUnwrap(object["user"] as? [String: Any])
        XCTAssertEqual(user["uid"] as? String, "request-id")
        let audio = try XCTUnwrap(object["audio"] as? [String: Any])
        XCTAssertEqual(audio["rate"] as? Int, 16_000)
        XCTAssertEqual(audio["channel"] as? Int, 1)
        let request = try XCTUnwrap(object["request"] as? [String: Any])
        XCTAssertEqual(request["model_name"] as? String, "bigmodel")
        XCTAssertEqual(request["enable_punc"] as? Bool, true)
    }

    func testPartialServerFlagProducesNonFinalTranscript() throws {
        let message = try VolcengineProtocol.parseServerFrame(
            try serverFrame(text: "正在识别", sequence: 3, flags: 0x1)
        )

        XCTAssertEqual(message, TranscriptEvent(text: "正在识别", isFinal: false))
    }

    func testFinalServerFlagMarksTranscriptFinal() throws {
        let message = try VolcengineProtocol.parseServerFrame(
            try serverFrame(text: "你好", sequence: 3, flags: 0x3)
        )

        XCTAssertEqual(message, TranscriptEvent(text: "你好", isFinal: true))
    }

    func testNegativeSequenceMarksTranscriptFinalEvenWithoutFinalFlag() throws {
        let message = try VolcengineProtocol.parseServerFrame(
            try serverFrame(text: "完成", sequence: -3, flags: 0x1)
        )

        XCTAssertEqual(message, TranscriptEvent(text: "完成", isFinal: true))
    }

    func testResponseWithoutTranscriptIsReportedAsNoTranscript() throws {
        let frame = try serverFrame(
            payload: try GzipCodec.compress(Data(#"{"result":{}}"#.utf8)),
            sequence: 1,
            flags: 0x1
        )

        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .missingTranscript)
        }
    }

    func testEmptyServerPayloadParsesAsAcknowledgement() throws {
        let frame = try serverFrame(payload: Data(), sequence: 1, flags: 0x1)

        XCTAssertEqual(
            try VolcengineProtocol.parseServerMessage(frame),
            VolcengineServerMessage(transcript: nil, sequence: 1, event: nil)
        )
    }

    func testTruncatedFrameIsRejected() {
        for count in 0..<12 {
            var frame = Data(repeating: 0, count: count)
            if count >= 4 {
                frame[0] = 0x11
                frame[1] = 0x91
                frame[2] = 0x11
            }
            XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
                XCTAssertEqual(error as? VolcengineProtocolError, .truncatedFrame)
            }
        }
    }

    func testInvalidHeaderAndUnsupportedMessageAreRejected() throws {
        var invalidVersion = try serverFrame(text: "x", sequence: 1, flags: 0x1)
        invalidVersion[0] = 0x21
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(invalidVersion)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidHeader)
        }

        var unsupportedType = try serverFrame(text: "x", sequence: 1, flags: 0x1)
        unsupportedType[1] = 0x41
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(unsupportedType)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .unsupportedMessageType(4))
        }
    }

    func testHeaderSizeMustBeExactlyOneWord() throws {
        var zeroWords = try serverFrame(text: "x", sequence: 1, flags: 0x1)
        zeroWords[0] = 0x10
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(zeroWords)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidHeader)
        }

        var twoWords = try serverFrame(text: "x", sequence: 1, flags: 0x1)
        twoWords.insert(contentsOf: [0, 0, 0, 0], at: 4)
        twoWords[0] = 0x12
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(twoWords)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidHeader)
        }
    }

    func testUnsupportedFlagsSerializationAndCompressionAreRejected() throws {
        let frame = try serverFrame(text: "x", sequence: 1, flags: 0x1)

        var flags = frame
        flags[1] = 0x98
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(flags)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .unsupportedFlags(8))
        }

        var serialization = frame
        serialization[2] = 0x21
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(serialization)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .unsupportedSerialization(2))
        }

        var compression = frame
        compression[2] = 0x12
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(compression)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .unsupportedCompression(2))
        }
    }

    func testDeclaredPayloadLargerThanFrameIsRejected() throws {
        var frame = try serverFrame(text: "x", sequence: 1, flags: 0x1)
        let declared = frame.readUInt32(at: 8)
        frame.replaceSubrange(8..<12, with: (declared + 10).bigEndianData)

        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidPayloadLength)
        }
    }

    func testTrailingBytesAreRejected() throws {
        var frame = try serverFrame(text: "x", sequence: 1, flags: 0x1)
        frame.append(0xff)

        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidPayloadLength)
        }
    }

    func testInvalidGzipAndJSONAreRejected() throws {
        let invalidGzip = try serverFrame(
            payload: Data("not gzip".utf8),
            sequence: 1,
            flags: 0x1
        )
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(invalidGzip)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidGzip)
        }

        let invalidJSON = try serverFrame(
            payload: try GzipCodec.compress(Data("not json".utf8)),
            sequence: 1,
            flags: 0x1
        )
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(invalidJSON)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidJSON)
        }
    }

    func testProviderErrorFrameMapsCodeAndMessage() throws {
        let frame = try errorFrame(code: 403, message: "Forbidden.AgentPlanDeductNotEnabled")

        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
            XCTAssertEqual(
                error as? VolcengineProtocolError,
                .providerError(code: 403, message: "Forbidden.AgentPlanDeductNotEnabled")
            )
        }
    }

    func testGzipRoundTripAndOutputLimit() throws {
        let input = Data(repeating: 0x61, count: 1_024)
        let compressed = try GzipCodec.compress(input)
        XCTAssertEqual(try GzipCodec.decompress(compressed), input)

        XCTAssertThrowsError(
            try GzipCodec.decompress(compressed, maxOutputBytes: 128)
        ) { error in
            XCTAssertEqual(error as? GzipCodecError, .outputLimitExceeded)
        }
    }

    private func serverFrame(
        text: String? = nil,
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
            body = try GzipCodec.compress(
                Data(
                    #"{"result":{"text":"\#(text ?? "")"}}"#.utf8
                )
            )
        }
        var frame = Data([0x11, (type << 4) | flags, 0x10 | compression, 0x00])
        if flags & 0x1 != 0 {
            frame.append(sequence.bigEndianData)
        }
        frame.append(UInt32(body.count).bigEndianData)
        frame.append(body)
        return frame
    }

    private func errorFrame(code: Int32, message: String) throws -> Data {
        let body = try GzipCodec.compress(Data(message.utf8))
        var frame = Data([0x11, 0xf0, 0x01, 0x00])
        frame.append(code.bigEndianData)
        frame.append(UInt32(body.count).bigEndianData)
        frame.append(body)
        return frame
    }
}

private extension Data {
    func readInt32(at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32(at: offset))
    }

    func readUInt32(at offset: Int) -> UInt32 {
        precondition(offset >= 0 && offset + 4 <= count)
        return withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return (UInt32(bytes[offset]) << 24)
                | (UInt32(bytes[offset + 1]) << 16)
                | (UInt32(bytes[offset + 2]) << 8)
                | UInt32(bytes[offset + 3])
        }
    }

    func sizedPayload(at offset: Int) -> Data? {
        guard offset + 4 <= count else { return nil }
        let size = Int(readUInt32(at: offset))
        guard size <= count - offset - 4 else { return nil }
        return subdata(in: (offset + 4)..<(offset + 4 + size))
    }
}

private extension FixedWidthInteger {
    var bigEndianData: Data {
        withUnsafeBytes(of: bigEndian) { Data($0) }
    }
}
