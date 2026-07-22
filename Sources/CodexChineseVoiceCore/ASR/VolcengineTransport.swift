import Foundation

enum VolcengineTransportMessage: Equatable, Sendable {
    case data(Data)
    case text(String)
    case closed
}

protocol VolcengineConnection: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> VolcengineTransportMessage
    func close()
}

protocol VolcengineTransport: Sendable {
    func connect(_ request: URLRequest) async throws -> any VolcengineConnection
}

struct URLSessionVolcengineTransport: VolcengineTransport, Sendable {
    let session: URLSession

    func connect(_ request: URLRequest) async throws -> any VolcengineConnection {
        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionVolcengineConnection(task: task)
    }
}

private final class URLSessionVolcengineConnection: VolcengineConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ data: Data) async throws {
        try await task.send(.data(data))
    }

    func receive() async throws -> VolcengineTransportMessage {
        do {
            switch try await task.receive() {
            case .data(let data):
                return .data(data)
            case .string(let text):
                return .text(text)
            @unknown default:
                return .text("")
            }
        } catch {
            if task.closeCode == .normalClosure || task.closeCode == .goingAway {
                return .closed
            }
            throw error
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
