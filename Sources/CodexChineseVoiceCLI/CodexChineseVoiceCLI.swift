import CodexChineseVoiceCore
import Foundation

@main
struct CodexChineseVoiceCLI {
    static func main() async {
        do {
            let command = try LifecycleCommand.parse(
                Array(CommandLine.arguments.dropFirst())
            )
            if command == .start {
                _ = try await prepareRuntime()
            }

            let result = try makeRouter().run(command)
            try await handle(result)
        } catch let error as LifecycleCommandError {
            writeError("无效命令：\(error)")
            writeError(LifecycleCommand.publicHelp)
            exit(2)
        } catch ConfigurationError.missingAPIKey {
            writeError("未找到 ARK_PLAN_API_KEY。请在菜单栏 App 设置中保存，或仅在当前终端导出它。")
            exit(2)
        } catch PermissionPreflightError.microphoneDenied {
            writeError("麦克风权限未开启。请在系统设置 > 隐私与安全性 > 麦克风中允许本程序。")
            exit(3)
        } catch PermissionPreflightError.accessibilityRequired {
            writeError("需要辅助功能权限才能监听 Command+R 并写入 Codex。请在系统设置中授权。")
            exit(4)
        } catch {
            writeError("操作失败：\(error.localizedDescription)")
            exit(1)
        }
    }

    private static func handle(_ result: LifecycleCommandRunResult) async throws {
        switch result {
        case let .message(message):
            print(message)
        case .runAgent:
            let configuration = try await prepareRuntime()
            await runAgent(configuration: configuration)
        case .configure:
            try saveEnvironmentKey()
        case .diagnose:
            try diagnose()
        }
    }

    private static func prepareRuntime() async throws -> AppConfiguration {
        let configuration = try ConfigurationLoader(
            store: ConfigFileStore.default
        ).load()
        try await PermissionPreflight(
            provider: SystemPermissionProvider()
        ).ensureReady()
        return configuration
    }

    private static func runAgent(configuration: AppConfiguration) async {
        let coordinator = await MainActor.run {
            VoiceInputCoordinator(
                hotkey: CodexHotkeyMonitor(),
                audio: AudioCapture(),
                provider: VolcengineProvider(apiKey: configuration.apiKey),
                composer: CodexComposerEditor(),
                report: { message in writeError(message) }
            )
        }

        writeError("CodexChineseVoice 已启动。仅 Codex 位于前台时，按住 Command+R 录音，松开结束。")
        await coordinator.run()
    }

    private static func makeRouter() -> LifecycleCommandRouter {
        let executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let stateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexChineseVoice", isDirectory: true)
            .appendingPathComponent("agent.json")
        let controller = BackgroundProcessController(
            store: PIDFileStore(fileURL: stateURL),
            inspector: SystemAgentProcessInspector(),
            launcher: DetachedAgentProcessLauncher(),
            signaler: SystemAgentProcessSignaler(),
            executableURL: executableURL
        )
        return LifecycleCommandRouter(controller: controller)
    }

    private static func saveEnvironmentKey() throws {
        let key = ProcessInfo.processInfo.environment["ARK_PLAN_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            throw ConfigurationError.missingAPIKey
        }
        try ConfigFileStore.default.saveAPIKey(key)
        print("API Key 已安全保存；未显示其内容。")
    }

    private static func diagnose() throws {
        let hasConfiguration = (try? ConfigurationLoader(
            store: ConfigFileStore.default
        ).load()) != nil
        let permissions = SystemPermissionProvider()
        let microphone = permissions.microphonePermission == .granted
        let accessibility = permissions.isAccessibilityTrusted(prompt: false)
        let process = try makeRouter().run(.status)

        print("API Key: \(hasConfiguration ? "已配置" : "未配置")")
        print("麦克风权限: \(microphone ? "已授权" : "未授权")")
        print("辅助功能权限: \(accessibility ? "已授权" : "未授权")")
        if case let .message(status) = process {
            print(status)
        }
    }

    private static func writeError(_ message: String) {
        let line = Data((message + "\n").utf8)
        try? FileHandle.standardError.write(contentsOf: line)
    }
}
