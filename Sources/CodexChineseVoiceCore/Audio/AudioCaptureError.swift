import Foundation

public enum AudioCaptureError: Error, LocalizedError, Sendable, Equatable {
    case alreadyRunning
    case microphonePermissionDenied
    case microphonePermissionNotDetermined
    case inputFormatUnavailable
    case outputFormatUnavailable
    case converterUnavailable
    case engineStartFailed(String)
    case conversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Microphone capture is already running."
        case .microphonePermissionDenied:
            return "Microphone access is denied. Enable it in System Settings > Privacy & Security > Microphone."
        case .microphonePermissionNotDetermined:
            return "Microphone access has not been requested. Request microphone permission, then start capture again."
        case .inputFormatUnavailable:
            return "The microphone did not provide a usable input format."
        case .outputFormatUnavailable:
            return "The 16 kHz mono 16-bit PCM output format is unavailable."
        case .converterUnavailable:
            return "The microphone audio converter could not be created."
        case let .engineStartFailed(message):
            return "The audio engine could not start: \(message)"
        case let .conversionFailed(message):
            return "Microphone audio conversion failed: \(message)"
        }
    }
}
