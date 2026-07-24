import Foundation

public struct PermissionSettingsPresentation: Equatable, Sendable {
    public let message: String
    public let buttonTitle: String
    public let url: URL
}

extension VoiceApplicationState {
    public var permissionSettingsPresentation: PermissionSettingsPresentation? {
        switch self {
        case .needsMicrophonePermission:
            PermissionSettingsPresentation(
                message: "要录制语音，需要允许本应用访问麦克风。",
                buttonTitle: "打开麦克风设置",
                url: SystemPermissionProvider.microphoneSettingsURL
            )
        case .needsAccessibilityPermission:
            PermissionSettingsPresentation(
                message: "要把转写内容写入 Codex，需要允许本应用使用辅助功能。",
                buttonTitle: "打开辅助功能设置",
                url: SystemPermissionProvider.accessibilitySettingsURL
            )
        case .needsInputMonitoringPermission:
            PermissionSettingsPresentation(
                message: "要监听 Codex 中的 Command+R，需要允许本应用访问全局键盘事件。",
                buttonTitle: "打开输入监控设置",
                url: SystemPermissionProvider.inputMonitoringSettingsURL
            )
        default:
            nil
        }
    }
}
