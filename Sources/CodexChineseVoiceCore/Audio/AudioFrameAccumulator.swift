import Foundation

public struct AudioFrameAccumulator: Sendable {
    public let frameByteCount: Int
    private var buffered = Data()

    public init(frameByteCount: Int) {
        precondition(frameByteCount > 0)
        self.frameByteCount = frameByteCount
    }

    public mutating func append(_ data: Data) -> [Data] {
        buffered.append(data)
        var frames: [Data] = []
        while buffered.count >= frameByteCount {
            frames.append(Data(buffered.prefix(frameByteCount)))
            buffered.removeFirst(frameByteCount)
        }
        return frames
    }

    public mutating func flush() -> Data? {
        guard !buffered.isEmpty else { return nil }
        let remainder = buffered
        buffered.removeAll(keepingCapacity: true)
        return remainder
    }

    mutating func finish(appending tail: Data?) -> [Data] {
        var frames = tail.map { append($0) } ?? []
        if let remainder = flush() {
            frames.append(remainder)
        }
        return frames
    }
}
