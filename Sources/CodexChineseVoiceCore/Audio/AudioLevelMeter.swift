import Foundation

public enum AudioLevelMeter {
    private static let decibelFloor = -50.0

    public static func normalizedLevel(pcm16LE data: Data) -> Double {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return 0 }

        var squaredSum = 0.0
        data.withUnsafeBytes { bytes in
            for offset in stride(from: 0, to: sampleCount * 2, by: 2) {
                let bits = UInt16(bytes[offset])
                    | UInt16(bytes[offset + 1]) << 8
                let sample = Double(Int16(bitPattern: bits)) / Double(Int16.max)
                squaredSum += sample * sample
            }
        }

        let rootMeanSquare = sqrt(squaredSum / Double(sampleCount))
        guard rootMeanSquare > 0 else { return 0 }
        let decibels = 20 * log10(rootMeanSquare)
        return min(max((decibels - decibelFloor) / -decibelFloor, 0), 1)
    }
}
