import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class PIDFileStoreTests: XCTestCase {
    func testLoadRejectsPIDOne() throws {
        let location = try makeTemporaryStateLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try writePrivateRecord(
            AgentProcessRecord(
                pid: 1,
                startTime: 10,
                executablePath: "/tmp/codex-chinese-voice"
            ),
            to: location.file
        )

        XCTAssertThrowsError(try PIDFileStore(fileURL: location.file).load()) {
            XCTAssertEqual($0 as? AgentProcessStateError, .invalidRecord)
        }
    }

    func testSaveRejectsPIDOneWithoutCreatingStateFile() throws {
        let location = try makeTemporaryStateLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let record = AgentProcessRecord(
            pid: 1,
            startTime: 10,
            executablePath: "/tmp/codex-chinese-voice"
        )

        XCTAssertThrowsError(
            try PIDFileStore(fileURL: location.file).save(record)
        ) {
            XCTAssertEqual($0 as? AgentProcessStateError, .invalidRecord)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.file.path))
    }

    func testLoadRejectsRelativeExecutablePath() throws {
        let location = try makeTemporaryStateLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try writePrivateRecord(
            AgentProcessRecord(
                pid: 100,
                startTime: 10,
                executablePath: "bin/codex-chinese-voice"
            ),
            to: location.file
        )

        XCTAssertThrowsError(try PIDFileStore(fileURL: location.file).load()) {
            XCTAssertEqual($0 as? AgentProcessStateError, .invalidRecord)
        }
    }

    func testSaveRejectsRelativeExecutablePath() throws {
        let location = try makeTemporaryStateLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let record = AgentProcessRecord(
            pid: 100,
            startTime: 10,
            executablePath: "bin/codex-chinese-voice"
        )

        XCTAssertThrowsError(
            try PIDFileStore(fileURL: location.file).save(record)
        ) {
            XCTAssertEqual($0 as? AgentProcessStateError, .invalidRecord)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.file.path))
    }

    func testSaveRejectsZeroStartTime() throws {
        let location = try makeTemporaryStateLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let record = AgentProcessRecord(
            pid: 100,
            startTime: 0,
            executablePath: "/tmp/codex-chinese-voice"
        )

        XCTAssertThrowsError(
            try PIDFileStore(fileURL: location.file).save(record)
        ) {
            XCTAssertEqual($0 as? AgentProcessStateError, .invalidRecord)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.file.path))
    }

    func testSaveCreatesPrivateDirectoryAndStateFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexChineseVoicePIDTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtimeDirectory = root.appendingPathComponent("runtime")
        let file = runtimeDirectory.appendingPathComponent("agent.pid")
        let record = validRecord()

        try PIDFileStore(fileURL: file).save(record)

        XCTAssertEqual(try permissions(at: runtimeDirectory), 0o700)
        XCTAssertEqual(try permissions(at: file), 0o600)
        XCTAssertEqual(try PIDFileStore(fileURL: file).load(), record)
    }

    func testLoadRejectsSymlinkedStateFile() throws {
        let location = try makeTemporaryStateLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let realFile = location.root.appendingPathComponent("real.pid")
        try writePrivateRecord(validRecord(), to: realFile)
        try FileManager.default.createSymbolicLink(
            at: location.file,
            withDestinationURL: realFile
        )

        XCTAssertThrowsError(try PIDFileStore(fileURL: location.file).load()) {
            XCTAssertEqual($0 as? AgentProcessStateError, .unreadableState)
        }
    }

    func testSaveRejectsSymlinkedStateFileWithoutChangingTarget() throws {
        let location = try makeTemporaryStateLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        let original = validRecord()
        let realFile = location.root.appendingPathComponent("real.pid")
        try writePrivateRecord(original, to: realFile)
        try FileManager.default.createSymbolicLink(
            at: location.file,
            withDestinationURL: realFile
        )
        let replacement = AgentProcessRecord(
            pid: 200,
            startTime: 20,
            executablePath: "/tmp/codex-chinese-voice"
        )

        XCTAssertThrowsError(
            try PIDFileStore(fileURL: location.file).save(replacement)
        ) {
            XCTAssertEqual($0 as? AgentProcessStateError, .unreadableState)
        }
        XCTAssertEqual(
            try JSONDecoder().decode(
                AgentProcessRecord.self,
                from: Data(contentsOf: realFile)
            ),
            original
        )
    }

    func testLoadRejectsBroadlyReadableStateFile() throws {
        let location = try makeTemporaryStateLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try writePrivateRecord(validRecord(), to: location.file)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: location.file.path
        )

        XCTAssertThrowsError(try PIDFileStore(fileURL: location.file).load()) {
            XCTAssertEqual($0 as? AgentProcessStateError, .unreadableState)
        }
    }

    func testLoadRejectsZeroAndNegativePIDs() throws {
        for pid: Int32 in [0, -10] {
            let location = try makeTemporaryStateLocation()
            defer { try? FileManager.default.removeItem(at: location.root) }
            try writePrivateRecord(
                AgentProcessRecord(
                    pid: pid,
                    startTime: 10,
                    executablePath: "/tmp/codex-chinese-voice"
                ),
                to: location.file
            )

            XCTAssertThrowsError(try PIDFileStore(fileURL: location.file).load()) {
                XCTAssertEqual($0 as? AgentProcessStateError, .invalidRecord)
            }
        }
    }

    func testLoadRejectsEmptyExecutablePath() throws {
        let location = try makeTemporaryStateLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try writePrivateRecord(
            AgentProcessRecord(pid: 100, startTime: 10, executablePath: ""),
            to: location.file
        )

        XCTAssertThrowsError(try PIDFileStore(fileURL: location.file).load()) {
            XCTAssertEqual($0 as? AgentProcessStateError, .invalidRecord)
        }
    }

    func testLoadRejectsMalformedJSON() throws {
        let location = try makeTemporaryStateLocation()
        defer { try? FileManager.default.removeItem(at: location.root) }
        try writePrivateData(Data("not-json".utf8), to: location.file)

        XCTAssertThrowsError(try PIDFileStore(fileURL: location.file).load()) {
            XCTAssertEqual($0 as? AgentProcessStateError, .invalidRecord)
        }
    }
}

private extension PIDFileStoreTests {
    func makeTemporaryStateLocation() throws -> (root: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexChineseVoicePIDTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return (root, root.appendingPathComponent("agent.pid"))
    }

    func writePrivateRecord(_ record: AgentProcessRecord, to url: URL) throws {
        try writePrivateData(try JSONEncoder().encode(record), to: url)
    }

    func writePrivateData(_ data: Data, to url: URL) throws {
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    func validRecord() -> AgentProcessRecord {
        AgentProcessRecord(
            pid: 100,
            startTime: 10,
            executablePath: "/tmp/codex-chinese-voice"
        )
    }

    func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
