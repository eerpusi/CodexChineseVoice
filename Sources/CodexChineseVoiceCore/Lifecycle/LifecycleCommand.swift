public enum LifecycleCommandError: Error, Equatable, Sendable {
    case invalidArguments([String])
}

public enum LifecycleCommand: Equatable, Sendable {
    case start
    case stop
    case status
    case config
    case doctor
    case runAgent
    case help

    public static let publicHelp = """
        CodexChineseVoice

        Usage: codex-chinese-voice [command]

        Commands:
          start   Start voice input in the background (default)
          stop    Stop the background agent
          status  Show whether the agent is running
          config  Save the Volcengine API key securely
          doctor  Check configuration, permissions, and agent status
        """

    public static func parse(_ arguments: [String]) throws -> LifecycleCommand {
        guard arguments.count <= 1 else {
            throw LifecycleCommandError.invalidArguments(arguments)
        }
        return switch arguments.first {
        case nil, "start": .start
        case "stop": .stop
        case "status": .status
        case "config": .config
        case "doctor": .doctor
        case "run-agent": .runAgent
        case "--help", "-h": .help
        default: throw LifecycleCommandError.invalidArguments(arguments)
        }
    }
}
