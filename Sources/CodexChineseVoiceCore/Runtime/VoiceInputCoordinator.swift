import Foundation

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
    func finalize(_ text: String) throws
    func cancel()
}

@MainActor
public final class VoiceInputCoordinator {
    private let hotkey: VoiceInputHotkeySource
    private let audio: VoiceInputAudioSource
    private let provider: ASRProvider
    private let composer: VoiceInputComposer
    private let report: @MainActor (String) -> Void

    private var sessionTask: Task<Void, Never>?
    private var nextSessionID: UInt64 = 0
    private var activeSessionID: UInt64?
    private var currentText = ""
    private var released = false
    private var didFinalize = false
    private var providerDidFinish = false

    public init(
        hotkey: VoiceInputHotkeySource,
        audio: VoiceInputAudioSource,
        provider: ASRProvider,
        composer: VoiceInputComposer,
        report: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.hotkey = hotkey
        self.audio = audio
        self.provider = provider
        self.composer = composer
        self.report = report
    }

    public func run() async {
        do {
            try hotkey.start()
        } catch {
            report("无法监听 Command+R：\(error.localizedDescription)")
            return
        }
        defer { hotkey.stop(); cancelSession() }

        for await event in hotkey.events {
            switch event {
            case .began:
                beginSession()
            case .ended:
                endSession()
            }
        }
    }

    private func beginSession() {
        guard sessionTask == nil else { return }
        do {
            try composer.begin()
            let audioStream = try audio.start()
            currentText = ""
            released = false
            didFinalize = false
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
            report("无法开始录音：\(error.localizedDescription)")
            audio.stop()
            composer.cancel()
        }
    }

    private func endSession() {
        guard sessionTask != nil else { return }
        released = true
        audio.stop()
        if providerDidFinish {
            finishReleasedSession()
        }
    }

    private func receive(_ event: TranscriptEvent, sessionID: UInt64) {
        guard activeSessionID == sessionID else { return }
        currentText = event.text
        do {
            if event.isFinal {
                try composer.finalize(event.text)
                didFinalize = true
            } else {
                try composer.replacePartial(event.text)
            }
        } catch {
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
        if !didFinalize && !currentText.isEmpty {
            do {
                try composer.finalize(currentText)
            } catch {
                report("无法完成 Codex 输入：\(error.localizedDescription)")
                composer.cancel()
            }
        } else if !didFinalize {
            composer.cancel()
        }
        clearSession()
    }

    private func providerCancelled(sessionID: UInt64) {
        guard activeSessionID == sessionID else { return }
        audio.stop()
        if !didFinalize { composer.cancel() }
        clearSession()
    }

    private func providerFailed(_ error: Error, sessionID: UInt64) {
        guard activeSessionID == sessionID else { return }
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
        currentText = ""
        released = false
        didFinalize = false
        providerDidFinish = false
    }
}
