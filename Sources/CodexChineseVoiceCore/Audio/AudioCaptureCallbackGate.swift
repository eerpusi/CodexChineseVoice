import Foundation

/// Coordinates audio callbacks with synchronous session shutdown.
final class AudioCaptureCallbackGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var accepting = true
    private var inFlight = 0

    func enter() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard accepting else { return false }
        inFlight += 1
        return true
    }

    func leave() {
        condition.lock()
        inFlight = max(0, inFlight - 1)
        if inFlight == 0 {
            condition.broadcast()
        }
        condition.unlock()
    }

    func close() {
        condition.lock()
        accepting = false
        condition.unlock()
    }

    func waitUntilIdle() {
        condition.lock()
        while inFlight > 0 {
            condition.wait()
        }
        condition.unlock()
    }
}
