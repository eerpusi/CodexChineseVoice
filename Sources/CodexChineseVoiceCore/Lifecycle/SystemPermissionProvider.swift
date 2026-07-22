import ApplicationServices
@preconcurrency import AVFAudio

public final class SystemPermissionProvider: PermissionProviding, @unchecked Sendable {
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
