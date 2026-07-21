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

    func testGeneratedTOMLRoundTripsSlashesWithoutInvalidEscape() throws {
        let location = makeTemporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let store = ConfigFileStore(fileURL: location.file)
        let apiKey = "synthetic/path/with/slashes"

        try store.saveAPIKey(apiKey)

        let data = try Data(contentsOf: location.file)
        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            "ark_plan_api_key = \"synthetic/path/with/slashes\"\n"
        )
        XCTAssertEqual(try store.loadAPIKey(), apiKey)
    }

    func testTOMLStandardAndUnicodeEscapesAreAccepted() throws {
        let location = makeTemporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try FileManager.default.createDirectory(
            at: location.root,
            withIntermediateDirectories: true
        )
        let content = Data(
            Array("ark_plan_api_key = \"a".utf8)
                + [0x5C, 0x62]
                + Array("b".utf8)
                + [0x5C, 0x66]
                + Array("c".utf8)
                + [0x5C, 0x55]
                + Array("0001F642".utf8)
                + [0x5C, 0x5C]
                + Array("U0001F642\"\n".utf8)
        )
        try writePrivateFixture(content, to: location.file)

        XCTAssertEqual(
            try ConfigFileStore(fileURL: location.file).loadAPIKey(),
            "a\u{8}b\u{C}c🙂\\U0001F642"
        )
    }

    func testLoadingIgnoresBlankAndCommentOnlyLines() throws {
        let location = makeTemporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try FileManager.default.createDirectory(
            at: location.root,
            withIntermediateDirectories: true
        )
        let content = "\n  # local credential\n\nark_plan_api_key = \"saved-key\"\n"
        try writePrivateFixture(Data(content.utf8), to: location.file)

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
            Data(
                Array("ark_plan_api_key = \"a".utf8)
                    + [0x5C, 0x2F]
                    + Array("b\"\n".utf8)
            ),
            Data([0xFF]),
        ]
        let store = ConfigFileStore(fileURL: location.file)

        for document in invalidDocuments {
            try writePrivateFixture(document, to: location.file)
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

    func testExistingUnreadableFileThrowsUnreadableFile() throws {
        let location = makeTemporaryConfigLocation()
        try FileManager.default.createDirectory(
            at: location.root,
            withIntermediateDirectories: true
        )
        try writePrivateFixture(
            Data("ark_plan_api_key = \"synthetic-key\"\n".utf8),
            to: location.file
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: location.root.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: location.root.path
            )
            try? FileManager.default.removeItem(at: location.root)
        }

        XCTAssertThrowsError(
            try ConfigFileStore(fileURL: location.file).loadAPIKey()
        ) { error in
            XCTAssertEqual(error as? ConfigurationError, .unreadableFile)
        }
    }

    func testValidEnvironmentAPIKeyDoesNotInvokeStore() throws {
        let store = ThrowingStore()
        let loader = ConfigurationLoader(
            store: store,
            environment: ["ARK_PLAN_API_KEY": "environment-key"]
        )

        XCTAssertEqual(
            try loader.load(),
            AppConfiguration(apiKey: "environment-key")
        )
        XCTAssertEqual(store.loadCount, 0)
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

private final class ThrowingStore: ConfigStoring {
    enum Failure: Error {
        case storeShouldNotBeCalled
    }

    private(set) var loadCount = 0

    func loadAPIKey() throws -> String? {
        loadCount += 1
        throw Failure.storeShouldNotBeCalled
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

    func writePrivateFixture(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
