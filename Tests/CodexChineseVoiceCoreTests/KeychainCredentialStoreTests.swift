import Foundation
import Security
import XCTest
@testable import CodexChineseVoiceCore

final class KeychainCredentialStoreTests: XCTestCase {
    func testMissingKeychainItemLoadsAsNil() throws {
        let client = FakeKeychainSecurityClient(copyStatus: errSecItemNotFound)
        let store = KeychainCredentialStore(client: client)

        XCTAssertNil(try store.loadAPIKey())
        XCTAssertEqual(client.copiedService, KeychainCredentialStore.service)
        XCTAssertEqual(client.copiedAccount, KeychainCredentialStore.account)
    }

    func testSaveAddsNewKeychainItem() throws {
        let client = FakeKeychainSecurityClient(addStatus: errSecSuccess)
        let store = KeychainCredentialStore(client: client)

        try store.saveAPIKey("synthetic-key")

        XCTAssertEqual(client.addedData, Data("synthetic-key".utf8))
        XCTAssertEqual(client.updatedData, nil)
    }

    func testSaveUpdatesDuplicateKeychainItem() throws {
        let client = FakeKeychainSecurityClient(
            addStatus: errSecDuplicateItem,
            updateStatus: errSecSuccess
        )
        let store = KeychainCredentialStore(client: client)

        try store.saveAPIKey("synthetic-key")

        XCTAssertEqual(client.updatedData, Data("synthetic-key".utf8))
    }

    func testDeleteTreatsMissingKeychainItemAsSuccess() throws {
        let client = FakeKeychainSecurityClient(deleteStatus: errSecItemNotFound)
        let store = KeychainCredentialStore(client: client)

        XCTAssertNoThrow(try store.deleteAPIKey())
    }

    func testUnexpectedKeychainStatusThrowsAccessFailure() {
        let client = FakeKeychainSecurityClient(copyStatus: errSecAuthFailed)
        let store = KeychainCredentialStore(client: client)

        XCTAssertThrowsError(try store.loadAPIKey()) { error in
            XCTAssertEqual(error as? ConfigurationError, .keychainAccessFailed)
        }
    }
}

private final class FakeKeychainSecurityClient: KeychainSecurityClient, @unchecked Sendable {
    let copyStatus: Int32
    let copyData: Data?
    let addStatus: Int32
    let updateStatus: Int32
    let deleteStatus: Int32

    private(set) var copiedService: String?
    private(set) var copiedAccount: String?
    private(set) var addedData: Data?
    private(set) var updatedData: Data?

    init(
        copyStatus: Int32 = errSecSuccess,
        copyData: Data? = nil,
        addStatus: Int32 = errSecSuccess,
        updateStatus: Int32 = errSecSuccess,
        deleteStatus: Int32 = errSecSuccess
    ) {
        self.copyStatus = copyStatus
        self.copyData = copyData
        self.addStatus = addStatus
        self.updateStatus = updateStatus
        self.deleteStatus = deleteStatus
    }

    func copyMatching(service: String, account: String) -> (Int32, Data?) {
        copiedService = service
        copiedAccount = account
        return (copyStatus, copyData)
    }

    func add(data: Data, service: String, account: String) -> Int32 {
        addedData = data
        return addStatus
    }

    func update(data: Data, service: String, account: String) -> Int32 {
        updatedData = data
        return updateStatus
    }

    func delete(service: String, account: String) -> Int32 {
        deleteStatus
    }
}
