import Foundation

public struct DetachedSpawnRequest: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let createSession: Bool
    public let redirectsStandardStreamsToNull: Bool
    public let closesUnrelatedFileDescriptors: Bool
    public let inheritsEnvironment: Bool

    public init(
        executableURL: URL,
        arguments: [String],
        createSession: Bool,
        redirectsStandardStreamsToNull: Bool,
        closesUnrelatedFileDescriptors: Bool,
        inheritsEnvironment: Bool
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.createSession = createSession
        self.redirectsStandardStreamsToNull = redirectsStandardStreamsToNull
        self.closesUnrelatedFileDescriptors = closesUnrelatedFileDescriptors
        self.inheritsEnvironment = inheritsEnvironment
    }
}

public protocol AgentProcessSpawning {
    func spawn(_ request: DetachedSpawnRequest) throws -> Int32
}

public struct DetachedAgentProcessLauncher: AgentProcessLaunching {
    private let spawner: any AgentProcessSpawning

    public init() {
        spawner = POSIXSpawnExecutor()
    }

    public init(spawner: any AgentProcessSpawning) {
        self.spawner = spawner
    }

    public func launch(
        executableURL: URL,
        arguments: [String]
    ) throws -> Int32 {
        try spawner.spawn(
            DetachedSpawnRequest(
                executableURL: executableURL.standardizedFileURL
                    .resolvingSymlinksInPath(),
                arguments: arguments,
                createSession: true,
                redirectsStandardStreamsToNull: true,
                closesUnrelatedFileDescriptors: true,
                inheritsEnvironment: true
            )
        )
    }
}
