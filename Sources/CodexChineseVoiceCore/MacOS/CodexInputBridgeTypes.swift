import Foundation

/// Errors shared by the event and Accessibility bridges.
public enum CodexInputBridgeError: Error, LocalizedError, Equatable, Sendable {
    case accessibilityPermissionDenied
    case eventTapUnavailable
    case eventTapSetupFailed
    case codexNotFrontmost
    case noFocusedComposer
    case focusedElementNotEditable
    case ambiguousComposerValue
    case accessibilityFailure(Int32)
    case invalidSelectionRange
    case textChangedExternally
    case noActiveComposition
    case autoSubmitUnavailable

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            "需要辅助功能权限"
        case .eventTapUnavailable:
            "无法创建全局快捷键监听器"
        case .eventTapSetupFailed:
            "无法启动全局快捷键监听器"
        case .codexNotFrontmost:
            "请先将 ChatGPT 置于前台"
        case .noFocusedComposer:
            "请先在 ChatGPT 中点击消息输入框"
        case .focusedElementNotEditable:
            "当前焦点不是可编辑的 ChatGPT 输入框"
        case .ambiguousComposerValue:
            "无法确认输入框是否为空，已停止写入以保护现有内容"
        case let .accessibilityFailure(status):
            "读取 ChatGPT 输入框失败（辅助功能错误 \(status)）"
        case .invalidSelectionRange:
            "无法读取 ChatGPT 输入框的光标位置"
        case .textChangedExternally:
            "ChatGPT 输入框内容已发生变化，请重新开始录音"
        case .noActiveComposition:
            "当前没有可编辑的语音会话"
        case .autoSubmitUnavailable:
            "无法创建自动发送按键事件"
        }
    }
}
