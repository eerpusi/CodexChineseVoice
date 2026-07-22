import Foundation

/// Errors raised by the WebSocket adapter before or outside the wire protocol.
public enum VolcengineProviderError: Error, Equatable, Sendable {
    case missingAPIKey
    case unexpectedTextMessage
    case connectionClosed
}

/// Streams PCM chunks to the Volcengine Agent Plan endpoint.
public struct VolcengineProvider: ASRProvider, Sendable {
    private let apiKey: String
    private let session: URLSession
    private let requestIDOverride: String?
    private let connectIDOverride: String?
    private let language: String

    public init(
        apiKey: String,
        session: URLSession = .shared,
        requestID: String? = nil,
        connectID: String? = nil,
        language: String = "zh-CN"
    ) {
        self.apiKey = apiKey
        self.session = session
        requestIDOverride = requestID
        connectIDOverride = connectID
        self.language = language
    }

    public func events(
        audio: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<TranscriptEvent, Error> {
        AsyncThrowingStream { continuation in
            let operation = Task { [self] in
                do {
                    try await run(audio: audio, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                operation.cancel()
            }
        }
    }
}

private extension VolcengineProvider {
    final class WebSocketBox: @unchecked Sendable {
        let task: URLSessionWebSocketTask

        init(_ task: URLSessionWebSocketTask) {
            self.task = task
        }
    }

    enum WorkerResult: Sendable {
        case senderFinished
        case receiverFinished
    }

    func run(
        audio: AsyncThrowingStream<Data, Error>,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    ) async throws {
        guard !apiKey.isEmpty else {
            throw VolcengineProviderError.missingAPIKey
        }
        let requestID = requestIDOverride ?? UUID().uuidString
        let connectID = connectIDOverride ?? UUID().uuidString

        let clientFrame = try VolcengineProtocol.clientRequest(
            requestID: requestID,
            language: language,
            sequence: 1
        )
        var request = URLRequest(url: VolcengineProtocol.webSocketURL)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(
            VolcengineProtocol.resourceID,
            forHTTPHeaderField: "X-Api-Resource-Id"
        )
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Connect-Id")
        request.setValue("1", forHTTPHeaderField: "X-Api-Sequence")

        let socket = WebSocketBox(session.webSocketTask(with: request))
        socket.task.resume()
        defer {
            socket.task.cancel(with: .normalClosure, reason: nil)
        }

        try Task.checkCancellation()
        try await socket.task.send(.data(clientFrame))

        try await withThrowingTaskGroup(of: WorkerResult.self) { group in
            group.addTask {
                try await sendAudio(audio, on: socket)
            }
            group.addTask {
                try await receiveEvents(from: socket, continuation: continuation)
            }

            do {
                guard let first = try await group.next() else { return }
                switch first {
                case .receiverFinished:
                    group.cancelAll()
                case .senderFinished:
                    _ = try await group.next()
                    group.cancelAll()
                }
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    func sendAudio(
        _ audio: AsyncThrowingStream<Data, Error>,
        on socket: WebSocketBox
    ) async throws -> WorkerResult {
        var sequence = 2
        for try await chunk in audio {
            try Task.checkCancellation()
            let frame = try VolcengineProtocol.audioFrame(
                chunk,
                sequence: sequence,
                isFinal: false
            )
            try await socket.task.send(.data(frame))
            sequence += 1
        }

        try Task.checkCancellation()
        let finalFrame = try VolcengineProtocol.audioFrame(
            Data(),
            sequence: sequence,
            isFinal: true
        )
        try await socket.task.send(.data(finalFrame))
        return .senderFinished
    }

    func receiveEvents(
        from socket: WebSocketBox,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    ) async throws -> WorkerResult {
        while true {
            do {
                try Task.checkCancellation()
                let message = try await socket.task.receive()
                switch message {
                case .data(let data):
                    let serverMessage = try VolcengineProtocol.parseServerMessage(data)
                    guard let event = serverMessage.transcript else { continue }
                    if case .terminated = continuation.yield(event) {
                        throw CancellationError()
                    }
                    if event.isFinal {
                        return .receiverFinished
                    }
                case .string:
                    throw VolcengineProviderError.unexpectedTextMessage
                @unknown default:
                    throw VolcengineProviderError.unexpectedTextMessage
                }
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                if socket.task.closeCode == .normalClosure
                    || socket.task.closeCode == .goingAway {
                    return .receiverFinished
                }
                throw error
            }
        }
    }
}
