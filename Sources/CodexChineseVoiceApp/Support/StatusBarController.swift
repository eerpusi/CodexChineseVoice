import AppKit
import SwiftUI

enum SettingsWindowLayout {
    static let width: CGFloat = 300
    static let apiKeyInputWidth: CGFloat = 100
    static let apiKeyLabel = "Key"
    static let contentAlignment = Alignment.leading
    static let rowHeight: CGFloat = 42
    static let panelSpacing: CGFloat = 0
    static let toggleControlWidth: CGFloat = 38

    static func contentSize(for measuredSize: NSSize) -> NSSize {
        NSSize(width: width, height: ceil(measuredSize.height))
    }
}

enum StatusBarMenuAction: CaseIterable {
    case settings
    case restart
    case quit

    var title: String {
        switch self {
        case .settings: "设置"
        case .restart: "重新启动"
        case .quit: "退出"
        }
    }
}

@MainActor
final class StatusBarController: NSObject {
    static let idleSymbolName = "waveform"

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: VoiceApplicationModel
    private let settingsWindowController: SettingsWindowController
    private lazy var menu = makeMenu()

    init(model: VoiceApplicationModel) {
        self.model = model
        settingsWindowController = SettingsWindowController(model: model)
        super.init()

        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: Self.idleSymbolName,
            accessibilityDescription: "CodexChineseVoice"
        )
        button.image?.isTemplate = true
        button.toolTip = "CodexChineseVoice"
        statusItem.menu = menu
    }

    @objc private func showSettings() {
        settingsWindowController.present()
    }

    @objc private func restart() {
        model.restart()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for action in StatusBarMenuAction.allCases {
            let item = NSMenuItem(title: action.title, action: selector(for: action), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    private func selector(for action: StatusBarMenuAction) -> Selector {
        switch action {
        case .settings: #selector(showSettings)
        case .restart: #selector(restart)
        case .quit: #selector(quit)
        }
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController {
    init(model: VoiceApplicationModel) {
        let hostingController = NSHostingController(rootView: AppSettingsView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        let displayName = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String ?? "CodexChineseVoice"
        window.title = "\(displayName) Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        hostingController.view.layoutSubtreeIfNeeded()
        let contentSize = SettingsWindowLayout.contentSize(
            for: hostingController.view.fittingSize
        )
        window.setContentSize(contentSize)
        window.minSize = contentSize
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        SettingsWindowPresenter.present(
            activate: { NSApp.activate(ignoringOtherApps: true) },
            show: { [weak self] in self?.window?.makeKeyAndOrderFront(nil) }
        )
    }
}
