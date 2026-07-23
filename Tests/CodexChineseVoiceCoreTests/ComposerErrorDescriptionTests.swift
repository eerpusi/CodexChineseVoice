import ApplicationServices
import XCTest
@testable import CodexChineseVoiceCore

final class ComposerErrorDescriptionTests: XCTestCase {
    func testMissingFocusedComposerExplainsTheRequiredAction() {
        XCTAssertEqual(
            CodexInputBridgeError.noFocusedComposer.localizedDescription,
            "请先在 ChatGPT 中点击消息输入框"
        )
    }

    func testNonEditableFocusedElementExplainsTheRequiredAction() {
        XCTAssertEqual(
            CodexInputBridgeError.focusedElementNotEditable.localizedDescription,
            "当前焦点不是可编辑的 ChatGPT 输入框"
        )
    }

    func testAccessibilityNoValueMapsToMissingFocusedComposer() {
        XCTAssertEqual(
            CodexAccessibilityErrorMapping.map(
                status: .noValue,
                missing: .noFocusedComposer
            ),
            .noFocusedComposer
        )
    }

    func testAccessibilityUnsupportedAttributeUsesContextualMissingError() {
        XCTAssertEqual(
            CodexAccessibilityErrorMapping.map(
                status: .attributeUnsupported,
                missing: .focusedElementNotEditable
            ),
            .focusedElementNotEditable
        )
    }
}
