import CodexChineseVoiceCore
import Foundation
import Observation

@MainActor
@Observable
final class VoiceApplicationModel {
    var state: VoiceApplicationState = .starting
    var hasConfiguredAPIKey = false
    var isRecording = false
    var inputLevel = 0.0

    private var runtimeTask: Task<Void, Never>?
    private var coordinator: VoiceInputCoordinator?

    func start() {
        guard runtimeTask == nil else { return }
        state = .starting
        runtimeTask = Task { [weak self] in
            await self?.startRuntime()
        }
    }

    func stop() {
        runtimeTask?.cancel()
        runtimeTask = nil
        coordinator?.stop()
        coordinator = nil
        isRecording = false
        inputLevel = 0
    }

    func restart() {
        stop()
        start()
    }

    func retryPermissionsIfReady() {
        let permissions = SystemPermissionProvider()
        guard state.shouldRetry(
            microphonePermission: permissions.microphonePermission,
            accessibilityTrusted: permissions.isAccessibilityTrusted(prompt: false)
        ) else {
            return
        }
        restart()
    }

    func saveAPIKey(_ apiKey: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        try ConfigFileStore.default.saveAPIKey(trimmedKey)
        restart()
    }

    private func startRuntime() async {
        do {
            let configuration = try ConfigurationLoader(
                store: ConfigFileStore.default
            ).load()
            hasConfiguredAPIKey = true

            try await PermissionPreflight(
                provider: SystemPermissionProvider()
            ).ensureReady()
            guard !Task.isCancelled else { return }

            let audio = AudioCapture(
                onLevel: { [weak self] level in
                    Task { @MainActor [weak self] in
                        guard self?.isRecording == true else { return }
                        self?.inputLevel = level
                    }
                },
                onRecordingChanged: { [weak self] isRecording in
                    Task { @MainActor [weak self] in
                        self?.isRecording = isRecording
                        if !isRecording {
                            self?.inputLevel = 0
                        }
                    }
                }
            )
            let coordinator = VoiceInputCoordinator(
                hotkey: CodexHotkeyMonitor(),
                audio: audio,
                provider: VolcengineProvider(apiKey: configuration.apiKey),
                composer: CodexComposerEditor(),
                report: { [weak self] message in
                    self?.state = .failed(.runtime(message))
                }
            )
            self.coordinator = coordinator
            state = .ready
            await coordinator.run()
            if !Task.isCancelled {
                state = .failed(.runtime("语音监听已停止"))
            }
        } catch let error as ConfigurationError {
            hasConfiguredAPIKey = error != .missingAPIKey
            state = .from(error)
        } catch let error as PermissionPreflightError {
            state = .from(error)
        } catch {
            state = .failed(.runtime(error.localizedDescription))
        }
        runtimeTask = nil
    }
}
