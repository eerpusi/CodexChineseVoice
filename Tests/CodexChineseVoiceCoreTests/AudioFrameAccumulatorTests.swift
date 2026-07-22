import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class AudioFrameAccumulatorTests: XCTestCase {
    func testAccumulatorEmitsExactTwoHundredMillisecondFrame() {
        var accumulator = AudioFrameAccumulator(frameByteCount: 6_400)

        XCTAssertTrue(
            accumulator.append(Data(repeating: 1, count: 3_200)).isEmpty
        )
        let frames = accumulator.append(Data(repeating: 2, count: 3_200))

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].count, 6_400)
        XCTAssertEqual(frames[0].prefix(3_200), Data(repeating: 1, count: 3_200))
        XCTAssertEqual(frames[0].suffix(3_200), Data(repeating: 2, count: 3_200))
    }

    func testFlushReturnsRemainderAndClearsAccumulator() {
        var accumulator = AudioFrameAccumulator(frameByteCount: 6_400)
        _ = accumulator.append(Data(repeating: 3, count: 6_523))

        XCTAssertEqual(
            accumulator.flush(),
            Data(repeating: 3, count: 123)
        )
        XCTAssertNil(accumulator.flush())
    }

    func testFinishAppendsConverterTailBeforeFlushingRemainder() {
        var accumulator = AudioFrameAccumulator(frameByteCount: 6_400)
        _ = accumulator.append(Data(repeating: 1, count: 6_300))

        let frames = accumulator.finish(
            appending: Data(repeating: 2, count: 200)
        )

        XCTAssertEqual(frames.map(\.count), [6_400, 100])
        XCTAssertEqual(frames[0].suffix(100), Data(repeating: 2, count: 100))
        XCTAssertEqual(frames[1], Data(repeating: 2, count: 100))
        XCTAssertNil(accumulator.flush())
    }

    func testAudioCaptureUsesTwoHundredMillisecondProviderFrames() {
        XCTAssertEqual(AudioCapture.frameByteCount, 6_400)
    }

    func testCaptureStreamKeepsEveryQueuedFrame() async throws {
        let (stream, continuation) = AudioCapture.makeAudioStream()
        for value in UInt8(0)..<UInt8(32) {
            continuation.yield(Data([value]))
        }
        continuation.finish()

        var received: [Data] = []
        for try await frame in stream {
            received.append(frame)
        }

        XCTAssertEqual(received, (UInt8(0)..<UInt8(32)).map { Data([$0]) })
    }
}
