import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class LifecycleTests: XCTestCase {
    func testNoArgumentsDefaultToStart() throws {
        XCTAssertEqual(try LifecycleCommand.parse([]), .start)
    }

    func testParsesSupportedCommandNames() throws {
        let cases: [([String], LifecycleCommand)] = [
            (["start"], .start),
            (["stop"], .stop),
            (["status"], .status),
            (["config"], .config),
            (["doctor"], .doctor),
            (["run-agent"], .runAgent),
            (["--help"], .help),
            (["-h"], .help),
        ]

        for (arguments, expected) in cases {
            XCTAssertEqual(try LifecycleCommand.parse(arguments), expected)
        }
    }

    func testRejectsUnknownOrExtraArguments() {
        for arguments in [["unknown"], ["start", "extra"]] {
            XCTAssertThrowsError(try LifecycleCommand.parse(arguments)) { error in
                XCTAssertEqual(
                    error as? LifecycleCommandError,
                    .invalidArguments(arguments)
                )
            }
        }
    }

    func testPublicHelpHidesRunAgentCommand() {
        let help = LifecycleCommand.publicHelp

        for command in ["start", "stop", "status", "config", "doctor"] {
            XCTAssertTrue(help.contains(command), "Missing \(command) in help")
        }
        XCTAssertFalse(help.contains("run-agent"))
    }

    func testFirstStartLaunchesAgentAndRecordsItsIdentity() throws {
        let pidFile = try temporaryPIDFile()
        defer { try? FileManager.default.removeItem(at: pidFile.deletingLastPathComponent()) }
        let process = FakeAgentProcess(launchPID: 4312)
        let executable = URL(fileURLWithPath: "/tmp/../tmp/codex-chinese-voice")
        let store = PIDFileStore(fileURL: pidFile)
        let controller = BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: executable
        )

        let result = try controller.start()

        XCTAssertEqual(result, .started(pid: 4312))
        XCTAssertEqual(process.launches.count, 1)
        XCTAssertEqual(process.launches.first?.arguments, ["run-agent"])
        XCTAssertEqual(
            process.launches.first?.executableURL.path,
            "/tmp/codex-chinese-voice"
        )
        XCTAssertEqual(
            try store.load(),
            AgentProcessRecord(
                pid: 4312,
                startTime: 900,
                executablePath: "/tmp/codex-chinese-voice"
            )
        )
    }

    func testStartDoesNotLaunchDuplicateMatchingAgent() throws {
        let pidFile = try temporaryPIDFile()
        defer { try? FileManager.default.removeItem(at: pidFile.deletingLastPathComponent()) }
        let process = FakeAgentProcess(launchPID: 4312)
        let executable = URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        let controller = BackgroundProcessController(
            store: PIDFileStore(fileURL: pidFile),
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: executable
        )
        _ = try controller.start()

        let result = try controller.start()

        XCTAssertEqual(result, .alreadyRunning(pid: 4312))
        XCTAssertEqual(process.launches.count, 1)
    }

    func testStartClearsExitedAgentRecordBeforeRelaunching() throws {
        let executable = URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        let store = FakeAgentProcessStore(
            record: AgentProcessRecord(
                pid: 100,
                startTime: 50,
                executablePath: executable.path
            )
        )
        let process = FakeAgentProcess(launchPID: 200)
        let controller = BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: executable
        )

        let result = try controller.start()

        XCTAssertEqual(result, .started(pid: 200))
        XCTAssertEqual(store.clearCount, 1)
        XCTAssertEqual(store.record?.pid, 200)
        XCTAssertTrue(process.signaledPIDs.isEmpty)
    }

    func testStartTreatsReusedPIDWithDifferentStartTimeAsStale() throws {
        let executable = URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        let store = FakeAgentProcessStore(
            record: AgentProcessRecord(
                pid: 100,
                startTime: 50,
                executablePath: executable.path
            )
        )
        let process = FakeAgentProcess(launchPID: 200)
        process.identities[100] = AgentProcessIdentity(
            pid: 100,
            startTime: 51,
            executableURL: executable
        )
        let controller = BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: executable
        )

        let result = try controller.start()

        XCTAssertEqual(result, .started(pid: 200))
        XCTAssertEqual(store.clearCount, 1)
        XCTAssertTrue(process.signaledPIDs.isEmpty)
    }

    func testStartTreatsWrongExecutableAsStaleWithoutTerminatingIt() throws {
        let executable = URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        let store = FakeAgentProcessStore(
            record: AgentProcessRecord(
                pid: 100,
                startTime: 50,
                executablePath: executable.path
            )
        )
        let process = FakeAgentProcess(launchPID: 200)
        process.identities[100] = AgentProcessIdentity(
            pid: 100,
            startTime: 50,
            executableURL: URL(fileURLWithPath: "/tmp/unrelated")
        )
        let controller = BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: executable
        )

        let result = try controller.start()

        XCTAssertEqual(result, .started(pid: 200))
        XCTAssertEqual(store.clearCount, 1)
        XCTAssertTrue(process.signaledPIDs.isEmpty)
    }

    func testStatusIsStoppedWhenNoRecordExists() throws {
        let store = FakeAgentProcessStore()
        let process = FakeAgentProcess(launchPID: 200)
        let controller = BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        )

        let status = try controller.status()

        XCTAssertEqual(status, .stopped)
        XCTAssertEqual(store.clearCount, 0)
        XCTAssertTrue(process.signaledPIDs.isEmpty)
    }

    func testStopIsNotRunningWhenNoRecordExists() throws {
        let store = FakeAgentProcessStore()
        let process = FakeAgentProcess(launchPID: 200)
        let controller = BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        )

        let result = try controller.stop()

        XCTAssertEqual(result, .notRunning)
        XCTAssertEqual(store.clearCount, 0)
        XCTAssertTrue(process.signaledPIDs.isEmpty)
    }

    func testStatusIsRunningForMatchingProcessIdentity() throws {
        let executable = URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        let record = AgentProcessRecord(
            pid: 100,
            startTime: 50,
            executablePath: executable.path
        )
        let store = FakeAgentProcessStore(record: record)
        let process = FakeAgentProcess(launchPID: 200)
        process.identities[100] = AgentProcessIdentity(
            pid: 100,
            startTime: 50,
            executableURL: executable
        )
        let controller = BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: executable
        )

        let status = try controller.status()

        XCTAssertEqual(status, .running(pid: 100))
        XCTAssertEqual(store.clearCount, 0)
        XCTAssertTrue(process.signaledPIDs.isEmpty)
    }

    func testStatusConditionallyClearsStaleIdentity() throws {
        let executable = URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        let record = AgentProcessRecord(
            pid: 100,
            startTime: 50,
            executablePath: executable.path
        )
        let store = FakeAgentProcessStore(record: record)
        let process = FakeAgentProcess(launchPID: 200)
        process.identities[100] = AgentProcessIdentity(
            pid: 100,
            startTime: 51,
            executableURL: executable
        )
        let controller = BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: executable
        )

        let status = try controller.status()

        XCTAssertEqual(status, .stopped)
        XCTAssertEqual(store.conditionalClearRecords, [record])
        XCTAssertNil(store.record)
        XCTAssertTrue(process.signaledPIDs.isEmpty)
    }

    func testStopTerminatesMatchingIdentityThenConditionallyClearsRecord() throws {
        let executable = URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        let record = AgentProcessRecord(
            pid: 100,
            startTime: 50,
            executablePath: executable.path
        )
        let store = FakeAgentProcessStore(record: record)
        let process = FakeAgentProcess(launchPID: 200)
        process.identities[100] = AgentProcessIdentity(
            pid: 100,
            startTime: 50,
            executableURL: executable
        )
        let controller = BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: executable
        )

        let result = try controller.stop()

        XCTAssertEqual(result, .stopped(pid: 100))
        XCTAssertEqual(process.signaledPIDs, [100])
        XCTAssertEqual(store.conditionalClearRecords, [record])
        XCTAssertNil(store.record)
    }

    func testStopDoesNotTerminateWrongExecutable() throws {
        let executable = URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        let record = AgentProcessRecord(
            pid: 100,
            startTime: 50,
            executablePath: executable.path
        )
        let store = FakeAgentProcessStore(record: record)
        let process = FakeAgentProcess(launchPID: 200)
        process.identities[100] = AgentProcessIdentity(
            pid: 100,
            startTime: 50,
            executableURL: URL(fileURLWithPath: "/tmp/unrelated")
        )
        let controller = BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: executable
        )

        let result = try controller.stop()

        XCTAssertEqual(result, .notRunning)
        XCTAssertTrue(process.signaledPIDs.isEmpty)
        XCTAssertEqual(store.conditionalClearRecords, [record])
        XCTAssertNil(store.record)
    }

    func testStopDoesNotTerminateReusedPIDWithDifferentStartTime() throws {
        let executable = URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        let record = AgentProcessRecord(
            pid: 100,
            startTime: 50,
            executablePath: executable.path
        )
        let store = FakeAgentProcessStore(record: record)
        let process = FakeAgentProcess(launchPID: 200)
        process.identities[100] = AgentProcessIdentity(
            pid: 100,
            startTime: 51,
            executableURL: executable
        )
        let controller = BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: executable
        )

        let result = try controller.stop()

        XCTAssertEqual(result, .notRunning)
        XCTAssertTrue(process.signaledPIDs.isEmpty)
        XCTAssertEqual(store.conditionalClearRecords, [record])
        XCTAssertNil(store.record)
    }

    func testStopDoesNotDeleteReplacementRecordCreatedDuringTermination() throws {
        let executable = URL(fileURLWithPath: "/tmp/codex-chinese-voice")
        let original = AgentProcessRecord(
            pid: 100,
            startTime: 50,
            executablePath: executable.path
        )
        let replacement = AgentProcessRecord(
            pid: 101,
            startTime: 60,
            executablePath: executable.path
        )
        let store = FakeAgentProcessStore(record: original)
        let process = FakeAgentProcess(launchPID: 200)
        process.identities[100] = AgentProcessIdentity(
            pid: 100,
            startTime: 50,
            executableURL: executable
        )
        process.onTerminate = { store.record = replacement }
        let controller = BackgroundProcessController(
            store: store,
            inspector: process,
            launcher: process,
            signaler: process,
            executableURL: executable
        )

        let result = try controller.stop()

        XCTAssertEqual(result, .stopped(pid: 100))
        XCTAssertEqual(process.signaledPIDs, [100])
        XCTAssertEqual(store.conditionalClearRecords, [original])
        XCTAssertEqual(store.record, replacement)
    }
}

