import Darwin
import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class SystemAgentProcessSignalerTests: XCTestCase {
    func testMapsKillErrnoToTypedFailure() {
        let expected = processIdentity()
        let inspector = RecordingProcessInspector(identity: expected)
        let savedErrno = errno
        defer { errno = savedErrno }
        let signaler = SystemAgentProcessSignaler(
            inspector: inspector,
            killCall: { _, _ in
                errno = EPERM
                return -1
            }
        )

        XCTAssertThrowsError(
            try signaler.terminate(expectedIdentity: expected)
        ) { error in
            XCTAssertEqual(
                error as? AgentProcessSignalError,
                .systemCallFailed(code: EPERM)
            )
        }
    }

    func testMapsKillErrnoToTypedFailureForPIDTermination() {
        let savedErrno = errno
        defer { errno = savedErrno }
        let signaler = SystemAgentProcessSignaler(
            killCall: { _, _ in
                errno = ESRCH
                return -1
            }
        )

        XCTAssertThrowsError(
            try signaler.terminate(pid: 4_312)
        ) { error in
            XCTAssertEqual(
                error as? AgentProcessSignalError,
                .systemCallFailed(code: ESRCH)
            )
        }
    }

    func testRejectsMissingOrChangedIdentityWithoutCallingKill() {
        let expected = processIdentity()
        let currentIdentities: [AgentProcessIdentity?] = [
            nil,
            processIdentity(startTime: expected.startTime + 1),
            processIdentity(executablePath: "/tmp/unrelated"),
        ]

        for currentIdentity in currentIdentities {
            let inspector = RecordingProcessInspector(identity: currentIdentity)
            var callCount = 0
            let signaler = SystemAgentProcessSignaler(
                inspector: inspector,
                killCall: { _, _ in
                    callCount += 1
                    return 0
                }
            )

            XCTAssertThrowsError(
                try signaler.terminate(expectedIdentity: expected)
            ) { error in
                XCTAssertEqual(
                    error as? AgentProcessSignalError,
                    .identityChanged
                )
            }
            XCTAssertEqual(callCount, 0)
        }
    }

    func testRejectsReservedPIDBeforeCallingKill() {
        let expected = processIdentity(pid: 1)
        let inspector = RecordingProcessInspector(identity: expected)
        var callCount = 0
        let signaler = SystemAgentProcessSignaler(
            inspector: inspector,
            killCall: { _, _ in
                callCount += 1
                return 0
            }
        )

        XCTAssertThrowsError(
            try signaler.terminate(expectedIdentity: expected)
        ) { error in
            XCTAssertEqual(error as? AgentProcessSignalError, .invalidPID)
        }
        XCTAssertEqual(callCount, 0)
    }

    func testMatchingIdentitySendsOnlySIGTERM() throws {
        let expected = processIdentity()
        let inspector = RecordingProcessInspector(identity: expected)
        var calls: [(pid: Int32, signal: Int32)] = []
        let signaler = SystemAgentProcessSignaler(
            inspector: inspector,
            killCall: { pid, signal in
                calls.append((pid, signal))
                return 0
            }
        )

        try signaler.terminate(expectedIdentity: expected)

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.pid, expected.pid)
        XCTAssertEqual(calls.first?.signal, SIGTERM)
    }
}

private extension SystemAgentProcessSignalerTests {
    func processIdentity(
        pid: Int32 = 4_312,
        startTime: UInt64 = 900,
        executablePath: String = "/tmp/codex-chinese-voice"
    ) -> AgentProcessIdentity {
        AgentProcessIdentity(
            pid: pid,
            startTime: startTime,
            executableURL: URL(fileURLWithPath: executablePath)
        )
    }
}

private final class RecordingProcessInspector: AgentProcessInspecting {
    private let currentIdentity: AgentProcessIdentity?

    init(identity: AgentProcessIdentity?) {
        currentIdentity = identity
    }

    func identity(for pid: Int32) -> AgentProcessIdentity? {
        currentIdentity
    }
}
