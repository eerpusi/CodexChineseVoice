import XCTest
@testable import CodexChineseVoiceCore

final class VoiceApplicationStateTests: XCTestCase {
    func testConfigurationErrorsMapToRecoverableOrFailedStates() {
        XCTAssertEqual(
            VoiceApplicationState.from(.missingAPIKey),
            .needsConfiguration
        )
        XCTAssertEqual(
            VoiceApplicationState.from(.unreadableFile),
            .failed(.configurationUnreadable)
        )
        XCTAssertEqual(
            VoiceApplicationState.from(.invalidFile),
            .failed(.configurationInvalid)
        )
        XCTAssertEqual(
            VoiceApplicationState.from(.keychainAccessFailed),
            .failed(.configurationKeychainUnavailable)
        )
    }

    func testPermissionErrorsMapToTheirRequiredActions() {
        XCTAssertEqual(
            VoiceApplicationState.from(.microphoneDenied),
            .needsMicrophonePermission
        )
        XCTAssertEqual(
            VoiceApplicationState.from(.accessibilityRequired),
            .needsAccessibilityPermission
        )
        XCTAssertEqual(
            VoiceApplicationState.from(.inputMonitoringRequired),
            .needsInputMonitoringPermission
        )
    }

    func testPermissionStateRetriesOnlyAfterRequiredPermissionIsGranted() {
        XCTAssertTrue(
            VoiceApplicationState.needsMicrophonePermission.shouldRetry(
                microphonePermission: .granted,
                accessibilityTrusted: false,
                inputMonitoringTrusted: false
            )
        )
        XCTAssertFalse(
            VoiceApplicationState.needsMicrophonePermission.shouldRetry(
                microphonePermission: .denied,
                accessibilityTrusted: true,
                inputMonitoringTrusted: true
            )
        )
        XCTAssertTrue(
            VoiceApplicationState.needsAccessibilityPermission.shouldRetry(
                microphonePermission: .granted,
                accessibilityTrusted: true,
                inputMonitoringTrusted: false
            )
        )
        XCTAssertFalse(
            VoiceApplicationState.needsAccessibilityPermission.shouldRetry(
                microphonePermission: .granted,
                accessibilityTrusted: false,
                inputMonitoringTrusted: true
            )
        )
        XCTAssertTrue(
            VoiceApplicationState.needsInputMonitoringPermission.shouldRetry(
                microphonePermission: .granted,
                accessibilityTrusted: true,
                inputMonitoringTrusted: true
            )
        )
        XCTAssertFalse(
            VoiceApplicationState.needsInputMonitoringPermission.shouldRetry(
                microphonePermission: .granted,
                accessibilityTrusted: true,
                inputMonitoringTrusted: false
            )
        )
        XCTAssertFalse(
            VoiceApplicationState.ready.shouldRetry(
                microphonePermission: .granted,
                accessibilityTrusted: true,
                inputMonitoringTrusted: true
            )
        )
    }

    func testFailureMessageExposesRuntimeReasonOnlyForFailedState() {
        XCTAssertEqual(
            VoiceApplicationState.failed(.runtime("请点击输入框"))
                .failureMessage,
            "请点击输入框"
        )
        XCTAssertNil(VoiceApplicationState.ready.failureMessage)
    }

    func testRecordingStartRecoversOnlyRuntimeFailure() {
        XCTAssertEqual(
            VoiceApplicationState.failed(.runtime("连接已关闭"))
                .recoveringForRecordingStart(),
            .ready
        )
        XCTAssertEqual(
            VoiceApplicationState.failed(.configurationInvalid)
                .recoveringForRecordingStart(),
            .failed(.configurationInvalid)
        )
        XCTAssertEqual(
            VoiceApplicationState.needsAccessibilityPermission
                .recoveringForRecordingStart(),
            .needsAccessibilityPermission
        )
    }
}
