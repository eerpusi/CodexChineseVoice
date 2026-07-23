import Darwin
import Foundation

public enum POSIXSpawnOperation: Equatable, Sendable {
    case initializeFileActions
    case redirectStandardInput
    case redirectStandardOutput
    case redirectStandardError
    case initializeAttributes
    case configureFlags
    case spawn
}

public struct POSIXSpawnError: Error, Equatable, Sendable {
    public let operation: POSIXSpawnOperation
    public let code: Int32

    public init(operation: POSIXSpawnOperation, code: Int32) {
        self.operation = operation
        self.code = code
    }
}

public struct POSIXSpawnExecutor: AgentProcessSpawning, Sendable {
    public init() {}

    public func spawn(_ request: DetachedSpawnRequest) throws -> Int32 {
        let executablePath = request.executableURL.path
        let argumentValues = [executablePath] + request.arguments
        let allocatedArguments = argumentValues.map { strdup($0) }
        guard allocatedArguments.allSatisfy({ $0 != nil }) else {
            allocatedArguments.forEach { free($0) }
            throw POSIXSpawnError(operation: .spawn, code: ENOMEM)
        }
        defer { allocatedArguments.forEach { free($0) } }

        var arguments = allocatedArguments + [nil]
        let emptyEnvironment = UnsafeMutablePointer<
            UnsafeMutablePointer<CChar>?
        >.allocate(capacity: 1)
        emptyEnvironment.initialize(to: nil)
        defer {
            emptyEnvironment.deinitialize(count: 1)
            emptyEnvironment.deallocate()
        }
        let environment = request.inheritsEnvironment
            ? environ
            : emptyEnvironment

        var fileActions: posix_spawn_file_actions_t?
        var result = posix_spawn_file_actions_init(&fileActions)
        guard result == 0 else {
            throw POSIXSpawnError(
                operation: .initializeFileActions,
                code: result
            )
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        if request.redirectsStandardStreamsToNull {
            result = posix_spawn_file_actions_addopen(
                &fileActions,
                STDIN_FILENO,
                "/dev/null",
                O_RDONLY,
                0
            )
            guard result == 0 else {
                throw POSIXSpawnError(
                    operation: .redirectStandardInput,
                    code: result
                )
            }
            result = posix_spawn_file_actions_addopen(
                &fileActions,
                STDOUT_FILENO,
                "/dev/null",
                O_WRONLY,
                0
            )
            guard result == 0 else {
                throw POSIXSpawnError(
                    operation: .redirectStandardOutput,
                    code: result
                )
            }
            result = posix_spawn_file_actions_addopen(
                &fileActions,
                STDERR_FILENO,
                "/dev/null",
                O_WRONLY,
                0
            )
            guard result == 0 else {
                throw POSIXSpawnError(
                    operation: .redirectStandardError,
                    code: result
                )
            }
        }

        var attributes: posix_spawnattr_t?
        result = posix_spawnattr_init(&attributes)
        guard result == 0 else {
            throw POSIXSpawnError(
                operation: .initializeAttributes,
                code: result
            )
        }
        defer { posix_spawnattr_destroy(&attributes) }

        var flags: Int16 = 0
        if request.createSession {
            flags |= Int16(POSIX_SPAWN_SETSID)
        }
        if request.closesUnrelatedFileDescriptors {
            flags |= Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)
        }
        result = posix_spawnattr_setflags(&attributes, flags)
        guard result == 0 else {
            throw POSIXSpawnError(operation: .configureFlags, code: result)
        }

        var pid: Int32 = 0
        result = executablePath.withCString { executable in
            arguments.withUnsafeMutableBufferPointer { argumentBuffer in
                posix_spawn(
                    &pid,
                    executable,
                    &fileActions,
                    &attributes,
                    argumentBuffer.baseAddress!,
                    environment
                )
            }
        }
        guard result == 0 else {
            throw POSIXSpawnError(operation: .spawn, code: result)
        }
        return pid
    }
}
