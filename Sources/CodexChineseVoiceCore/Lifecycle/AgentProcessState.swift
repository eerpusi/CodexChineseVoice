import Foundation

public struct AgentProcessRecord: Codable, Equatable, Sendable {
    public let pid: Int32
    public let startTime: UInt64
    public let executablePath: String

    public init(pid: Int32, startTime: UInt64, executablePath: String) {
        self.pid = pid
        self.startTime = startTime
        self.executablePath = executablePath
    }
}

public enum AgentProcessStateError: Error, Equatable, Sendable {
    case invalidRecord
    case unreadableState
}

public protocol AgentProcessStateStoring {
    func withLock<Result>(_ operation: () throws -> Result) throws -> Result
    func load() throws -> AgentProcessRecord?
    func save(_ record: AgentProcessRecord) throws
    @discardableResult
    func clear(ifMatches expected: AgentProcessRecord) throws -> Bool
}

public struct PIDFileStore: AgentProcessStateStoring, Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func withLock<Result>(
        _ operation: () throws -> Result
    ) throws -> Result {
        do {
            return try SecureFileAccess.withExclusiveLock(
                at: fileURL.appendingPathExtension("lock"),
                operation: operation
            )
        } catch is SecureFileAccessError {
            throw AgentProcessStateError.unreadableState
        } catch {
            throw error
        }
    }

    public func load() throws -> AgentProcessRecord? {
        do {
            guard let data = try SecureFileAccess.read(from: fileURL) else {
                return nil
            }
            let record = try JSONDecoder().decode(AgentProcessRecord.self, from: data)
            try Self.validateIdentity(record)
            return record
        } catch let error as AgentProcessStateError {
            throw error
        } catch SecureFileAccessError.missing {
            return nil
        } catch is DecodingError {
            throw AgentProcessStateError.invalidRecord
        } catch {
            throw AgentProcessStateError.unreadableState
        }
    }

    public func save(_ record: AgentProcessRecord) throws {
        try Self.validateIdentity(record)
        do {
            let data = try JSONEncoder().encode(record)
            try SecureFileAccess.write(data, to: fileURL)
        } catch let error as AgentProcessStateError {
            throw error
        } catch {
            throw AgentProcessStateError.unreadableState
        }
    }

    @discardableResult
    public func clear(ifMatches expected: AgentProcessRecord) throws -> Bool {
        guard try load() == expected else { return false }
        try FileManager.default.removeItem(at: fileURL)
        return true
    }
}

private extension PIDFileStore {
    static func validateIdentity(_ record: AgentProcessRecord) throws {
        guard record.pid > 1,
              record.startTime > 0,
              NSString(string: record.executablePath).isAbsolutePath
        else {
            throw AgentProcessStateError.invalidRecord
        }
    }
}
