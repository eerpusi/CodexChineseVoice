import Darwin
import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class SystemAgentProcessInspectorTests: XCTestCase {
    func testRejectsPIDValuesThatMustNeverBeManaged() {
        let inspector = SystemAgentProcessInspector(identityQuery: { pid in
            AgentProcessIdentity(
                pid: pid,
                startTime: 1,
                executableURL: URL(fileURLWithPath: "/tmp/process")
            )
        })

        for pid in [Int32.min, -1, 0, 1] {
            XCTAssertNil(inspector.identity(for: pid), "pid: \(pid)")
        }
    }

    func testInspectsCurrentProcessIdentity() throws {
        let pid = getpid()
        let identity = try XCTUnwrap(
            SystemAgentProcessInspector().identity(for: pid)
        )
        let expectedExecutable = try XCTUnwrap(Bundle.main.executableURL)

        XCTAssertEqual(identity.pid, pid)
        XCTAssertGreaterThan(identity.startTime, 0)
        XCTAssertEqual(
            canonicalPath(identity.executableURL),
            canonicalPath(expectedExecutable)
        )
    }
}

private extension SystemAgentProcessInspectorTests {
    func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
