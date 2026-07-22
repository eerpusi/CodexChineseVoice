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

    func testCapturedCommandRConsumesAutoRepeatUntilKeyUp() throws {
        let monitor = CodexHotkeyMonitor {
            CodexHotkeyMonitor.codexBundleIdentifier
        }
        let keyDown = try keyboardEvent(keyDown: true)
        XCTAssertNil(monitor.handle(type: .keyDown, event: keyDown))

        let repeatedKeyDown = try keyboardEvent(keyDown: true, isAutoRepeat: true)
        XCTAssertNil(monitor.handle(type: .keyDown, event: repeatedKeyDown))

        let keyUp = try keyboardEvent(keyDown: false)
        XCTAssertNil(monitor.handle(type: .keyUp, event: keyUp))
    }

    private func keyboardEvent(
        keyDown: Bool,
        isAutoRepeat: Bool = false
    ) throws -> CGEvent {
        let event = try XCTUnwrap(
            CGEvent(
                keyboardEventSource: nil,
                virtualKey: CodexHotkeyMonitor.commandRKeyCode,
                keyDown: keyDown
            )
        )
        event.flags = [.maskCommand]
        event.setIntegerValueField(
            .keyboardEventAutorepeat,
            value: isAutoRepeat ? 1 : 0
        )
        return event
    }
}
