import Foundation

public struct MenuBarIndicatorPresentation: Equatable, Sendable {
    public let symbolName: String
    public let showsMeter: Bool
    public let normalizedLevel: Double
    public let reservedWidth: Double

    public init(isRecording: Bool, level: Double) {
        symbolName = "waveform"
        showsMeter = isRecording
        normalizedLevel = isRecording
            ? max(0, min(level, 1))
            : 0
        reservedWidth = isRecording ? 22 : 18
    }
}
