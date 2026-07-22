import Foundation
@preconcurrency import AVFAudio

extension AudioCapture {
    func receive(_ inputBuffer: AVAudioPCMBuffer, sessionID id: UInt64) {
        guard let resources = resources(for: id) else { return }
        let converter = resources.converter
        callbackProcessingLock.lock()

        let data: Data?
        do {
            data = try converter.convert(inputBuffer)
        } catch let error as AudioCaptureError {
            callbackProcessingLock.unlock()
            resources.gate.leave()
            fail(error, sessionID: id)
            return
        } catch {
            callbackProcessingLock.unlock()
            resources.gate.leave()
            fail(.conversionFailed(error.localizedDescription), sessionID: id)
            return
        }
        guard let data else {
            callbackProcessingLock.unlock()
            resources.gate.leave()
            return
        }
        for frame in appendFrames(data, sessionID: id) {
            resources.continuation.yield(frame)
        }
        callbackProcessingLock.unlock()
        resources.gate.leave()
    }

    private func appendFrames(_ data: Data, sessionID id: UInt64) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        guard active, sessionID == id else { return [] }
        return frameAccumulator.append(data)
    }

    private func resources(
        for id: UInt64
    ) -> (
        converter: PCMConverter,
        continuation: AsyncThrowingStream<Data, Error>.Continuation,
        gate: AudioCaptureCallbackGate
    )? {
        lock.lock()
        defer { lock.unlock() }
        guard active, acceptingCallbacks, sessionID == id,
              let converter,
              let continuation,
              let gate = callbackGate,
              gate.enter() else {
            return nil
        }
        return (converter, continuation, gate)
    }

    private func fail(_ error: AudioCaptureError, sessionID id: UInt64) {
        failureQueue.async { [weak self] in
            self?.finishSession(id: id, error: error)
        }
    }

    func finishSession(id requestedID: UInt64?, error: Error?) {
        let continuation: AsyncThrowingStream<Data, Error>.Continuation?
        let cleanupPlan: AudioCaptureCleanupPlan
        let converterToFinish: PCMConverter?
        var accumulator: AudioFrameAccumulator
        let gate: AudioCaptureCallbackGate?

        lifecycleLock.lock()
        lock.lock()
        if let requestedID, (!active || sessionID != requestedID) {
            lock.unlock()
            lifecycleLock.unlock()
            return
        }
        cleanupPlan = AudioCaptureCleanupPlan(
            active: active,
            tapInstalled: tapInstalled,
            hasConverter: converter != nil
        )
        continuation = self.continuation
        converterToFinish = error == nil ? converter : nil
        gate = callbackGate
        acceptingCallbacks = false
        gate?.close()
        lock.unlock()

        gate?.waitUntilIdle()

        if cleanupPlan.shouldRemoveTap {
            engine.inputNode.removeTap(onBus: 0)
        }
        if cleanupPlan.shouldStopEngine {
            engine.stop()
            engine.reset()
        }

        lock.lock()
        accumulator = frameAccumulator
        self.continuation = nil
        frameAccumulator = AudioFrameAccumulator(frameByteCount: Self.frameByteCount)
        active = false
        converter = nil
        callbackGate = nil
        tapInstalled = false
        lock.unlock()

        var terminalError = error
        var finalFrames: [Data] = []
        if terminalError == nil {
            do {
                finalFrames = accumulator.finish(
                    appending: try converterToFinish?.finish()
                )
            } catch {
                terminalError = error
            }
        }

        for frame in finalFrames {
            continuation?.yield(frame)
        }
        if let terminalError {
            continuation?.finish(throwing: terminalError)
        } else {
            continuation?.finish()
        }
        lifecycleLock.unlock()
    }
}
