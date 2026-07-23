import Foundation
import Dispatch
import XCTest
@testable import CodexChineseVoiceCore

final class PIDFileLockTests: XCTestCase {
    func testWithLockCreatesPersistentPrivateLockFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexChineseVoiceLockTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("runtime")
        let stateFile = directory.appendingPathComponent("agent.pid")
        let lockFile = stateFile.appendingPathExtension("lock")
        let store = PIDFileStore(fileURL: stateFile)

        try store.withLock {}
        let firstInode = try inode(at: lockFile)
        try store.withLock {}

        XCTAssertEqual(try permissions(at: directory), 0o700)
        XCTAssertEqual(try permissions(at: lockFile), 0o600)
        XCTAssertEqual(try inode(at: lockFile), firstInode)
    }

    func testTwoStoresSerializeCriticalSections() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexChineseVoiceLockTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let stateFile = root.appendingPathComponent("agent.pid")
        let firstStore = PIDFileStore(fileURL: stateFile)
        let secondStore = PIDFileStore(fileURL: stateFile)
        let firstEntered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let firstFinished = DispatchSemaphore(value: 0)
        let secondEntered = DispatchSemaphore(value: 0)
        let secondFinished = DispatchSemaphore(value: 0)
        let errors = LockTestErrorBox()

        DispatchQueue.global().async {
            defer { firstFinished.signal() }
            do {
                try firstStore.withLock {
                    firstEntered.signal()
                    guard releaseFirst.wait(timeout: .now() + 2) == .success else {
                        throw LockTestError.timeout
                    }
                }
            } catch {
                errors.append(error)
            }
        }
        XCTAssertEqual(firstEntered.wait(timeout: .now() + 2), .success)

        DispatchQueue.global().async {
            defer { secondFinished.signal() }
            do {
                try secondStore.withLock { _ = secondEntered.signal() }
            } catch {
                errors.append(error)
            }
        }
        let secondEnteredEarly = secondEntered.wait(timeout: .now() + 0.1)
        XCTAssertEqual(secondEnteredEarly, .timedOut)

        releaseFirst.signal()
        XCTAssertEqual(firstFinished.wait(timeout: .now() + 2), .success)
        if secondEnteredEarly == .timedOut {
            XCTAssertEqual(secondEntered.wait(timeout: .now() + 2), .success)
        }
        XCTAssertEqual(secondFinished.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(errors.values.isEmpty)
    }

    func testWithLockRejectsSymlinkedLockFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexChineseVoiceLockTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let stateFile = root.appendingPathComponent("agent.pid")
        let lockFile = stateFile.appendingPathExtension("lock")
        let target = root.appendingPathComponent("target.lock")
        try Data().write(to: target)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: target.path
        )
        try FileManager.default.createSymbolicLink(
            at: lockFile,
            withDestinationURL: target
        )
        var entered = false

        XCTAssertThrowsError(
            try PIDFileStore(fileURL: stateFile).withLock { entered = true }
        ) {
            XCTAssertEqual($0 as? AgentProcessStateError, .unreadableState)
        }
        XCTAssertFalse(entered)
    }
}

private extension PIDFileLockTests {
    func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    func inode(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    }
}

private enum LockTestError: Error {
    case timeout
}

private final class LockTestErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Error] = []

    var values: [Error] {
        lock.withLock { storage }
    }

    func append(_ error: Error) {
        lock.withLock { storage.append(error) }
    }
}
