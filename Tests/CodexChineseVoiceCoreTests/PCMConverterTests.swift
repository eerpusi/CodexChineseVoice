import AVFAudio
import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class PCMConverterTests: XCTestCase {
    func testConverterProducesMonoInt16DataAtSixteenKilohertz() throws {
        let inputFormat = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let outputFormat = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: true
            )
        )
        let converter = try PCMConverter(
            inputFormat: inputFormat,
            outputFormat: outputFormat
        )
        let input = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_410)
        )
        input.frameLength = 4_410
        input.floatChannelData?.pointee.initialize(repeating: 0.25, count: 4_410)

        let data = try XCTUnwrap(converter.convert(input))

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertLessThanOrEqual(data.count, 3_200)
        XCTAssertEqual(data.count % MemoryLayout<Int16>.size, 0)
        XCTAssertTrue(data.contains { $0 != 0 })
    }

    func testFinishDrainsResamplerTail() throws {
        let inputFormat = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let outputFormat = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: true
            )
        )
        let converter = try PCMConverter(
            inputFormat: inputFormat,
            outputFormat: outputFormat
        )
        let input = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_410)
        )
        input.frameLength = 4_410
        input.floatChannelData?.pointee.initialize(repeating: 0.25, count: 4_410)

        let converted = try converter.convert(input) ?? Data()
        let tail = try converter.finish() ?? Data()

        XCTAssertGreaterThan(tail.count, 0)
        XCTAssertLessThan(abs(converted.count + tail.count - 3_200), 128)
    }

    func testConverterMixesStereoInputToOneChannel() throws {
        let inputFormat = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
        )
        let outputFormat = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: true
            )
        )
        let converter = try PCMConverter(
            inputFormat: inputFormat,
            outputFormat: outputFormat
        )
        let input = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_410)
        )
        input.frameLength = 4_410
        if let channels = input.floatChannelData {
            channels[0].initialize(repeating: 0.25, count: 4_410)
            channels[1].initialize(repeating: -0.25, count: 4_410)
        }

        let data = try XCTUnwrap(converter.convert(input))

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(data.count % MemoryLayout<Int16>.size, 0)
    }
}
