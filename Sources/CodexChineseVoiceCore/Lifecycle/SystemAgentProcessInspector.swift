import Darwin
import Foundation

public struct SystemAgentProcessInspector: AgentProcessInspecting, Sendable {
    private let identityQuery: @Sendable (Int32) -> AgentProcessIdentity?

    public init() {
        identityQuery = Self.systemIdentity
    }

    init(
        identityQuery: @escaping @Sendable (Int32) -> AgentProcessIdentity?
    ) {
        self.identityQuery = identityQuery
    }

    public func identity(for pid: Int32) -> AgentProcessIdentity? {
        guard pid > 1 else { return nil }
        return identityQuery(pid)
    }
}

private extension SystemAgentProcessInspector {
    static func systemIdentity(for pid: Int32) -> AgentProcessIdentity? {
        guard let startTime = processStartTime(for: pid),
              let executableURL = processExecutableURL(for: pid)
        else {
            return nil
        }
        return AgentProcessIdentity(
            pid: pid,
            startTime: startTime,
            executableURL: executableURL
        )
    }
    static func processStartTime(for pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let result = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &info,
            expectedSize
        )
        guard result == expectedSize,
              info.pbi_start_tvsec > 0,
              info.pbi_start_tvusec < 1_000_000
        else {
            return nil
        }

        let (seconds, multipliedOverflow) = info.pbi_start_tvsec
            .multipliedReportingOverflow(by: 1_000_000)
        let (microseconds, addedOverflow) = seconds.addingReportingOverflow(
            info.pbi_start_tvusec
        )
        guard !multipliedOverflow, !addedOverflow, microseconds > 0 else {
            return nil
        }
        return microseconds
    }

    static func processExecutableURL(for pid: Int32) -> URL? {
        var buffer = [CChar](
            repeating: 0,
            count: 4 * Int(MAXPATHLEN)
        )
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }

        let pathBytes = buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
        let path = String(decoding: pathBytes, as: UTF8.self)
        guard !path.isEmpty, NSString(string: path).isAbsolutePath else {
            return nil
        }
        return URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }
}
