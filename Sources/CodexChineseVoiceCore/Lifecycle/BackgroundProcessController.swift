import Foundation

public struct AgentProcessIdentity: Equatable, Sendable {
    public let pid: Int32
    public let startTime: UInt64
    public let executableURL: URL

    public init(pid: Int32, startTime: UInt64, executableURL: URL) {
        self.pid = pid
        self.startTime = startTime
        self.executableURL = executableURL
    }
}

public protocol AgentProcessInspecting {
    func identity(for pid: Int32) -> AgentProcessIdentity?
}

public protocol AgentProcessLaunching {
    func launch(executableURL: URL, arguments: [String]) throws -> Int32
}

public protocol AgentProcessSignaling {
    func terminate(pid: Int32) throws
}

public enum BackgroundStartResult: Equatable, Sendable {
    case started(pid: Int32)
    case alreadyRunning(pid: Int32)
}

public enum BackgroundProcessStatus: Equatable, Sendable {
    case running(pid: Int32)
    case stopped
}

public enum BackgroundStopResult: Equatable, Sendable {
    case stopped(pid: Int32)
    case notRunning
}

public enum BackgroundProcessError: Error, Equatable, Sendable {
    case launchedProcessIdentityUnavailable
}

public final class BackgroundProcessController {
    private let store: any AgentProcessStateStoring
    private let inspector: any AgentProcessInspecting
    private let launcher: any AgentProcessLaunching
    private let signaler: any AgentProcessSignaling
    private let executableURL: URL
    private let executablePath: String

    public init(
        store: any AgentProcessStateStoring,
        inspector: any AgentProcessInspecting,
        launcher: any AgentProcessLaunching,
        signaler: any AgentProcessSignaling,
        executableURL: URL
    ) {
        self.store = store
        self.inspector = inspector
        self.launcher = launcher
        self.signaler = signaler
        self.executableURL = Self.canonicalURL(executableURL)
        self.executablePath = Self.canonicalURL(executableURL).path
    }

    public func start() throws -> BackgroundStartResult {
        try store.withLock { try startLocked() }
    }

    private func startLocked() throws -> BackgroundStartResult {
        if let record = try store.load() {
            let identity = inspector.identity(for: record.pid)
            if isMatchingAgent(record, identity: identity) {
                return .alreadyRunning(pid: record.pid)
            }
            try store.clear(ifMatches: record)
        }
        let pid = try launcher.launch(
            executableURL: executableURL,
            arguments: ["run-agent"]
        )
        guard pid > 1,
              let identity = inspector.identity(for: pid),
              identity.pid == pid,
              identity.startTime > 0,
              Self.canonicalURL(identity.executableURL).path == executablePath
        else {
            throw BackgroundProcessError.launchedProcessIdentityUnavailable
        }
        try store.save(
            AgentProcessRecord(
                pid: pid,
                startTime: identity.startTime,
                executablePath: executablePath
            )
        )
        return .started(pid: pid)
    }

    public func status() throws -> BackgroundProcessStatus {
        try store.withLock { try statusLocked() }
    }

    private func statusLocked() throws -> BackgroundProcessStatus {
        guard let record = try store.load() else { return .stopped }
        let identity = inspector.identity(for: record.pid)
        guard isMatchingAgent(record, identity: identity) else {
            try store.clear(ifMatches: record)
            return .stopped
        }
        return .running(pid: record.pid)
    }

    public func stop() throws -> BackgroundStopResult {
        try store.withLock { try stopLocked() }
    }

    private func stopLocked() throws -> BackgroundStopResult {
        guard let record = try store.load() else { return .notRunning }
        let identity = inspector.identity(for: record.pid)
        guard isMatchingAgent(record, identity: identity) else {
            try store.clear(ifMatches: record)
            return .notRunning
        }
        try signaler.terminate(pid: record.pid)
        try store.clear(ifMatches: record)
        return .stopped(pid: record.pid)
    }

    private func isMatchingAgent(
        _ record: AgentProcessRecord,
        identity: AgentProcessIdentity?
    ) -> Bool {
        guard let identity,
              record.pid == identity.pid,
              record.startTime == identity.startTime,
              record.executablePath == executablePath
        else {
            return false
        }
        return Self.canonicalURL(identity.executableURL).path == executablePath
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
