import ApplicationServices
import XCTest
@testable import CodexChineseVoiceCore

final class ComposerLockingTests: XCTestCase {
    func testFinalizationFailureDoesNotLeaveEditorLocked() throws {
        final class FrontmostState {
            var bundleIdentifier = CodexHotkeyMonitor.codexBundleIdentifier
            let processID = getpid()
        }

        let frontmost = FrontmostState()
        let element = AXUIElementCreateApplication(frontmost.processID)
        let editor = CodexComposerEditor(
            frontmostBundleIdentifier: { frontmost.bundleIdentifier },
            frontmostProcessIdentifier: { frontmost.processID },
            accessibilityTrusted: { true },
            compositionSeed: { processID in
                ComposerSeed(
                    element: element,
                    processID: processID,
                    originalValue: "before",
                    originalSelection: NSRange(location: 6, length: 0)
                )
            }
        )

        try editor.begin()
        frontmost.bundleIdentifier = "com.apple.Safari"
        XCTAssertThrowsError(try editor.finalize("after"))

        editor.cancel()
        XCTAssertFalse(editor.isActive)
    }
}
