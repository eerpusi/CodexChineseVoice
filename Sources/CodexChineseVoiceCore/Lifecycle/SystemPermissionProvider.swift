import ApplicationServices
@preconcurrency import AVFAudio
import CoreGraphics
import Foundation

public final class SystemPermissionProvider: PermissionProviding, @unchecked Sendable {
    public static let inputMonitoringSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    )!

    public init() {}

    public var microphonePermission: MicrophonePermission {
        Self.map(AVAudioApplication.shared.recordPermission)
    }

    public func requestMicrophonePermission() async -> Bool {
        await AudioCapture.requestMicrophonePermission()
    }

    public func isAccessibilityTrusted(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func isInputMonitoringTrusted(prompt: Bool) -> Bool {
        if prompt {
            return CGRequestListenEventAccess()
        }
        return CGPreflightListenEventAccess()
    }

    static func map(_ permission: AVAudioApplication.recordPermission) -> MicrophonePermission {
        switch permission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .undetermined
        @unknown default:
            return .denied
        }
    }
}
