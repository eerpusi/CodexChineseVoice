import Darwin
import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class POSIXSpawnExecutorTests: XCTestCase {
    func testClosesUnrelatedFileDescriptorsWhenRequested() throws {
        let baseFD = open("/dev/null", O_RDONLY)
        XCTAssertGreaterThanOrEqual(baseFD, 0)
        guard baseFD >= 0 else { return }
        defer { close(baseFD) }
        let inheritedFD = fcntl(baseFD, F_DUPFD, 200)
        XCTAssertGreaterThanOrEqual(inheritedFD, 200)
        guard inheritedFD >= 200 else { return }
        defer { close(inheritedFD) }
        let request = DetachedSpawnRequest(
            executableURL: URL(fileURLWithPath: "/bin/test"),
            arguments: ["!", "-e", "/dev/fd/\(inheritedFD)"],
            createSession: false,
            redirectsStandardStreamsToNull: false,
            closesUnrelatedFileDescriptors: true,
            inheritsEnvironment: false
        )

        let pid = try POSIXSpawnExecutor().spawn(request)

        XCTAssertEqual(waitForExit(of: pid), 0)
    }

    func testRedirectsAllStandardStreamsToNullWhenRequested() throws {
        let request = DetachedSpawnRequest(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "test /dev/null -ef /dev/fd/0 && "
                    + "test /dev/null -ef /dev/fd/1 && "
                    + "test /dev/null -ef /dev/fd/2",
            ],
            createSession: false,
            redirectsStandardStreamsToNull: true,
            closesUnrelatedFileDescriptors: false,
            inheritsEnvironment: false
        )

        let pid = try POSIXSpawnExecutor().spawn(request)

        XCTAssertEqual(waitForExit(of: pid), 0)
    }

    func testCreatesNewSessionWhenRequested() throws {
        let request = DetachedSpawnRequest(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"],
            createSession: true,
            redirectsStandardStreamsToNull: false,
            closesUnrelatedFileDescriptors: false,
            inheritsEnvironment: false
        )

        let pid = try POSIXSpawnExecutor().spawn(request)
        defer { terminateAndReap(pid) }

        XCTAssertEqual(getsid(pid), pid)
    }

    func testInheritsEnvironmentWithoutMaterializingItInRequest() throws {
        let name = "CCV_POSIX_SPAWN_TEST_MARKER"
        let value = "synthetic-value"
        XCTAssertEqual(setenv(name, value, 1), 0)
        defer { unsetenv(name) }
        let request = DetachedSpawnRequest(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "test \"$CCV_POSIX_SPAWN_TEST_MARKER\" = synthetic-value",
            ],
            createSession: false,
            redirectsStandardStreamsToNull: false,
            closesUnrelatedFileDescriptors: false,
            inheritsEnvironment: true
        )

        let pid = try POSIXSpawnExecutor().spawn(request)

        XCTAssertEqual(waitForExit(of: pid), 0)
    }

    func testPassesOnlyExecutableAndSuppliedArguments() throws {
        let request = DetachedSpawnRequest(
            executableURL: URL(fileURLWithPath: "/bin/test"),
            arguments: ["alpha", "=", "alpha"],
            createSession: false,
            redirectsStandardStreamsToNull: false,
            closesUnrelatedFileDescriptors: false,
            inheritsEnvironment: false
        )

        let pid = try POSIXSpawnExecutor().spawn(request)

        XCTAssertEqual(waitForExit(of: pid), 0)
    }

    func testMissingExecutableReportsOnlySpawnStageAndErrorCode() {
        let request = DetachedSpawnRequest(
            executableURL: URL(
                fileURLWithPath: "/definitely/missing/codex-chinese-voice"
            ),
            arguments: [],
            createSession: false,
            redirectsStandardStreamsToNull: false,
            closesUnrelatedFileDescriptors: false,
            inheritsEnvironment: false
        )

        XCTAssertThrowsError(try POSIXSpawnExecutor().spawn(request)) { error in
            XCTAssertEqual(
                error as? POSIXSpawnError,
                POSIXSpawnError(operation: .spawn, code: ENOENT)
            )
        }
    }
}

private extension POSIXSpawnExecutorTests {
    func terminateAndReap(_ pid: Int32) {
        _ = kill(pid, SIGTERM)
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    }

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
