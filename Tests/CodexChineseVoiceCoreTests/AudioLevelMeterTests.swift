import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class AudioLevelMeterTests: XCTestCase {
    func testSilenceAndEmptyPCMProduceZeroLevel() {
        XCTAssertEqual(AudioLevelMeter.normalizedLevel(pcm16LE: Data()), 0)
        XCTAssertEqual(
            AudioLevelMeter.normalizedLevel(
                pcm16LE: pcmData(repeating: 0, count: 64)
            ),
            0
        )
    }

    func testFullScalePCMProducesMaximumLevel() {
        XCTAssertEqual(
            AudioLevelMeter.normalizedLevel(
                pcm16LE: pcmData(repeating: .max, count: 64)
            ),
            1,
            accuracy: 0.0001
        )
    }

    func testTenPercentAmplitudeProducesVisibleMidrangeLevel() {
        XCTAssertEqual(
            AudioLevelMeter.normalizedLevel(
                pcm16LE: pcmData(repeating: 3_277, count: 64)
            ),
            0.6,
            accuracy: 0.01
        )
    }
}

private extension AudioLevelMeterTests {
    func pcmData(repeating sample: Int16, count: Int) -> Data {
        var data = Data()
        data.reserveCapacity(count * MemoryLayout<Int16>.size)
        for _ in 0..<count {
            var littleEndian = sample.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }
}
