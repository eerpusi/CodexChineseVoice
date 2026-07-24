import XCTest
@testable import CodexChineseVoiceCore

final class PermissionSettingsPresentationTests: XCTestCase {
    func testMicrophonePermissionStateOpensMicrophoneSettings() {
        let presentation = VoiceApplicationState.needsMicrophonePermission
            .permissionSettingsPresentation

        XCTAssertEqual(presentation?.message, "要录制语音，需要允许本应用访问麦克风。")
        XCTAssertEqual(presentation?.buttonTitle, "打开麦克风设置")
        XCTAssertEqual(presentation?.url, SystemPermissionProvider.microphoneSettingsURL)
    }

    func testAccessibilityPermissionStateOpensAccessibilitySettings() {
        let presentation = VoiceApplicationState.needsAccessibilityPermission
            .permissionSettingsPresentation

        XCTAssertEqual(presentation?.message, "要把转写内容写入 Codex，需要允许本应用使用辅助功能。")
        XCTAssertEqual(presentation?.buttonTitle, "打开辅助功能设置")
        XCTAssertEqual(presentation?.url, SystemPermissionProvider.accessibilitySettingsURL)
    }

    func testInputMonitoringPermissionStateOpensInputMonitoringSettings() {
        let presentation = VoiceApplicationState.needsInputMonitoringPermission
            .permissionSettingsPresentation

        XCTAssertEqual(presentation?.message, "要监听 Codex 中的 Command+R，需要允许本应用访问全局键盘事件。")
        XCTAssertEqual(presentation?.buttonTitle, "打开输入监控设置")
        XCTAssertEqual(presentation?.url, SystemPermissionProvider.inputMonitoringSettingsURL)
    }

    func testReadyStateDoesNotShowPermissionSettingsAction() {
        XCTAssertNil(VoiceApplicationState.ready.permissionSettingsPresentation)
    }
}
