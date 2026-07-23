import XCTest
@testable import CodexChineseVoiceCore

final class ComposerPlaceholderTests: XCTestCase {
    func testPlaceholderOnlyValueIsTreatedAsEmptyComposer() {
        XCTAssertEqual(
            normalizedComposerValue("Work with ChatGPT", placeholder: "Work with ChatGPT"),
            ""
        )
    }

    func testRealTextIsPreservedWhenItDiffersFromPlaceholder() {
        XCTAssertEqual(
            normalizedComposerValue("Work with ChatGPT now", placeholder: "Work with ChatGPT"),
            "Work with ChatGPT now"
        )
    }
}
