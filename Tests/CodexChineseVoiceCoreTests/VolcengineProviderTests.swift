import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class VolcengineProviderTests: XCTestCase {
    func testBuildsAgentPlanRequestAndSendsHandshakeFirst() async throws {
        let finalEvent = TranscriptEvent(text: "完成", isFinal: true)
        let connection = FakeVolcengineConnection(
            incoming: [
                .data(
                    try ProtocolTestSupport.serverFrame(
                        text: finalEvent.text,
                        sequence: -1,
                        flags: 0x3
                    )
                ),
            ],
            releaseIncomingAfterFinalAudio: true
        )
        let transport = FakeVolcengineTransport(connection: connection)
        let provider = VolcengineProvider(
            apiKey: "synthetic-api-key",
            transport: transport,
            requestID: "request-id",
            connectID: "connect-id",
            language: "zh-CN"
        )

        let events = try await collect(
            provider.events(audio: finishedAudioStream())
        )

        XCTAssertEqual(events, [finalEvent])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "wss://openspeech.bytedance.com/api/v3/plan/sauc/bigmodel_async"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "synthetic-api-key")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Api-Resource-Id"),
            "volc.seedasr.sauc.duration"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Request-Id"), "request-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Connect-Id"), "connect-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Sequence"), "1")

        let handshake = try XCTUnwrap(connection.sentFrames.first)
        XCTAssertEqual(Array(handshake.prefix(4)), [0x11, 0x11, 0x11, 0x00])
        XCTAssertEqual(handshake.protocolReadInt32(at: 4), 1)
        let payload = try XCTUnwrap(handshake.protocolSizedPayload(at: 8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: GzipCodec.decompress(payload)
            ) as? [String: Any]
        )
        let user = try XCTUnwrap(object["user"] as? [String: Any])
        XCTAssertEqual(user["uid"] as? String, "request-id")
    }

    func testSendsEveryAudioChunkAndAnExplicitFinalFrame() async throws {
        let connection = FakeVolcengineConnection()
        let transport = FakeVolcengineTransport(connection: connection)
        let provider = VolcengineProvider(
            apiKey: "synthetic-api-key",
            transport: transport,
            requestID: "request-id",
            connectID: "connect-id"
        )
        let collector = Task<[TranscriptEvent], Error> {
            try await collect(
                provider.events(
                    audio: finishedAudioStream([Data([1, 2]), Data([3, 4, 5])])
                )
            )
        }

        try await waitForSentFrames(connection, count: 4)
        connection.enqueue(
            .data(
                try ProtocolTestSupport.serverFrame(
                    text: "完成",
                    sequence: -4,
                    flags: 0x3
                )
            )
        )
        let events = try await collector.value
        XCTAssertEqual(
            events,
            [TranscriptEvent(text: "完成", isFinal: true)]
        )

        let frames = connection.sentFrames
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames[1].protocolReadInt32(at: 4), 2)
        XCTAssertEqual(
            try GzipCodec.decompress(
                try XCTUnwrap(frames[1].protocolSizedPayload(at: 8))
            ),
            Data([1, 2])
        )
        XCTAssertEqual(frames[2].protocolReadInt32(at: 4), 3)
        XCTAssertEqual(
            try GzipCodec.decompress(
                try XCTUnwrap(frames[2].protocolSizedPayload(at: 8))
            ),
            Data([3, 4, 5])
        )
        XCTAssertEqual(Array(frames[3].prefix(4)), [0x11, 0x23, 0x01, 0x00])
        XCTAssertEqual(frames[3].protocolReadInt32(at: 4), -4)
        XCTAssertEqual(
            try GzipCodec.decompress(
                try XCTUnwrap(frames[3].protocolSizedPayload(at: 8))
            ),
            Data()
        )
    }

    func testStreamsPartialThenFinalTranscriptEvents() async throws {
        let connection = FakeVolcengineConnection(
            incoming: [
                .data(
                    try ProtocolTestSupport.serverFrame(
                        text: "正在识别",
                        sequence: 2,
                        flags: 0x1
                    )
                ),
                .data(
                    try ProtocolTestSupport.serverFrame(
                        text: "你好",
                        sequence: -3,
                        flags: 0x3
                    )
                ),
            ],
            releaseIncomingAfterFinalAudio: true
        )
        let provider = VolcengineProvider(
            apiKey: "synthetic-api-key",
            transport: FakeVolcengineTransport(connection: connection),
            requestID: "request-id",
            connectID: "connect-id"
        )

        let events = try await collect(
            provider.events(audio: finishedAudioStream())
        )
        XCTAssertEqual(
            events,
            [
                TranscriptEvent(text: "正在识别", isFinal: false),
                TranscriptEvent(text: "你好", isFinal: true),
            ]
        )
    }

    func testDropsDuplicatePartialButKeepsMatchingFinalEvent() async throws {
        let connection = FakeVolcengineConnection(
            incoming: [
                .data(
                    try ProtocolTestSupport.serverFrame(
                        text: "你好",
                        sequence: 2,
                        flags: 0x1
                    )
                ),
                .data(
                    try ProtocolTestSupport.serverFrame(
                        text: "你好",
                        sequence: 3,
                        flags: 0x1
                    )
                ),
                .data(
                    try ProtocolTestSupport.serverFrame(
                        text: "你好",
                        sequence: -4,
                        flags: 0x3
                    )
                ),
            ],
            releaseIncomingAfterFinalAudio: true
        )
        let provider = VolcengineProvider(
            apiKey: "synthetic-api-key",
            transport: FakeVolcengineTransport(connection: connection),
            requestID: "request-id",
            connectID: "connect-id"
        )

        let events = try await collect(
            provider.events(audio: finishedAudioStream())
        )

        XCTAssertEqual(
            events,
            [
                TranscriptEvent(text: "你好", isFinal: false),
                TranscriptEvent(text: "你好", isFinal: true),
            ]
        )
    }

    func testProviderErrorFrameFinishesStreamWithProtocolError() async throws {
        let connection = FakeVolcengineConnection(
            incoming: [
                .data(
                    try ProtocolTestSupport.errorFrame(
                        code: 403,
                        message: "synthetic provider failure"
                    )
                ),
            ],
            releaseIncomingAfterFinalAudio: true
        )
        let provider = VolcengineProvider(
            apiKey: "synthetic-api-key",
            transport: FakeVolcengineTransport(connection: connection),
            requestID: "request-id",
            connectID: "connect-id"
        )

        do {
            _ = try await collect(provider.events(audio: finishedAudioStream()))
            XCTFail("Expected provider error")
        } catch {
            XCTAssertEqual(
                error as? VolcengineProtocolError,
                .providerError(code: 403, message: "synthetic provider failure")
            )
        }
        XCTAssertTrue(connection.closed)
    }

}
