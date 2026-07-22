import CodexChineseVoiceCore
import Foundation

@main
struct CodexChineseVoiceCLI {
    static func main() async {
        if CommandLine.arguments.contains("--help") {
            printHelp()
            return
        }

        let configuration: AppConfiguration
        do {
            configuration = try ConfigurationLoader(
                store: ConfigFileStore.default
            ).load()
        } catch ConfigurationError.missingAPIKey {
            writeError(
                "未找到 ARK_PLAN_API_KEY。请在当前终端导出它，或配置 ~/.config/codex-chinese-voice/config.toml。"
            )
            exit(2)
        } catch {
            writeError("读取配置失败：\(error.localizedDescription)")
            exit(2)
        }

        do {
            try await PermissionPreflight(
                provider: SystemPermissionProvider()
            ).ensureReady()
        } catch PermissionPreflightError.microphoneDenied {
            writeError(
                "麦克风权限未开启。请在系统设置 > 隐私与安全性 > 麦克风中允许本程序，然后重新运行。"
            )
            exit(3)
        } catch PermissionPreflightError.accessibilityRequired {
            writeError(
                "需要辅助功能权限才能监听 Command+R 并写入 Codex。请在系统设置中授权后重新运行。"
            )
            exit(4)
        } catch {
            writeError("检查 macOS 权限失败：\(error.localizedDescription)")
            exit(3)
        }

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

    private static func printHelp() {
        print(
            """
            CodexChineseVoice

            Hold Command+R while the Codex desktop app is frontmost to dictate Chinese text.
            The message is never submitted automatically.

            Configuration:
              ARK_PLAN_API_KEY                 process environment (preferred)
              ~/.config/codex-chinese-voice/config.toml
            """
        )
    }

    private static func writeError(_ message: String) {
        let line = Data((message + "\n").utf8)
        try? FileHandle.standardError.write(contentsOf: line)
    }
}
