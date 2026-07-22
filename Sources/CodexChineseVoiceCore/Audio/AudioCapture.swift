import Foundation
@preconcurrency import AVFAudio

public enum AudioCaptureError: Error, LocalizedError, Sendable, Equatable {
    case alreadyRunning
    case microphonePermissionDenied
    case microphonePermissionNotDetermined
    case inputFormatUnavailable
    case outputFormatUnavailable
    case converterUnavailable
    case engineStartFailed(String)
    case conversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Microphone capture is already running."
        case .microphonePermissionDenied:
            return "Microphone access is denied. Enable it in System Settings > Privacy & Security > Microphone."
        case .microphonePermissionNotDetermined:
            return "Microphone access has not been requested. Request microphone permission, then start capture again."
        case .inputFormatUnavailable:
            return "The microphone did not provide a usable input format."
        case .outputFormatUnavailable:
            return "The 16 kHz mono 16-bit PCM output format is unavailable."
        case .converterUnavailable:
            return "The microphone audio converter could not be created."
        case let .engineStartFailed(message):
            return "The audio engine could not start: \(message)"
        case let .conversionFailed(message):
            return "Microphone audio conversion failed: \(message)"
        }
    }
}

public final class AudioCapture: @unchecked Sendable {
    public static let sampleRate: Double = 16_000
    public static let channelCount: AVAudioChannelCount = 1
    public static let bitsPerSample = 16

    private static let tapBufferSize: AVAudioFrameCount = 4_096

    private let lifecycleLock = NSRecursiveLock()
    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var sessionID: UInt64 = 0
    private var tapInstalled = false
    private var active = false

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

    /// Starts a new microphone stream.
    ///
    /// If permission is undetermined, `requestMicrophonePermission()` must be called
    /// first. This keeps `start()` synchronous and avoids blocking the UI thread on the
    /// system permission dialog.
    public func start() throws -> AsyncThrowingStream<Data, Error> {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        let (stream, pendingContinuation) = AsyncThrowingStream<Data, Error>.makeStream(
            of: Data.self,
            throwing: Error.self,
            bufferingPolicy: .bufferingNewest(16)
        )
        lock.lock()
        guard !active else {
            lock.unlock()
            throw AudioCaptureError.alreadyRunning
        }

        sessionID &+= 1
        let id = sessionID
        active = true
        continuation = pendingContinuation
        pendingContinuation.onTermination = { [weak self] _ in
            self?.finishSession(id: id, error: nil)
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

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterUnavailable
        }
        converter.primeMethod = .none

        lock.lock()
        guard active, sessionID == id else {
            lock.unlock()
            return
        }
        self.converter = converter
        self.outputFormat = outputFormat
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

    private func receive(_ inputBuffer: AVAudioPCMBuffer, sessionID id: UInt64) {
        guard let resources = resources(for: id) else { return }
        let converter = resources.converter

        let inputRate = inputBuffer.format.sampleRate
        guard inputRate > 0 else {
            fail(AudioCaptureError.inputFormatUnavailable, sessionID: id)
            return
        }

        let estimatedFrames = max(
            Int(inputBuffer.frameLength),
            Int(ceil(Double(inputBuffer.frameLength) * Self.sampleRate / inputRate)) + 1
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: resources.outputFormat,
            frameCapacity: AVAudioFrameCount(estimatedFrames)
        ) else {
            fail(AudioCaptureError.outputFormatUnavailable, sessionID: id)
            return
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) {
            _, inputStatus in
            guard !suppliedInput else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        if status == .error {
            let message = conversionError?.localizedDescription ?? "unknown converter error"
            fail(AudioCaptureError.conversionFailed(message), sessionID: id)
            return
        }

        guard outputBuffer.frameLength > 0,
              isActive(id),
              let data = pcmData(from: outputBuffer) else {
            return
        }
        resources.continuation.yield(data)
    }

    private func pcmData(from buffer: AVAudioPCMBuffer) -> Data? {
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Int16>.size
        guard byteCount > 0,
              let channels = buffer.int16ChannelData else {
            return nil
        }
        let samples = channels.pointee
        return Data(bytes: samples, count: byteCount)
    }

    private func resources(
        for id: UInt64
    ) -> (converter: AVAudioConverter, outputFormat: AVAudioFormat, continuation: AsyncThrowingStream<Data, Error>.Continuation)? {
        lock.lock()
        defer { lock.unlock() }
        guard active, sessionID == id,
              let converter,
              let outputFormat,
              let continuation else {
            return nil
        }
        return (converter, outputFormat, continuation)
    }

    private func isActive(_ id: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return active && sessionID == id
    }

    private func fail(_ error: AudioCaptureError, sessionID id: UInt64) {
        finishSession(id: id, error: error)
    }

    private func finishSession(id requestedID: UInt64?, error: Error?) {
        let continuation: AsyncThrowingStream<Data, Error>.Continuation?
        let shouldCleanUp: Bool

        lifecycleLock.lock()
        lock.lock()
        if let requestedID, (!active || sessionID != requestedID) {
            lock.unlock()
            lifecycleLock.unlock()
            return
        }
        shouldCleanUp = active || tapInstalled || converter != nil
        continuation = self.continuation
        self.continuation = nil
        active = false
        converter = nil
        outputFormat = nil
        tapInstalled = false
        lock.unlock()

        if shouldCleanUp {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        lifecycleLock.unlock()

        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
    }
}
