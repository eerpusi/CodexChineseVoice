import Foundation
import Security

protocol KeychainSecurityClient: Sendable {
    func copyMatching(service: String, account: String) -> (Int32, Data?)
    func add(data: Data, service: String, account: String) -> Int32
    func update(data: Data, service: String, account: String) -> Int32
    func delete(service: String, account: String) -> Int32
}

public struct KeychainCredentialStore: ConfigStoring, Sendable {
    static let service = "com.lianenguang.CodexChineseVoice"
    static let account = "ARK_PLAN_API_KEY"

    public static let `default` = KeychainCredentialStore()

    private let client: any KeychainSecurityClient

    public init() {
        self.init(client: SystemKeychainSecurityClient())
    }

    init(client: any KeychainSecurityClient) {
        self.client = client
    }

    public func loadAPIKey() throws -> String? {
        let result = client.copyMatching(service: Self.service, account: Self.account)
        switch result.0 {
        case errSecSuccess:
            guard let data = result.1, let apiKey = String(data: data, encoding: .utf8) else {
                throw ConfigurationError.keychainAccessFailed
            }
            return apiKey
        case errSecItemNotFound:
            return nil
        default:
            throw ConfigurationError.keychainAccessFailed
        }
    }

    public func saveAPIKey(_ apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let status = client.add(data: data, service: Self.service, account: Self.account)
        if status == errSecSuccess {
            return
        }
        guard status == errSecDuplicateItem else {
            throw ConfigurationError.keychainAccessFailed
        }
        guard client.update(data: data, service: Self.service, account: Self.account) == errSecSuccess else {
            throw ConfigurationError.keychainAccessFailed
        }
    }

    public func deleteAPIKey() throws {
        let status = client.delete(service: Self.service, account: Self.account)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ConfigurationError.keychainAccessFailed
        }
    }
}

private struct SystemKeychainSecurityClient: KeychainSecurityClient {
    func copyMatching(service: String, account: String) -> (Int32, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query(service: service, account: account, returnData: true) as CFDictionary,
            &result
        )
        return (status, result as? Data)
    }

    func add(data: Data, service: String, account: String) -> Int32 {
        var query = query(service: service, account: account)
        query[kSecValueData] = data
        return SecItemAdd(query as CFDictionary, nil)
    }

    func update(data: Data, service: String, account: String) -> Int32 {
        SecItemUpdate(
            query(service: service, account: account) as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
    }

    func delete(service: String, account: String) -> Int32 {
        SecItemDelete(query(service: service, account: account) as CFDictionary)
    }

    private func query(
        service: String,
        account: String,
        returnData: Bool = false
    ) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        if returnData {
            query[kSecReturnData] = true
            query[kSecMatchLimit] = kSecMatchLimitOne
        }
        return query
    }
}
