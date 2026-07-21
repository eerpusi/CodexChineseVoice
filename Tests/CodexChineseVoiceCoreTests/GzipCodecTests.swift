import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class GzipCodecTests: XCTestCase {
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
}
