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
    case keychainAccessFailed
}

public protocol CredentialStoring: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey() throws
}

public typealias ConfigStoring = CredentialStoring

public struct EmptyConfigStore: CredentialStoring {
    public init() {}

    public func loadAPIKey() throws -> String? {
        nil
    }

    public func saveAPIKey(_ apiKey: String) throws {}

    public func deleteAPIKey() throws {}
}

public struct ConfigurationLoader<Keychain: CredentialStoring, Legacy: CredentialStoring> {
    private let keychain: Keychain
    private let legacy: Legacy
    private let environment: [String: String]

    public init(
        keychain: Keychain,
        legacy: Legacy,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.keychain = keychain
        self.legacy = legacy
        self.environment = environment
    }

    public func load() throws -> AppConfiguration {
        if let apiKey = environment["ARK_PLAN_API_KEY"], !apiKey.isEmpty {
            return AppConfiguration(apiKey: apiKey)
        }

        if let apiKey = try keychain.loadAPIKey(), !apiKey.isEmpty {
            return AppConfiguration(apiKey: apiKey)
        }

        if let apiKey = try legacy.loadAPIKey(), !apiKey.isEmpty {
            try keychain.saveAPIKey(apiKey)
            try legacy.deleteAPIKey()
            return AppConfiguration(apiKey: apiKey)
        }

        throw ConfigurationError.missingAPIKey
    }
}

public extension ConfigurationLoader where Keychain == EmptyConfigStore {
    init(
        store: Legacy,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.init(
            keychain: EmptyConfigStore(),
            legacy: store,
            environment: environment
        )
    }
}
