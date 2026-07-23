public enum VoiceApplicationFailure: Equatable, Sendable {
    case configurationUnreadable
    case configurationInvalid
    case runtime(String)
}

public enum VoiceApplicationState: Equatable, Sendable {
    case starting
    case ready
    case needsConfiguration
    case needsMicrophonePermission
    case needsAccessibilityPermission
    case failed(VoiceApplicationFailure)

    public var failureMessage: String? {
        switch self {
        case .failed(.configurationUnreadable):
            "无法读取配置文件"
        case .failed(.configurationInvalid):
            "配置文件格式无效"
        case let .failed(.runtime(message)):
            message
        default:
            nil
        }
    }

    public static func from(
        _ error: ConfigurationError
    ) -> VoiceApplicationState {
        switch error {
        case .missingAPIKey:
            .needsConfiguration
        case .unreadableFile:
            .failed(.configurationUnreadable)
        case .invalidFile:
            .failed(.configurationInvalid)
        }
    }

    public static func from(
        _ error: PermissionPreflightError
    ) -> VoiceApplicationState {
        switch error {
        case .microphoneDenied:
            .needsMicrophonePermission
        case .accessibilityRequired:
            .needsAccessibilityPermission
        }
    }

    public func shouldRetry(
        microphonePermission: MicrophonePermission,
        accessibilityTrusted: Bool
    ) -> Bool {
        switch self {
        case .needsMicrophonePermission:
            microphonePermission == .granted
        case .needsAccessibilityPermission:
            accessibilityTrusted
        default:
            false
        }
    }
}
