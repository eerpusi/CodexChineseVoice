import AppKit

enum SettingsWindowPresenter {
    static func present(
        activate: () -> Void,
        show: () -> Void
    ) {
        activate()
        show()
    }
}
