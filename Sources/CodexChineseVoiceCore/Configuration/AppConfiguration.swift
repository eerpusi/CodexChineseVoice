import Foundation

public struct AppConfiguration: Equatable, Sendable {
    public let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}

public enum ConfigurationError: Error, Equatable {
    case missingAPIKey
    case unreadableFile
    case invalidFile
}

public protocol ConfigStoring {
    func loadAPIKey() throws -> String?
}

public struct ConfigurationLoader<Store: ConfigStoring> {
    private let store: Store
    private let environment: [String: String]

    public init(
        store: Store,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.store = store
        self.environment = environment
    }

    public func load() throws -> AppConfiguration {
        if let apiKey = environment["ARK_PLAN_API_KEY"], !apiKey.isEmpty {
            return AppConfiguration(apiKey: apiKey)
        }

        if let apiKey = try store.loadAPIKey(), !apiKey.isEmpty {
            return AppConfiguration(apiKey: apiKey)
        }

        throw ConfigurationError.missingAPIKey
    }
}
