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
    private let transport: any VolcengineTransport
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
        transport = URLSessionVolcengineTransport(session: session)
        requestIDOverride = requestID
        connectIDOverride = connectID
        self.language = language
    }

    init(
        apiKey: String,
        transport: any VolcengineTransport,
        requestID: String? = nil,
        connectID: String? = nil,
        language: String = "zh-CN"
    ) {
        self.apiKey = apiKey
        self.transport = transport
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

        let connection = try await transport.connect(request)
        defer { connection.close() }

        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await connection.send(clientFrame)

            try await withThrowingTaskGroup(of: WorkerResult.self) { group in
                group.addTask {
                    try await sendAudio(audio, on: connection)
                }
                group.addTask {
                    try await receiveEvents(from: connection, continuation: continuation)
                }

                do {
                    guard let first = try await group.next() else { return }
                    switch first {
                    case .receiverFinished:
                        connection.close()
                        group.cancelAll()
                    case .senderFinished:
                        _ = try await group.next()
                        group.cancelAll()
                    }
                } catch {
                    connection.close()
                    group.cancelAll()
                    throw error
                }
            }
        } onCancel: {
            connection.close()
        }
    }

    func sendAudio(
        _ audio: AsyncThrowingStream<Data, Error>,
        on connection: any VolcengineConnection
    ) async throws -> WorkerResult {
        var sequence = 2
        for try await chunk in audio {
            try Task.checkCancellation()
            let frame = try VolcengineProtocol.audioFrame(
                chunk,
                sequence: sequence,
                isFinal: false
            )
            try await connection.send(frame)
            sequence += 1
        }

        try Task.checkCancellation()
        let finalFrame = try VolcengineProtocol.audioFrame(
            Data(),
            sequence: sequence,
            isFinal: true
        )
        try await connection.send(finalFrame)
        return .senderFinished
    }

    func receiveEvents(
        from connection: any VolcengineConnection,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    ) async throws -> WorkerResult {
        var lastPartialText: String?
        while true {
            do {
                try Task.checkCancellation()
                let message = try await connection.receive()
                switch message {
                case .data(let data):
                    let serverMessage = try VolcengineProtocol.parseServerMessage(data)
                    guard let event = serverMessage.transcript else { continue }
                    if !event.isFinal {
                        guard event.text != lastPartialText else { continue }
                        lastPartialText = event.text
                    }
                    if case .terminated = continuation.yield(event) {
                        throw CancellationError()
                    }
                    if event.isFinal {
                        return .receiverFinished
                    }
                case .text:
                    throw VolcengineProviderError.unexpectedTextMessage
                case .closed:
                    throw VolcengineProviderError.connectionClosed
                }
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                throw error
            }
        }
    }
}
