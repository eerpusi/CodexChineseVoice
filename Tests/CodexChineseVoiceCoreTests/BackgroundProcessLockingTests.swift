import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class BackgroundProcessLockingTests: XCTestCase {
    func testStartRunsEntireOperationInsideOneStoreLock() throws {
        let store = LockCheckingProcessStore()
        let process = LockCheckingProcess(store: store, launchPID: 200)
        let controller = makeController(store: store, process: process)

        XCTAssertEqual(try controller.start(), .started(pid: 200))

        XCTAssertEqual(store.lockEntryCount, 1)
        XCTAssertEqual(store.operationsOutsideLock, 0)
        XCTAssertEqual(process.operationsOutsideLock, 0)
    }

    func testStatusRunsEntireOperationInsideOneStoreLock() throws {
        let store = LockCheckingProcessStore()
        let process = LockCheckingProcess(store: store, launchPID: 200)
        let executable = URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        store.record = AgentProcessRecord(
            pid: 100,
            startTime: 10,
            executablePath: executable.path
        )
        process.setIdentity(
            AgentProcessIdentity(
                pid: 100,
                startTime: 10,
                executableURL: executable
            )
        )
        let controller = makeController(store: store, process: process)

        XCTAssertEqual(try controller.status(), .running(pid: 100))

        XCTAssertEqual(store.lockEntryCount, 1)
        XCTAssertEqual(store.operationsOutsideLock, 0)
        XCTAssertEqual(process.operationsOutsideLock, 0)
    }

    func testStopRunsEntireOperationInsideOneStoreLock() throws {
        let store = LockCheckingProcessStore()
        let process = LockCheckingProcess(store: store, launchPID: 200)
        let executable = URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        store.record = AgentProcessRecord(
            pid: 100,
            startTime: 10,
            executablePath: executable.path
        )
        process.setIdentity(
            AgentProcessIdentity(
                pid: 100,
                startTime: 10,
                executableURL: executable
            )
        )
        let controller = makeController(store: store, process: process)

        XCTAssertEqual(try controller.stop(), .stopped(pid: 100))

        XCTAssertEqual(store.lockEntryCount, 1)
        XCTAssertEqual(store.operationsOutsideLock, 0)
        XCTAssertEqual(process.operationsOutsideLock, 0)
    }

    func testStartRejectsReservedLauncherPIDWithoutSavingState() throws {
        let store = LockCheckingProcessStore()
        let process = LockCheckingProcess(store: store, launchPID: 1)
        let controller = makeController(store: store, process: process)

        XCTAssertThrowsError(try controller.start()) {
            XCTAssertEqual(
                $0 as? BackgroundProcessError,
                .launchedProcessIdentityUnavailable
            )
        }
        XCTAssertNil(store.record)
        XCTAssertEqual(store.lockEntryCount, 1)
        XCTAssertEqual(store.operationsOutsideLock, 0)
        XCTAssertEqual(process.operationsOutsideLock, 0)
    }

    func testStartRejectsZeroIdentityStartTimeWithoutSavingState() throws {
        let store = LockCheckingProcessStore()
        let process = LockCheckingProcess(
            store: store,
            launchPID: 200,
            launchStartTime: 0
        )
        let controller = makeController(store: store, process: process)

        XCTAssertThrowsError(try controller.start()) {
            XCTAssertEqual(
                $0 as? BackgroundProcessError,
                .launchedProcessIdentityUnavailable
            )
        }
        XCTAssertNil(store.record)
        XCTAssertEqual(store.lockEntryCount, 1)
        XCTAssertEqual(store.operationsOutsideLock, 0)
        XCTAssertEqual(process.operationsOutsideLock, 0)
    }

    func testStartRejectsMismatchedIdentityPIDWithoutSavingState() throws {
        let store = LockCheckingProcessStore()
        let process = LockCheckingProcess(
            store: store,
            launchPID: 200,
            identityPID: 201
        )
        let controller = makeController(store: store, process: process)

        XCTAssertThrowsError(try controller.start()) {
            XCTAssertEqual(
                $0 as? BackgroundProcessError,
                .launchedProcessIdentityUnavailable
            )
        }
        XCTAssertNil(store.record)
    }

    func testStartRejectsWrongIdentityExecutableWithoutSavingState() throws {
        let store = LockCheckingProcessStore()
        let process = LockCheckingProcess(
            store: store,
            launchPID: 200,
            identityExecutableURL: URL(fileURLWithPath: "/tmp/unrelated")
        )
        let controller = makeController(store: store, process: process)

        XCTAssertThrowsError(try controller.start()) {
            XCTAssertEqual(
                $0 as? BackgroundProcessError,
                .launchedProcessIdentityUnavailable
            )
        }
        XCTAssertNil(store.record)
    }
}

private extension BackgroundProcessLockingTests {
    func makeController(
        store: LockCheckingProcessStore,
        process: LockCheckingProcess
    ) -> BackgroundProcessController {
        BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        )
    }
}

private final class LockCheckingProcessStore: AgentProcessStateStoring {
    var record: AgentProcessRecord?
    private(set) var isLocked = false
    private(set) var lockEntryCount = 0
    private(set) var operationsOutsideLock = 0

    func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lockEntryCount += 1
        isLocked = true
        defer { isLocked = false }
        return try operation()
    }

    func load() throws -> AgentProcessRecord? {
        recordOperation()
        return record
    }

    func save(_ record: AgentProcessRecord) throws {
        recordOperation()
        self.record = record
    }

    func clear(ifMatches expected: AgentProcessRecord) throws -> Bool {
        recordOperation()
        guard record == expected else { return false }
        record = nil
        return true
    }

    private func recordOperation() {
        if !isLocked { operationsOutsideLock += 1 }
    }
}

private final class LockCheckingProcess:
    AgentProcessInspecting,
    AgentProcessLaunching,
    AgentProcessSignaling
{
    private let store: LockCheckingProcessStore
    private let launchPID: Int32
    private let launchStartTime: UInt64
    private let identityPID: Int32?
    private let identityExecutableURL: URL?
    private var identities: [Int32: AgentProcessIdentity] = [:]
    private(set) var operationsOutsideLock = 0

    init(
        store: LockCheckingProcessStore,
        launchPID: Int32,
        launchStartTime: UInt64 = 10,
        identityPID: Int32? = nil,
        identityExecutableURL: URL? = nil
    ) {
        self.store = store
        self.launchPID = launchPID
        self.launchStartTime = launchStartTime
        self.identityPID = identityPID
        self.identityExecutableURL = identityExecutableURL
    }

    func setIdentity(_ identity: AgentProcessIdentity) {
        identities[identity.pid] = identity
    }

    func identity(for pid: Int32) -> AgentProcessIdentity? {
        recordOperation()
        return identities[pid]
    }

    func launch(executableURL: URL, arguments: [String]) throws -> Int32 {
        recordOperation()
        identities[launchPID] = AgentProcessIdentity(
            pid: identityPID ?? launchPID,
            startTime: launchStartTime,
            executableURL: identityExecutableURL ?? executableURL
        )
        return launchPID
    }

    func terminate(pid: Int32) throws {
        recordOperation()
        identities[pid] = nil
    }

    private func recordOperation() {
        if !store.isLocked { operationsOutsideLock += 1 }
    }
}
