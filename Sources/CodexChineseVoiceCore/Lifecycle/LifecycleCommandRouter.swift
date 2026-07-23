public protocol BackgroundProcessControlling: AnyObject {
    func start() throws -> BackgroundStartResult
    func stop() throws -> BackgroundStopResult
    func status() throws -> BackgroundProcessStatus
}

extension BackgroundProcessController: BackgroundProcessControlling {}

public enum LifecycleCommandRunResult: Equatable, Sendable {
    case message(String)
    case runAgent
    case configure
    case diagnose
}

public struct LifecycleCommandRouter {
    private let controller: any BackgroundProcessControlling

    public init(controller: any BackgroundProcessControlling) {
        self.controller = controller
    }

    public func run(_ command: LifecycleCommand) throws -> LifecycleCommandRunResult {
        switch command {
        case .start:
            return .message(Self.message(for: try controller.start()))
        case .stop:
            return .message(Self.message(for: try controller.stop()))
        case .status:
            return .message(Self.message(for: try controller.status()))
        case .config:
            return .configure
        case .doctor:
            return .diagnose
        case .runAgent:
            return .runAgent
        case .help:
            return .message(LifecycleCommand.publicHelp)
        }
    }
}

private extension LifecycleCommandRouter {
    static func message(for result: BackgroundStartResult) -> String {
        switch result {
        case let .started(pid):
            "CodexChineseVoice started (PID \(pid))."
        case let .alreadyRunning(pid):
            "CodexChineseVoice is already running (PID \(pid))."
        }
    }

    static func message(for result: BackgroundStopResult) -> String {
        switch result {
        case let .stopped(pid):
            "CodexChineseVoice stopped (PID \(pid))."
        case .notRunning:
            "CodexChineseVoice is not running."
        }
    }

    static func message(for status: BackgroundProcessStatus) -> String {
        switch status {
        case let .running(pid):
            "CodexChineseVoice is running (PID \(pid))."
        case .stopped:
            "CodexChineseVoice is stopped."
        }
    }
}
