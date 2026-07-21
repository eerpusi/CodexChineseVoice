import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class ProtocolRequestTests: XCTestCase {
    func testFinalAudioFrameUsesNegativeSequenceAndFinalFlag() throws {
        let frame = try VolcengineProtocol.audioFrame(
            Data("pcm".utf8),
            sequence: 7,
            isFinal: true
        )

        XCTAssertEqual(Array(frame.prefix(4)), [0x11, 0x23, 0x01, 0x00])
        XCTAssertEqual(frame.protocolReadInt32(at: 4), -7)
        let payload = try XCTUnwrap(frame.protocolSizedPayload(at: 8))
        XCTAssertEqual(try GzipCodec.decompress(payload), Data("pcm".utf8))
    }

    func testFinalEmptyAudioFrameIsGzippedAndUsesFinalSequence() throws {
        let frame = try VolcengineProtocol.audioFrame(
            Data(),
            sequence: 8,
            isFinal: true
        )

        XCTAssertEqual(Array(frame.prefix(4)), [0x11, 0x23, 0x01, 0x00])
        XCTAssertEqual(frame.protocolReadInt32(at: 4), -8)
        let payload = try XCTUnwrap(frame.protocolSizedPayload(at: 8))
        XCTAssertFalse(payload.isEmpty)
        XCTAssertEqual(try GzipCodec.decompress(payload), Data())
    }

    func testNonFinalAudioFrameUsesPositiveSequence() throws {
        let frame = try VolcengineProtocol.audioFrame(
            Data([1, 2, 3]),
            sequence: 2,
            isFinal: false
        )

        XCTAssertEqual(Array(frame.prefix(4)), [0x11, 0x21, 0x01, 0x00])
        XCTAssertEqual(frame.protocolReadInt32(at: 4), 2)
    }

    func testClientRequestContainsAllFixedGzippedJSONFields() throws {
        let frame = try VolcengineProtocol.clientRequest(
            requestID: "request-id",
            language: "zh-CN",
            sequence: 1
        )

        XCTAssertEqual(Array(frame.prefix(4)), [0x11, 0x11, 0x11, 0x00])
        XCTAssertEqual(frame.protocolReadInt32(at: 4), 1)
        let payload = try XCTUnwrap(frame.protocolSizedPayload(at: 8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: GzipCodec.decompress(payload),
                options: []
            ) as? [String: Any]
        )
        let user = try XCTUnwrap(object["user"] as? [String: Any])
        XCTAssertEqual(user.count, 1)
        XCTAssertEqual(user["uid"] as? String, "request-id")

        let audio = try XCTUnwrap(object["audio"] as? [String: Any])
        XCTAssertEqual(audio.count, 6)
        XCTAssertEqual(audio["format"] as? String, "pcm")
        XCTAssertEqual(audio["codec"] as? String, "raw")
        XCTAssertEqual(audio["rate"] as? Int, 16_000)
        XCTAssertEqual(audio["bits"] as? Int, 16)
        XCTAssertEqual(audio["channel"] as? Int, 1)
        XCTAssertEqual(audio["language"] as? String, "zh-CN")

        let request = try XCTUnwrap(object["request"] as? [String: Any])
        XCTAssertEqual(request.count, 7)
        XCTAssertEqual(request["model_name"] as? String, "bigmodel")
        XCTAssertEqual(request["enable_itn"] as? Bool, true)
        XCTAssertEqual(request["enable_punc"] as? Bool, true)
        XCTAssertEqual(request["enable_ddc"] as? Bool, false)
        XCTAssertEqual(request["show_utterances"] as? Bool, true)
        XCTAssertEqual(request["enable_nonstream"] as? Bool, false)
        XCTAssertEqual(request["result_type"] as? String, "full")
    }

    func testClientSequenceMustBePositiveAndFitInt32() {
        for sequence in [0, -1, Int(Int32.max) + 1] {
            XCTAssertThrowsError(
                try VolcengineProtocol.clientRequest(
                    requestID: "request-id",
                    sequence: sequence
                )
            ) { error in
                XCTAssertEqual(error as? VolcengineProtocolError, .invalidSequence)
            }
            XCTAssertThrowsError(
                try VolcengineProtocol.audioFrame(
                    Data([1]),
                    sequence: sequence,
                    isFinal: false
                )
            ) { error in
                XCTAssertEqual(error as? VolcengineProtocolError, .invalidSequence)
            }
        }
    }
}
