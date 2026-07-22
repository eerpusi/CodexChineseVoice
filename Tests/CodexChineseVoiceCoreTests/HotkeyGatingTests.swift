import CoreGraphics
import XCTest
@testable import CodexChineseVoiceCore

final class HotkeyGatingTests: XCTestCase {
    func testOnlyCodexCommandRMatches() {
        XCTAssertTrue(
            CodexHotkeyMonitor.matchesCommandR(
                bundleIdentifier: CodexHotkeyMonitor.codexBundleIdentifier,
                keyCode: CodexHotkeyMonitor.commandRKeyCode,
                flags: [.maskCommand]
            )
        )
        XCTAssertFalse(
            CodexHotkeyMonitor.matchesCommandR(
                bundleIdentifier: "com.apple.Terminal",
                keyCode: CodexHotkeyMonitor.commandRKeyCode,
                flags: [.maskCommand]
            )
        )
    }

    func testModifiedOrRepeatedCommandRDoesNotMatch() {
        let bundle = CodexHotkeyMonitor.codexBundleIdentifier
        let key = CodexHotkeyMonitor.commandRKeyCode

        XCTAssertFalse(
            CodexHotkeyMonitor.matchesCommandR(
                bundleIdentifier: bundle,
                keyCode: key,
                flags: [.maskCommand, .maskShift]
            )
        )
        XCTAssertFalse(
            CodexHotkeyMonitor.matchesCommandR(
                bundleIdentifier: bundle,
                keyCode: key,
                flags: [.maskCommand],
                isAutoRepeat: true
            )
        )
    }
}
