import Foundation

public enum AppActivationMode: Equatable, Sendable {
    case regular
    case accessory
}

public struct AppPresentationPreferences: Equatable, Sendable {
    public static let showsDockIconKey = "showsDockIcon"

    public var showsDockIcon: Bool

    public init(showsDockIcon: Bool = true) {
        self.showsDockIcon = showsDockIcon
    }

    public var activationMode: AppActivationMode {
        showsDockIcon ? .regular : .accessory
    }

    public static func load(
        from defaults: UserDefaults = .standard
    ) -> AppPresentationPreferences {
        let showsDockIcon = defaults.object(forKey: showsDockIconKey) == nil
            ? true
            : defaults.bool(forKey: showsDockIconKey)
        return AppPresentationPreferences(showsDockIcon: showsDockIcon)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(showsDockIcon, forKey: Self.showsDockIconKey)
    }
}
