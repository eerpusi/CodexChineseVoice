import Darwin
import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class DetachedAgentProcessLauncherTests: XCTestCase {
    func testDefaultLauncherUsesPOSIXSpawner() throws {
        let launcher = DetachedAgentProcessLauncher()

        let pid = try launcher.launch(
            executableURL: URL(fileURLWithPath: "/bin/test"),
            arguments: ["alpha", "=", "alpha"]
        )

        XCTAssertEqual(waitForExit(of: pid), 0)
    }

    func testLaunchBuildsDetachedRequestAndReturnsSpawnedPID() throws {
        let spawner = RecordingAgentProcessSpawner(pid: 4_312)
        let launcher = DetachedAgentProcessLauncher(spawner: spawner)

        let pid = try launcher.launch(
            executableURL: URL(
                fileURLWithPath: "/tmp/../tmp/codex-chinese-voice"
            ),
            arguments: ["run-agent"]
        )

        XCTAssertEqual(pid, 4_312)
        XCTAssertEqual(
            spawner.requests,
            [
                DetachedSpawnRequest(
                    executableURL: URL(
                        fileURLWithPath: "/tmp/codex-chinese-voice"
                    ),
                    arguments: ["run-agent"],
                    createSession: true,
                    redirectsStandardStreamsToNull: true,
                    closesUnrelatedFileDescriptors: true,
                    inheritsEnvironment: true
                ),
            ]
        )
    }
}

private extension DetachedAgentProcessLauncherTests {
    func waitForExit(of pid: Int32) -> Int32 {
        var status: Int32 = 0
        var result: Int32
        repeat {
            result = waitpid(pid, &status, 0)
        } while result == -1 && errno == EINTR

        guard result == pid, status & 0x7f == 0 else { return -1 }
        return (status >> 8) & 0xff
    }
}

private final class RecordingAgentProcessSpawner: AgentProcessSpawning {
    private let pid: Int32
    private(set) var requests: [DetachedSpawnRequest] = []

    init(pid: Int32) {
        self.pid = pid
    }

    func spawn(_ request: DetachedSpawnRequest) throws -> Int32 {
        requests.append(request)
        return pid
    }
}
