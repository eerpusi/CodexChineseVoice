import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class ProtocolParsingTests: XCTestCase {
    func testPartialServerFlagProducesNonFinalTranscript() throws {
        let message = try VolcengineProtocol.parseServerFrame(
            try ProtocolTestSupport.serverFrame(text: "正在识别", sequence: 3, flags: 0x1)
        )

        XCTAssertEqual(message, TranscriptEvent(text: "正在识别", isFinal: false))
    }

    func testFinalServerFlagMarksTranscriptFinal() throws {
        let message = try VolcengineProtocol.parseServerFrame(
            try ProtocolTestSupport.serverFrame(text: "你好", sequence: 3, flags: 0x3)
        )

        XCTAssertEqual(message, TranscriptEvent(text: "你好", isFinal: true))
    }

    func testNegativeSequenceMarksTranscriptFinalEvenWithoutFinalFlag() throws {
        let message = try VolcengineProtocol.parseServerFrame(
            try ProtocolTestSupport.serverFrame(text: "完成", sequence: -3, flags: 0x1)
        )

        XCTAssertEqual(message, TranscriptEvent(text: "完成", isFinal: true))
    }

    func testServerSequenceZeroIsRejected() throws {
        let frame = try ProtocolTestSupport.serverFrame(text: "无效", sequence: 0, flags: 0x1)

        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidSequence)
        }
    }

    func testResultObjectAndArrayBothExposeLatestUsableText() throws {
        let object = try ProtocolTestSupport.serverFrame(
            json: #"{"result":{"text":"对象文本"}}"#,
            sequence: 2,
            flags: 0x1
        )
        XCTAssertEqual(
            try VolcengineProtocol.parseServerFrame(object),
            TranscriptEvent(text: "对象文本", isFinal: false)
        )

        let array = try ProtocolTestSupport.serverFrame(
            json: #"{"result":[{"text":"旧文本"},{"other":true},{"text":"最新文本"}]}"#,
            sequence: 2,
            flags: 0x1
        )
        XCTAssertEqual(
            try VolcengineProtocol.parseServerFrame(array),
            TranscriptEvent(text: "最新文本", isFinal: false)
        )
    }

    func testResultArraySkipsEmptyAndNonStringEntries() throws {
        let frame = try ProtocolTestSupport.serverFrame(
            json: #"{"result":[{"text":""},{"text":42}]}"#,
            sequence: 2,
            flags: 0x1
        )

        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .missingTranscript)
        }
    }

    func testUnsupportedResultShapeIsRejected() throws {
        let frame = try ProtocolTestSupport.serverFrame(
            json: #"{"result":"unexpected"}"#,
            sequence: 2,
            flags: 0x1
        )

        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidPayload)
        }
    }

    func testResponseWithoutTranscriptIsReportedAsNoTranscript() throws {
        let frame = try ProtocolTestSupport.serverFrame(
            payload: try GzipCodec.compress(Data(#"{"result":{}}"#.utf8)),
            sequence: 1,
            flags: 0x1
        )

        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .missingTranscript)
        }
    }

    func testEmptyServerPayloadParsesAsAcknowledgement() throws {
        let frame = try ProtocolTestSupport.serverFrame(payload: Data(), sequence: 1, flags: 0x1)

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
            if count >= 8 {
                frame[7] = 1
            }
            XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
                XCTAssertEqual(error as? VolcengineProtocolError, .truncatedFrame)
            }
        }
    }

    func testInvalidHeaderAndUnsupportedMessageAreRejected() throws {
        var invalidVersion = try ProtocolTestSupport.serverFrame(text: "x", sequence: 1, flags: 0x1)
        invalidVersion[0] = 0x21
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(invalidVersion)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidHeader)
        }

        var unsupportedType = try ProtocolTestSupport.serverFrame(text: "x", sequence: 1, flags: 0x1)
        unsupportedType[1] = 0x41
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(unsupportedType)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .unsupportedMessageType(4))
        }
    }

    func testHeaderSizeMustBeExactlyOneWord() throws {
        var zeroWords = try ProtocolTestSupport.serverFrame(text: "x", sequence: 1, flags: 0x1)
        zeroWords[0] = 0x10
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(zeroWords)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidHeader)
        }

        var twoWords = try ProtocolTestSupport.serverFrame(text: "x", sequence: 1, flags: 0x1)
        twoWords.insert(contentsOf: [0, 0, 0, 0], at: 4)
        twoWords[0] = 0x12
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(twoWords)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidHeader)
        }
    }

    func testUnsupportedFlagsSerializationAndCompressionAreRejected() throws {
        let frame = try ProtocolTestSupport.serverFrame(text: "x", sequence: 1, flags: 0x1)

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
        var frame = try ProtocolTestSupport.serverFrame(text: "x", sequence: 1, flags: 0x1)
        let declared = frame.protocolReadUInt32(at: 8)
        frame.replaceSubrange(8..<12, with: (declared + 10).protocolBigEndianData)

        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidPayloadLength)
        }
    }

    func testTrailingBytesAreRejected() throws {
        var frame = try ProtocolTestSupport.serverFrame(text: "x", sequence: 1, flags: 0x1)
        frame.append(0xff)

        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidPayloadLength)
        }
    }

    func testInvalidGzipAndJSONAreRejected() throws {
        let invalidGzip = try ProtocolTestSupport.serverFrame(
            payload: Data("not gzip".utf8),
            sequence: 1,
            flags: 0x1
        )
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(invalidGzip)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidGzip)
        }

        let invalidJSON = try ProtocolTestSupport.serverFrame(
            payload: try GzipCodec.compress(Data("not json".utf8)),
            sequence: 1,
            flags: 0x1
        )
        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(invalidJSON)) { error in
            XCTAssertEqual(error as? VolcengineProtocolError, .invalidJSON)
        }
    }

    func testProviderErrorFrameMapsCodeAndMessage() throws {
        let frame = try ProtocolTestSupport.errorFrame(
            code: 403,
            message: "Forbidden.AgentPlanDeductNotEnabled"
        )

        XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
            XCTAssertEqual(
                error as? VolcengineProtocolError,
                .providerError(code: 403, message: "Forbidden.AgentPlanDeductNotEnabled")
            )
        }
    }

    func testErrorFrameRequiresNoFlags() throws {
        for flags in [UInt8(0x1), UInt8(0x4)] {
            let frame = try ProtocolTestSupport.errorFrame(
                code: 400,
                message: "bad request",
                flags: flags
            )

            XCTAssertThrowsError(try VolcengineProtocol.parseServerFrame(frame)) { error in
                XCTAssertEqual(error as? VolcengineProtocolError, .unsupportedFlags(flags))
            }
        }
    }
}
