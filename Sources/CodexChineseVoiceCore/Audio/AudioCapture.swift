import Foundation
@preconcurrency import AVFAudio

public final class AudioCapture: @unchecked Sendable {
    public static let sampleRate: Double = 16_000
    public static let channelCount: AVAudioChannelCount = 1
    public static let bitsPerSample = 16
    public static let frameByteCount = 6_400

    private static let tapBufferSize: AVAudioFrameCount = 4_096

    let lifecycleLock = NSRecursiveLock()
    let lock = NSLock()
    let callbackProcessingLock = NSLock()
    let failureQueue = DispatchQueue(
        label: "CodexChineseVoice.AudioCapture.failure",
        qos: .userInitiated
    )
    let engine = AVAudioEngine()
    var converter: PCMConverter?
    var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    var callbackGate: AudioCaptureCallbackGate?
    var sessionID: UInt64 = 0
    var tapInstalled = false
    var active = false
    var acceptingCallbacks = false
    var frameAccumulator = AudioFrameAccumulator(frameByteCount: 6_400)

    public init() {}

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    public static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func makeAudioStream() -> (
        stream: AsyncThrowingStream<Data, Error>,
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) {
        AsyncThrowingStream.makeStream(
            of: Data.self,
            throwing: Error.self,
            bufferingPolicy: .unbounded
        )
    }

    /// Starts a new microphone stream.
    ///
    /// If permission is undetermined, `requestMicrophonePermission()` must be called
    /// first. This keeps `start()` synchronous and avoids blocking the UI thread on the
    /// system permission dialog.
    public func start() throws -> AsyncThrowingStream<Data, Error> {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        let (stream, pendingContinuation) = Self.makeAudioStream()
        lock.lock()
        guard !active else {
            lock.unlock()
            throw AudioCaptureError.alreadyRunning
        }

        sessionID &+= 1
        let id = sessionID
        active = true
        acceptingCallbacks = true
        callbackGate = AudioCaptureCallbackGate()
        frameAccumulator = AudioFrameAccumulator(frameByteCount: Self.frameByteCount)
        continuation = pendingContinuation
        pendingContinuation.onTermination = { [weak self] _ in
            self?.failureQueue.async { [weak self] in
                self?.finishSession(id: id, error: nil)
            }
        }
        lock.unlock()

        do {
            try validateMicrophonePermission()
            try beginEngine(for: id)
            return stream
        } catch {
            finishSession(id: id, error: error)
            throw error
        }
    }

    /// Stops the active recording session. Calling this method while idle is harmless.
    public func stop() {
        finishSession(id: nil, error: nil)
    }

    deinit {
        stop()
    }

    private func validateMicrophonePermission() throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw AudioCaptureError.microphonePermissionDenied
        case .undetermined:
            throw AudioCaptureError.microphonePermissionNotDetermined
        @unknown default:
            throw AudioCaptureError.microphonePermissionDenied
        }
    }

    private func beginEngine(for id: UInt64) throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioCaptureError.inputFormatUnavailable
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: Self.channelCount,
            interleaved: true
        ) else {
            throw AudioCaptureError.outputFormatUnavailable
        }

        let converter = try PCMConverter(
            inputFormat: inputFormat,
            outputFormat: outputFormat
        )

        lock.lock()
        guard active, sessionID == id else {
            lock.unlock()
            return
        }
        self.converter = converter
        lock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: inputFormat) {
            [weak self] buffer, _ in
            self?.receive(buffer, sessionID: id)
        }
        lock.lock()
        if active, sessionID == id {
            tapInstalled = true
        }
        lock.unlock()

        do {
            engine.prepare()
            try engine.start()
        } catch {
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }
    }

}
