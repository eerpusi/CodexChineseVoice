import AppKit
import CodexChineseVoiceCore

@MainActor
enum DockIconController {
    static func apply(_ mode: AppActivationMode) {
        let policy: NSApplication.ActivationPolicy = switch mode {
        case .regular: .regular
        case .accessory: .accessory
        }
        NSApp.setActivationPolicy(policy)
    }
}
