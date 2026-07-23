import SwiftUI

@main
struct CodexChineseVoiceApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self)
    private var applicationDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: applicationDelegate.model)
        } label: {
            MenuBarInputLevelView(
                isRecording: applicationDelegate.model.isRecording,
                level: applicationDelegate.model.inputLevel
            )
        }

        Settings {
            AppSettingsView(model: applicationDelegate.model)
        }
    }
}
