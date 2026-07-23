import CodexChineseVoiceCore

extension VoiceApplicationState {
    var menuTitle: String {
        switch self {
        case .starting: "启动中"
        case .ready: "就绪"
        case .needsConfiguration: "需要配置"
        case .needsMicrophonePermission: "需要麦克风权限"
        case .needsAccessibilityPermission: "需要辅助功能权限"
        case .needsInputMonitoringPermission: "需要输入监控权限"
        case .failed: "运行失败"
        }
    }

    var iconName: String {
        switch self {
        case .starting: "ellipsis.circle"
        case .ready: "checkmark.circle"
        case .needsConfiguration: "key"
        case .needsMicrophonePermission: "mic.slash"
        case .needsAccessibilityPermission: "hand.raised"
        case .needsInputMonitoringPermission: "keyboard"
        case .failed: "exclamationmark.triangle"
        }
    }
}
