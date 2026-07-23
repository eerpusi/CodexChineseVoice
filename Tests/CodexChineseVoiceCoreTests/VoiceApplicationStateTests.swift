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
    }

    func testPermissionStateRetriesOnlyAfterRequiredPermissionIsGranted() {
        XCTAssertTrue(
            VoiceApplicationState.needsMicrophonePermission.shouldRetry(
                microphonePermission: .granted,
                accessibilityTrusted: false
            )
        )
        XCTAssertFalse(
            VoiceApplicationState.needsMicrophonePermission.shouldRetry(
                microphonePermission: .denied,
                accessibilityTrusted: true
            )
        )
        XCTAssertTrue(
            VoiceApplicationState.needsAccessibilityPermission.shouldRetry(
                microphonePermission: .granted,
                accessibilityTrusted: true
            )
        )
        XCTAssertFalse(
            VoiceApplicationState.needsAccessibilityPermission.shouldRetry(
                microphonePermission: .granted,
                accessibilityTrusted: false
            )
        )
        XCTAssertFalse(
            VoiceApplicationState.ready.shouldRetry(
                microphonePermission: .granted,
                accessibilityTrusted: true
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
}
