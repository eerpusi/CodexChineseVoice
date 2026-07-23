import Foundation

public enum AppActivationMode: Equatable, Sendable {
    case regular
    case accessory
}

public struct AppPresentationPreferences: Equatable, Sendable {
    public static let showsDockIconKey = "showsDockIcon"
    public static let autoSendsTranscriptionKey = "autoSendsTranscription"

    public var showsDockIcon: Bool
    public var autoSendsTranscription: Bool

    public init(
        showsDockIcon: Bool = true,
        autoSendsTranscription: Bool = true
    ) {
        self.showsDockIcon = showsDockIcon
        self.autoSendsTranscription = autoSendsTranscription
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
        let autoSendsTranscription = defaults.object(
            forKey: autoSendsTranscriptionKey
        ) == nil
            ? true
            : defaults.bool(forKey: autoSendsTranscriptionKey)
        return AppPresentationPreferences(
            showsDockIcon: showsDockIcon,
            autoSendsTranscription: autoSendsTranscription
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(showsDockIcon, forKey: Self.showsDockIconKey)
        defaults.set(
            autoSendsTranscription,
            forKey: Self.autoSendsTranscriptionKey
        )
    }
}
