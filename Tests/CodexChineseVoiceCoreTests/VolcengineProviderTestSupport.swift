import Foundation
@testable import CodexChineseVoiceCore

func collect(
    _ stream: AsyncThrowingStream<TranscriptEvent, Error>
) async throws -> [TranscriptEvent] {
    var events: [TranscriptEvent] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

func finishedAudioStream(
    _ chunks: [Data] = []
) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
    }
}

enum TestTimeout: Error {
    case expired
}

func waitForSentFrames(
    _ connection: FakeVolcengineConnection,
    count: Int
) async throws {
    for _ in 0..<100 {
        if connection.sentFrames.count >= count {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw TestTimeout.expired
}

func waitForConnectionClose(
    _ connection: FakeVolcengineConnection
) async -> Bool {
    for _ in 0..<100 {
        if connection.closed {
            return true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
}

final class FakeVolcengineTransport: VolcengineTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let connection: FakeVolcengineConnection
    private var capturedRequests: [URLRequest] = []

    init(connection: FakeVolcengineConnection) {
        self.connection = connection
    }

    var requests: [URLRequest] {
        lock.withLock { capturedRequests }
    }

    func connect(_ request: URLRequest) async throws -> any VolcengineConnection {
        lock.withLock {
            capturedRequests.append(request)
        }
        return connection
    }
}

final class FakeVolcengineConnection: VolcengineConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var incoming: [VolcengineTransportMessage]
    private var sent: [Data] = []
    private var waiter: CheckedContinuation<VolcengineTransportMessage, Error>?
    private var sendWaiter: CheckedContinuation<Void, Error>?
    private var isClosed = false
    private var finalAudioSent = false
    private let releaseIncomingAfterFinalAudio: Bool
    private let suspendHandshakeUntilClose: Bool

    init(
        incoming: [VolcengineTransportMessage] = [],
        releaseIncomingAfterFinalAudio: Bool = false,
        suspendHandshakeUntilClose: Bool = false
    ) {
        self.incoming = incoming
        self.releaseIncomingAfterFinalAudio = releaseIncomingAfterFinalAudio
        self.suspendHandshakeUntilClose = suspendHandshakeUntilClose
    }

    var sentFrames: [Data] {
        lock.withLock { sent }
    }

    var closed: Bool {
        lock.withLock { isClosed }
    }

    func send(_ data: Data) async throws {
        let (pending, shouldSuspend) = try lock.withLock {
            () throws -> (
                (
                    CheckedContinuation<VolcengineTransportMessage, Error>,
                    VolcengineTransportMessage
                )?,
                Bool
            ) in
            guard !isClosed else { throw CancellationError() }
            sent.append(data)
            if isFinalAudioFrame(data) {
                finalAudioSent = true
            }
            guard finalAudioSent,
                  let waiter,
                  !incoming.isEmpty else {
                return (nil, suspendHandshakeUntilClose && sent.count == 1)
            }
            self.waiter = nil
            return (
                (waiter, incoming.removeFirst()),
                suspendHandshakeUntilClose && sent.count == 1
            )
        }
        if let pending {
            pending.0.resume(returning: pending.1)
        }
        guard shouldSuspend else { return }

        try await withCheckedThrowingContinuation { continuation in
            let alreadyClosed = lock.withLock {
                if isClosed {
                    return true
                }
                sendWaiter = continuation
                return false
            }
            if alreadyClosed {
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    func receive() async throws -> VolcengineTransportMessage {
        try await withCheckedThrowingContinuation { continuation in
            let result: Result<VolcengineTransportMessage, Error>? = lock.withLock {
                if !incoming.isEmpty,
                   !releaseIncomingAfterFinalAudio || finalAudioSent {
                    return .success(incoming.removeFirst())
                }
                if isClosed {
                    return .failure(CancellationError())
                }
                waiter = continuation
                return nil
            }
            if let result {
                continuation.resume(with: result)
            }
        }
    }

    func enqueue(_ message: VolcengineTransportMessage) {
        let pending = lock.withLock {
            () -> CheckedContinuation<VolcengineTransportMessage, Error>? in
            if let waiter {
                self.waiter = nil
                return waiter
            }
            incoming.append(message)
            return nil
        }
        pending?.resume(returning: message)
    }

    func close() {
        let pending = lock.withLock {
            () -> (
                CheckedContinuation<VolcengineTransportMessage, Error>?,
                CheckedContinuation<Void, Error>?
            ) in
            guard !isClosed else { return (nil, nil) }
            isClosed = true
            defer {
                waiter = nil
                sendWaiter = nil
            }
            return (waiter, sendWaiter)
        }
        pending.0?.resume(throwing: CancellationError())
        pending.1?.resume(throwing: CancellationError())
    }

    private func isFinalAudioFrame(_ data: Data) -> Bool {
        data.count >= 2 && data[1] == 0x23
    }
}
