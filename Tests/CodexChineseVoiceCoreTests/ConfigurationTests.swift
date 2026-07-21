import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class ConfigurationTests: XCTestCase {
    func testEnvironmentAPIKeyOverridesSavedAPIKey() throws {
        let loader = ConfigurationLoader(
            store: StubStore(apiKey: "saved-key"),
            environment: ["ARK_PLAN_API_KEY": "environment-key"]
        )

        XCTAssertEqual(
            try loader.load(),
            AppConfiguration(apiKey: "environment-key")
        )
    }

    func testEmptyEnvironmentAPIKeyFallsBackToSavedAPIKey() throws {
        let loader = ConfigurationLoader(
            store: StubStore(apiKey: "saved-key"),
            environment: ["ARK_PLAN_API_KEY": ""]
        )

        XCTAssertEqual(try loader.load(), AppConfiguration(apiKey: "saved-key"))
    }

    func testMissingAPIKeyThrows() {
        let loader = ConfigurationLoader(
            store: StubStore(apiKey: nil),
            environment: [:]
        )

        XCTAssertThrowsError(try loader.load()) { error in
            XCTAssertEqual(error as? ConfigurationError, .missingAPIKey)
        }
    }

    func testGeneratedTOMLRoundTripsQuotesAndNewlines() throws {
        let location = makeTemporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let store = ConfigFileStore(fileURL: location.file)
        let apiKey = "first \"quoted\"\nsecond"

        try store.saveAPIKey(apiKey)

        let data = try Data(contentsOf: location.file)
        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            "ark_plan_api_key = \"first \\\"quoted\\\"\\nsecond\"\n"
        )
        XCTAssertEqual(try store.loadAPIKey(), apiKey)
    }

    func testLoadingIgnoresBlankAndCommentOnlyLines() throws {
        let location = makeTemporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try FileManager.default.createDirectory(
            at: location.root,
            withIntermediateDirectories: true
        )
        let content = "\n  # local credential\n\nark_plan_api_key = \"saved-key\"\n"
        try Data(content.utf8).write(to: location.file)

        XCTAssertEqual(
            try ConfigFileStore(fileURL: location.file).loadAPIKey(),
            "saved-key"
        )
    }

    func testInvalidFilesThrowInvalidFile() throws {
        let location = makeTemporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try FileManager.default.createDirectory(
            at: location.root,
            withIntermediateDirectories: true
        )
        let invalidDocuments: [Data] = [
            Data("unknown_key = \"value\"\n".utf8),
            Data("ark_plan_api_key = \"first\"\nark_plan_api_key = \"second\"\n".utf8),
            Data("ark_plan_api_key \"value\"\n".utf8),
            Data("# no assignment\n\n".utf8),
            Data("ark_plan_api_key = unquoted\n".utf8),
            Data([0xFF]),
        ]
        let store = ConfigFileStore(fileURL: location.file)

        for document in invalidDocuments {
            try document.write(to: location.file, options: .atomic)
            XCTAssertThrowsError(try store.loadAPIKey()) { error in
                XCTAssertEqual(error as? ConfigurationError, .invalidFile)
            }
        }
    }

    func testUnreadablePathThrowsUnreadableFile() throws {
        let location = makeTemporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try FileManager.default.createDirectory(
            at: location.file,
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(
            try ConfigFileStore(fileURL: location.file).loadAPIKey()
        ) { error in
            XCTAssertEqual(error as? ConfigurationError, .unreadableFile)
        }
    }

    func testSaveAppliesPrivateDirectoryAndFilePermissions() throws {
        let location = makeTemporaryConfigLocation(nested: true)
        defer { try? FileManager.default.removeItem(at: location.root) }
        let store = ConfigFileStore(fileURL: location.file)

        try store.saveAPIKey("saved-key")

        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: location.file.deletingLastPathComponent().path
        )
        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: location.file.path
        )
        let directoryMode = try XCTUnwrap(
            directoryAttributes[.posixPermissions] as? NSNumber
        )
        let fileMode = try XCTUnwrap(
            fileAttributes[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(directoryMode.intValue & 0o777, 0o700)
        XCTAssertEqual(fileMode.intValue & 0o777, 0o600)
    }

    func testDefaultStoreUsesExpectedPath() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("codex-chinese-voice")
            .appendingPathComponent("config.toml")

        XCTAssertEqual(ConfigFileStore.default.fileURL, expected)
    }
}

private struct StubStore: ConfigStoring {
    let apiKey: String?

    func loadAPIKey() throws -> String? {
        apiKey
    }
}

private extension ConfigurationTests {
    func makeTemporaryConfigLocation(
        nested: Bool = false
    ) -> (root: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexChineseVoiceTests-\(UUID().uuidString)")
        let directory = nested ? root.appendingPathComponent("config") : root
        return (root, directory.appendingPathComponent("config.toml"))
    }
}
