import Foundation
import OSLog

private let voiceInputLogger = Logger(
    subsystem: "com.lianenguang.CodexChineseVoice",
    category: "VoiceInput"
)

public enum VoiceInputHotkeyEvent: Sendable {
    case began
    case ended
}

public protocol VoiceInputHotkeySource: AnyObject {
    var events: AsyncStream<VoiceInputHotkeyEvent> { get }
    func start() throws
    func stop()
}

public protocol VoiceInputAudioSource: AnyObject {
    func start() throws -> AsyncThrowingStream<Data, Error>
    func stop()
}

public protocol VoiceInputComposer: AnyObject {
    func begin() throws
    func replacePartial(_ text: String) throws
    func complete(_ text: String, submit: Bool) throws
    func cancel()
}

@MainActor
public final class VoiceInputCoordinator {
    private let hotkey: VoiceInputHotkeySource
    private let audio: VoiceInputAudioSource
    private let provider: ASRProvider
    private let composer: VoiceInputComposer
    private let autoSendEnabled: @MainActor () -> Bool
    private let report: @MainActor (String) -> Void

    private var sessionTask: Task<Void, Never>?
    private var nextSessionID: UInt64 = 0
    private var activeSessionID: UInt64?
    private var finalText: String?
    private var released = false
    private var providerDidFinish = false

    public init(
        hotkey: VoiceInputHotkeySource,
        audio: VoiceInputAudioSource,
        provider: ASRProvider,
        composer: VoiceInputComposer,
        autoSendEnabled: @escaping @MainActor () -> Bool = { true },
        report: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.hotkey = hotkey
        self.audio = audio
        self.provider = provider
        self.composer = composer
        self.autoSendEnabled = autoSendEnabled
        self.report = report
    }

    public func run() async {
        voiceInputLogger.info("voice input coordinator starting")
        do {
            try hotkey.start()
        } catch {
            voiceInputLogger.error("hotkey monitor start failed")
            report("无法监听 Command+R：\(error.localizedDescription)")
            return
        }
        defer {
            hotkey.stop()
            cancelSession()
            voiceInputLogger.info("voice input coordinator stopped")
        }

        for await event in hotkey.events {
            switch event {
            case .began:
                voiceInputLogger.info("recording begin event received")
                beginSession()
            case .ended:
                voiceInputLogger.info("recording end event received")
                endSession()
            }
        }
    }

    public func stop() {
        cancelSession()
        hotkey.stop()
    }

    private func beginSession() {
        guard sessionTask == nil else { return }
        do {
            try composer.begin()
            let audioStream = try audio.start()
            finalText = nil
            released = false
            providerDidFinish = false
            nextSessionID &+= 1
            let sessionID = nextSessionID
            activeSessionID = sessionID
            let provider = self.provider
            sessionTask = Task { [weak self] in
                do {
                    for try await event in provider.events(audio: audioStream) {
                        guard !Task.isCancelled else { return }
                        self?.receive(event, sessionID: sessionID)
                    }
                    self?.providerFinished(sessionID: sessionID)
                } catch is CancellationError {
                    self?.providerCancelled(sessionID: sessionID)
                } catch {
                    self?.providerFailed(error, sessionID: sessionID)
                }
            }
        } catch {
            voiceInputLogger.error(
                "recording session start failed: \(error.localizedDescription, privacy: .public)"
            )
            report("无法开始录音：\(error.localizedDescription)")
            audio.stop()
            composer.cancel()
        }
    }

    private func endSession() {
        guard sessionTask != nil else { return }
        released = true
        audio.stop()
        voiceInputLogger.info("audio capture stopped")
        if providerDidFinish {
            finishReleasedSession()
        }
    }

    private func receive(_ event: TranscriptEvent, sessionID: UInt64) {
        guard activeSessionID == sessionID else { return }
        if event.isFinal {
            finalText = event.text
        }
        do {
            try composer.replacePartial(event.text)
        } catch {
            voiceInputLogger.error(
                "composer update failed: \(error.localizedDescription, privacy: .public)"
            )
            report("无法更新 Codex 输入框：\(error.localizedDescription)")
            cancelSession()
        }
    }

    private func providerFinished(sessionID: UInt64) {
        guard activeSessionID == sessionID else { return }
        providerDidFinish = true
        guard released else { return }
        finishReleasedSession()
    }

    private func finishReleasedSession() {
        guard let finalText, !finalText.isEmpty else {
            composer.cancel()
            clearSession()
            return
        }
        do {
            try composer.complete(finalText, submit: autoSendEnabled())
        } catch {
            voiceInputLogger.error(
                "composer finalization failed: \(error.localizedDescription, privacy: .public)"
            )
            report("无法完成 Codex 输入：\(error.localizedDescription)")
            composer.cancel()
        }
        clearSession()
    }

    private func providerCancelled(sessionID: UInt64) {
        guard activeSessionID == sessionID else { return }
        audio.stop()
        composer.cancel()
        clearSession()
    }

    private func providerFailed(_ error: Error, sessionID: UInt64) {
        guard activeSessionID == sessionID else { return }
        voiceInputLogger.error(
            "speech recognition failed: \(error.localizedDescription, privacy: .public)"
        )
        report("语音识别失败：\(error.localizedDescription)")
        audio.stop()
        composer.cancel()
        clearSession()
    }

    private func cancelSession() {
        guard sessionTask != nil else { return }
        sessionTask?.cancel()
        audio.stop()
        composer.cancel()
        clearSession()
    }

    private func clearSession() {
        sessionTask = nil
        activeSessionID = nil
        finalText = nil
        released = false
        providerDidFinish = false
    }
}
