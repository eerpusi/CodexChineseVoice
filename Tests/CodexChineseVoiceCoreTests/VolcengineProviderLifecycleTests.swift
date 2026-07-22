import Foundation
import XCTest
@testable import CodexChineseVoiceCore

extension VolcengineProviderTests {
    func testEmptyAPIKeyFailsBeforeOpeningTransport() async throws {
        let connection = FakeVolcengineConnection()
        let transport = FakeVolcengineTransport(connection: connection)
        let provider = VolcengineProvider(
            apiKey: "",
            transport: transport,
            requestID: "request-id",
            connectID: "connect-id"
        )

        do {
            _ = try await collect(provider.events(audio: finishedAudioStream()))
            XCTFail("Expected missing API key")
        } catch {
            XCTAssertEqual(error as? VolcengineProviderError, .missingAPIKey)
        }
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(connection.sentFrames.isEmpty)
    }

    func testCancellingConsumerClosesOpenTransport() async throws {
        let connection = FakeVolcengineConnection()
        let transport = FakeVolcengineTransport(connection: connection)
        let provider = VolcengineProvider(
            apiKey: "synthetic-api-key",
            transport: transport,
            requestID: "request-id",
            connectID: "connect-id"
        )
        var audioContinuation: AsyncThrowingStream<Data, Error>.Continuation?
        let audio = AsyncThrowingStream<Data, Error> { continuation in
            audioContinuation = continuation
        }
        let consumer = Task<[TranscriptEvent], Error> {
            try await collect(provider.events(audio: audio))
        }

        try await waitForSentFrames(connection, count: 1)
        consumer.cancel()
        let closedByCancellation = await waitForConnectionClose(connection)
        audioContinuation?.finish()
        _ = await consumer.result

        XCTAssertTrue(closedByCancellation)
    }

    func testCancellingConsumerWhileHandshakeSendIsSuspendedClosesTransport() async throws {
        let connection = FakeVolcengineConnection(
            suspendHandshakeUntilClose: true
        )
        let provider = VolcengineProvider(
            apiKey: "synthetic-api-key",
            transport: FakeVolcengineTransport(connection: connection),
            requestID: "request-id",
            connectID: "connect-id"
        )
        let consumer = Task<[TranscriptEvent], Error> {
            try await collect(
                provider.events(audio: finishedAudioStream())
            )
        }

        try await waitForSentFrames(connection, count: 1)
        consumer.cancel()
        _ = await consumer.result
        let closedByCancellation = await waitForConnectionClose(connection)
        if !closedByCancellation {
            connection.close()
        }

        XCTAssertTrue(closedByCancellation)
    }

    func testUnexpectedTransportCloseIsReported() async throws {
        let connection = FakeVolcengineConnection(
            incoming: [.closed],
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
            XCTFail("Expected connection-closed error")
        } catch {
            XCTAssertEqual(error as? VolcengineProviderError, .connectionClosed)
        }
        XCTAssertTrue(connection.closed)
    }
}
