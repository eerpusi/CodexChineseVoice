import AppKit
import CodexChineseVoiceCore
import SwiftUI

struct MenuBarContentView: View {
    let model: VoiceApplicationModel

    var body: some View {
        if model.isRecording {
            Label("正在录音", systemImage: "mic.fill")
        } else {
            Label(model.state.menuTitle, systemImage: model.state.iconName)
        }

        if let failureMessage = model.state.failureMessage {
            Text(failureMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let permissionSettings = model.state.permissionSettingsPresentation {
            Text(permissionSettings.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NSWorkspace.shared.open(permissionSettings.url)
            } label: {
                Label(permissionSettings.buttonTitle, systemImage: "arrow.up.forward.app")
            }
        }

        Divider()

        SettingsLink {
            Label("设置...", systemImage: "gearshape")
        }

        Button {
            model.restart()
        } label: {
            Label("重新启动", systemImage: "arrow.clockwise")
        }

        Button {
            NSApp.terminate(nil)
        } label: {
            Label("退出", systemImage: "power")
        }
    }
}
