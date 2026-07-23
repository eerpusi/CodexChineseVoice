import Foundation
import AVFAudio
import XCTest
@testable import CodexChineseVoiceCore

final class PermissionPreflightTests: XCTestCase {
    func testGrantedPermissionsNeedNoPrompts() async throws {
        let provider = FakePermissionProvider(
            microphone: .granted,
            requestMicrophoneResult: true,
            accessibilityChecks: [true]
        )

        try await PermissionPreflight(provider: provider).ensureReady()

        XCTAssertEqual(provider.microphoneRequestCount, 0)
        XCTAssertEqual(provider.accessibilityPromptValues, [false])
    }

    func testUndeterminedMicrophoneRequestsPermissionOnce() async throws {
        let provider = FakePermissionProvider(
            microphone: .undetermined,
            requestMicrophoneResult: true,
            accessibilityChecks: [true]
        )

        try await PermissionPreflight(provider: provider).ensureReady()

        XCTAssertEqual(provider.microphoneRequestCount, 1)
        XCTAssertEqual(provider.accessibilityPromptValues, [false])
    }

    func testMissingAccessibilityPermissionPromptsThenReportsRequired() async {
        let provider = FakePermissionProvider(
            microphone: .granted,
            requestMicrophoneResult: true,
            accessibilityChecks: [false, false]
        )

        do {
            try await PermissionPreflight(provider: provider).ensureReady()
            XCTFail("Expected accessibility permission to be required")
        } catch {
            XCTAssertEqual(
                error as? PermissionPreflightError,
                .accessibilityRequired
            )
        }
        XCTAssertEqual(provider.accessibilityPromptValues, [false, true])
    }

    func testAccessibilityPromptCanObserveNewlyGrantedPermission() async throws {
        let provider = FakePermissionProvider(
            microphone: .granted,
            requestMicrophoneResult: true,
            accessibilityChecks: [false, true]
        )

        try await PermissionPreflight(provider: provider).ensureReady()

        XCTAssertEqual(provider.accessibilityPromptValues, [false, true])
    }

    func testMissingInputMonitoringPermissionIsReportedAfterAccessibility() async {
        let provider = FakePermissionProvider(
            microphone: .granted,
            requestMicrophoneResult: true,
            accessibilityChecks: [true],
            inputMonitoringChecks: [false, false]
        )

        do {
            try await PermissionPreflight(provider: provider).ensureReady()
            XCTFail("Expected input monitoring permission to be required")
        } catch {
            XCTAssertEqual(
                error as? PermissionPreflightError,
                .inputMonitoringRequired
            )
            XCTAssertEqual(provider.inputMonitoringPromptValues, [false, true])
        }
    }

    func testDeniedMicrophoneStopsBeforeAccessibilityCheck() async {
        let provider = FakePermissionProvider(
            microphone: .denied,
            requestMicrophoneResult: true,
            accessibilityChecks: [true]
        )

        do {
            try await PermissionPreflight(provider: provider).ensureReady()
            XCTFail("Expected microphone permission to be denied")
        } catch {
            XCTAssertEqual(error as? PermissionPreflightError, .microphoneDenied)
        }
        XCTAssertEqual(provider.microphoneRequestCount, 0)
        XCTAssertTrue(provider.accessibilityPromptValues.isEmpty)
    }

    func testDeniedMicrophoneRequestStopsBeforeAccessibilityCheck() async {
        let provider = FakePermissionProvider(
            microphone: .undetermined,
            requestMicrophoneResult: false,
            accessibilityChecks: [true]
        )

        do {
            try await PermissionPreflight(provider: provider).ensureReady()
            XCTFail("Expected microphone permission to be denied")
        } catch {
            XCTAssertEqual(error as? PermissionPreflightError, .microphoneDenied)
        }
        XCTAssertEqual(provider.microphoneRequestCount, 1)
        XCTAssertTrue(provider.accessibilityPromptValues.isEmpty)
    }

    func testSystemProviderMapsNativeMicrophoneStates() {
        XCTAssertEqual(
            SystemPermissionProvider.map(.granted),
            .granted
        )
        XCTAssertEqual(
            SystemPermissionProvider.map(.denied),
            .denied
        )
        XCTAssertEqual(
            SystemPermissionProvider.map(.undetermined),
            .undetermined
        )
    }

    func testInputMonitoringSettingsURLTargetsPrivacyInputMonitoring() {
        XCTAssertEqual(
            SystemPermissionProvider.inputMonitoringSettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
    }
}

private final class FakePermissionProvider: PermissionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var microphone: MicrophonePermission
    private let requestMicrophoneResult: Bool
    private var accessibilityChecks: [Bool]
    private var inputMonitoringChecks: [Bool]
    private(set) var microphoneRequestCount = 0
    private(set) var accessibilityPromptValues: [Bool] = []
    private(set) var inputMonitoringPromptValues: [Bool] = []

    init(
        microphone: MicrophonePermission,
        requestMicrophoneResult: Bool,
        accessibilityChecks: [Bool],
        inputMonitoringChecks: [Bool] = [true]
    ) {
        self.microphone = microphone
        self.requestMicrophoneResult = requestMicrophoneResult
        self.accessibilityChecks = accessibilityChecks
        self.inputMonitoringChecks = inputMonitoringChecks
    }

    var microphonePermission: MicrophonePermission {
        lock.withLock { microphone }
    }

    func requestMicrophonePermission() async -> Bool {
        lock.withLock {
            microphoneRequestCount += 1
            if requestMicrophoneResult {
                microphone = .granted
            }
        }
        return requestMicrophoneResult
    }

    func isAccessibilityTrusted(prompt: Bool) -> Bool {
        lock.withLock {
            accessibilityPromptValues.append(prompt)
            return accessibilityChecks.isEmpty ? false : accessibilityChecks.removeFirst()
        }
    }

    func isInputMonitoringTrusted(prompt: Bool) -> Bool {
        lock.withLock {
            inputMonitoringPromptValues.append(prompt)
            return inputMonitoringChecks.isEmpty ? false : inputMonitoringChecks.removeFirst()
        }
    }
}
