import AppKit
import CodexChineseVoiceCore

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let model = VoiceApplicationModel()
    private var workspaceActivationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = AppPresentationPreferences.load()
        DockIconController.apply(preferences.activationMode)
        model.start()
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            Task { @MainActor in
                model?.retryPermissionsIfReady()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                workspaceActivationObserver
            )
        }
        model.stop()
    }
}