private extension LifecycleTests {
    func temporaryPIDFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("agent.pid")
    }
}

private final class FakeAgentProcess:
    AgentProcessInspecting,
    AgentProcessLaunching,
    AgentProcessSignaling
{
    struct Launch {
        let executableURL: URL
        let arguments: [String]
    }

    let launchPID: Int32
    let launchStartTime: UInt64
    var identities: [Int32: AgentProcessIdentity] = [:]
    var onTerminate: (() -> Void)?
    private(set) var launches: [Launch] = []
    private(set) var signaledPIDs: [Int32] = []

    init(launchPID: Int32, launchStartTime: UInt64 = 900) {
        self.launchPID = launchPID
        self.launchStartTime = launchStartTime
    }

    func identity(for pid: Int32) -> AgentProcessIdentity? {
        identities[pid]
    }

    func launch(executableURL: URL, arguments: [String]) throws -> Int32 {
        launches.append(Launch(executableURL: executableURL, arguments: arguments))
        identities[launchPID] = AgentProcessIdentity(
            pid: launchPID,
            startTime: launchStartTime,
            executableURL: executableURL
        )
        return launchPID
    }

    func terminate(pid: Int32) throws {
        signaledPIDs.append(pid)
        onTerminate?()
        identities[pid] = nil
    }
}

private final class FakeAgentProcessStore: AgentProcessStateStoring {
    var record: AgentProcessRecord?
    private(set) var conditionalClearRecords: [AgentProcessRecord] = []
    var clearCount: Int { conditionalClearRecords.count }

    init(record: AgentProcessRecord? = nil) {
        self.record = record
    }

    func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        try operation()
    }

    func load() throws -> AgentProcessRecord? {
        record
    }

    func save(_ record: AgentProcessRecord) throws {
        self.record = record
    }

    func clear(ifMatches expected: AgentProcessRecord) throws -> Bool {
        conditionalClearRecords.append(expected)
        guard record == expected else { return false }
        record = nil
        return true
    }
}
