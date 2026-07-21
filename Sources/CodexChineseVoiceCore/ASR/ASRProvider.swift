import Foundation

public protocol ASRProvider: Sendable {
    func events(
        audio: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<TranscriptEvent, Error>
}
