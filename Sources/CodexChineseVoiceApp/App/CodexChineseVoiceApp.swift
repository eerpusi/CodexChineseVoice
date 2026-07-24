import SwiftUI

@main
struct CodexChineseVoiceApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self)
    private var applicationDelegate

    var body: some Scene {
        Settings {
            AppSettingsView(model: applicationDelegate.model)
        }
    }
}
