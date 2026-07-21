import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class ConfigurationSecurityTests: XCTestCase {
    func testSaveAppliesPrivateDirectoryAndFilePermissions() throws {
        let location = makeTemporaryConfigLocation(nested: true)
        defer { try? FileManager.default.removeItem(at: location.root) }

        try ConfigFileStore(fileURL: location.file).saveAPIKey("saved-key")

        XCTAssertEqual(
            try permissions(at: location.file.deletingLastPathComponent()),
            0o700
        )
        XCTAssertEqual(try permissions(at: location.file), 0o600)
    }

    func testSavePreservesPreExistingDirectoryPermissions() throws {
        let location = makeTemporaryConfigLocation(nested: true)
        defer { try? FileManager.default.removeItem(at: location.root) }
        try FileManager.default.createDirectory(
            at: location.root,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: location.root.path
        )

        try ConfigFileStore(fileURL: location.file).saveAPIKey("synthetic-key")

        XCTAssertEqual(try permissions(at: location.root), 0o755)
        XCTAssertEqual(
            try permissions(at: location.file.deletingLastPathComponent()),
            0o700
        )
        XCTAssertEqual(try permissions(at: location.file), 0o600)
    }

    func testSaveRejectsSymlinkedDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexChineseVoiceTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = FileManager.default
        let realDirectory = root.appendingPathComponent("real")
        let symlinkDirectory = root.appendingPathComponent("link")
        try fileManager.createDirectory(
            at: realDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: realDirectory.path
        )
        try fileManager.createSymbolicLink(
            at: symlinkDirectory,
            withDestinationURL: realDirectory
        )
        let linkedFile = symlinkDirectory.appendingPathComponent("config.toml")

        XCTAssertThrowsError(
            try ConfigFileStore(fileURL: linkedFile).saveAPIKey("synthetic-key")
        ) { error in
            XCTAssertEqual(error as? ConfigurationError, .unreadableFile)
        }
        XCTAssertEqual(try permissions(at: realDirectory), 0o755)
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: realDirectory.appendingPathComponent("config.toml").path
            )
        )
    }

    func testSaveRejectsSymlinkedFile() throws {
        let location = makeTemporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: location.root,
            withIntermediateDirectories: true
        )
        let realFile = location.root.appendingPathComponent("real.toml")
        try Data("ark_plan_api_key = \"original\"\n".utf8).write(to: realFile)
        let linkedFile = location.root.appendingPathComponent("link.toml")
        try fileManager.createSymbolicLink(
            at: linkedFile,
            withDestinationURL: realFile
        )

        XCTAssertThrowsError(
            try ConfigFileStore(fileURL: linkedFile).saveAPIKey("synthetic-key")
        ) { error in
            XCTAssertEqual(error as? ConfigurationError, .unreadableFile)
        }
        XCTAssertEqual(
            String(decoding: try Data(contentsOf: realFile), as: UTF8.self),
            "ark_plan_api_key = \"original\"\n"
        )
    }

    func testLoadRejectsSymlinkedFile() throws {
        let location = makeTemporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: location.root,
            withIntermediateDirectories: true
        )
        let realFile = location.root.appendingPathComponent("real.toml")
        try Data("ark_plan_api_key = \"original\"\n".utf8).write(to: realFile)
        let linkedFile = location.root.appendingPathComponent("link.toml")
        try fileManager.createSymbolicLink(
            at: linkedFile,
            withDestinationURL: realFile
        )

        XCTAssertThrowsError(
            try ConfigFileStore(fileURL: linkedFile).loadAPIKey()
        ) { error in
            XCTAssertEqual(error as? ConfigurationError, .unreadableFile)
        }
    }
}

private extension ConfigurationSecurityTests {
    func makeTemporaryConfigLocation(
        nested: Bool = false
    ) -> (root: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexChineseVoiceTests-\(UUID().uuidString)")
        let directory = nested ? root.appendingPathComponent("config") : root
        return (root, directory.appendingPathComponent("config.toml"))
    }

    func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let mode = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return mode.intValue & 0o777
    }
}
