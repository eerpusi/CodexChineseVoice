import XCTest
@testable import CodexChineseVoiceCore

final class AccessibilityComposerSearchTests: XCTestCase {
    func testPrefersEditableTextDescendantOverFocusedContainer() {
        let candidates = [
            ComposerAccessibilityCandidate(
                role: "AXGroup",
                isEditable: false,
                supportsValue: false,
                supportsSelection: false,
                isFocused: true
            ),
            ComposerAccessibilityCandidate(
                role: "AXTextArea",
                isEditable: true,
                supportsValue: true,
                supportsSelection: true,
                isFocused: true
            ),
        ]

        XCTAssertEqual(selectComposerCandidate(candidates), 1)
    }

    func testFallsBackToUsableComposerWhenFocusFlagIsUnavailable() {
        let candidates = [
            ComposerAccessibilityCandidate(
                role: "AXTextArea",
                isEditable: true,
                supportsValue: true,
                supportsSelection: true,
                isFocused: false
            ),
        ]

        XCTAssertEqual(selectComposerCandidate(candidates), 0)
    }

    func testPrefersFocusedUsableComposerOverEarlierUnfocusedCandidate() {
        let candidates = [
            ComposerAccessibilityCandidate(
                role: "AXTextArea",
                isEditable: true,
                supportsValue: true,
                supportsSelection: true,
                isFocused: false
            ),
            ComposerAccessibilityCandidate(
                role: "AXTextArea",
                isEditable: true,
                supportsValue: true,
                supportsSelection: true,
                isFocused: true
            ),
        ]

        XCTAssertEqual(selectComposerCandidate(candidates), 1)
    }
}
