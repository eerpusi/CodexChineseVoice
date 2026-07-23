import Darwin
import Foundation

public enum AgentProcessSignalError: Error, Equatable, Sendable {
    case invalidPID
    case identityChanged
    case systemCallFailed(code: Int32)
}

public struct SystemAgentProcessSignaler: AgentProcessSignaling {
    private let inspector: (any AgentProcessInspecting)?
    private let killCall: (Int32, Int32) -> Int32

    public init() {
        inspector = nil
        killCall = Darwin.kill
    }

    init(killCall: @escaping (Int32, Int32) -> Int32) {
        inspector = nil
        self.killCall = killCall
    }

    init(
        inspector: any AgentProcessInspecting,
        killCall: @escaping (Int32, Int32) -> Int32
    ) {
        self.inspector = inspector
        self.killCall = killCall
    }

    public func terminate(pid: Int32) throws {
        guard pid > 1 else { throw AgentProcessSignalError.invalidPID }
        try sendSIGTERM(to: pid)
    }

    func terminate(expectedIdentity: AgentProcessIdentity) throws {
        guard expectedIdentity.pid > 1 else {
            throw AgentProcessSignalError.invalidPID
        }
        guard let inspector,
              let current = inspector.identity(for: expectedIdentity.pid),
              Self.matches(expectedIdentity, current: current)
        else {
            throw AgentProcessSignalError.identityChanged
        }
        try sendSIGTERM(to: expectedIdentity.pid)
    }
}

private extension SystemAgentProcessSignaler {
    func sendSIGTERM(to pid: Int32) throws {
        guard killCall(pid, SIGTERM) == 0 else {
            throw AgentProcessSignalError.systemCallFailed(code: errno)
        }
    }

    static func matches(
        _ expected: AgentProcessIdentity,
        current: AgentProcessIdentity
    ) -> Bool {
        expected.pid == current.pid
            && expected.startTime == current.startTime
            && canonicalPath(expected.executableURL)
                == canonicalPath(current.executableURL)
    }

    static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
