import XCTest
@testable import CodexChineseVoiceCore

final class APIKeyPresentationTests: XCTestCase {
    func testConfiguredKeyUsesFixedMaskWithoutReadingCredential() {
        XCTAssertEqual(
            APIKeyPresentation.maskedValue(isConfigured: true),
            "********"
        )
    }

    func testMissingKeyHasNoMaskedValue() {
        XCTAssertNil(APIKeyPresentation.maskedValue(isConfigured: false))
    }
}
