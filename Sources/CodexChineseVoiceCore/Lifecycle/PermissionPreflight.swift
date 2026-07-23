public enum MicrophonePermission: Equatable, Sendable {
    case granted
    case denied
    case undetermined
}

public enum PermissionPreflightError: Error, Equatable, Sendable {
    case microphoneDenied
    case accessibilityRequired
    case inputMonitoringRequired
}

public protocol PermissionProviding: Sendable {
    var microphonePermission: MicrophonePermission { get }
    func requestMicrophonePermission() async -> Bool
    func isAccessibilityTrusted(prompt: Bool) -> Bool
    func isInputMonitoringTrusted(prompt: Bool) -> Bool
}

public struct PermissionPreflight<Provider: PermissionProviding>: Sendable {
    private let provider: Provider

    public init(provider: Provider) {
        self.provider = provider
    }

    public func ensureReady() async throws {
        switch provider.microphonePermission {
        case .granted:
            break
        case .denied:
            throw PermissionPreflightError.microphoneDenied
        case .undetermined:
            guard await provider.requestMicrophonePermission() else {
                throw PermissionPreflightError.microphoneDenied
            }
        }
        if !provider.isAccessibilityTrusted(prompt: false) {
            guard provider.isAccessibilityTrusted(prompt: true) else {
                throw PermissionPreflightError.accessibilityRequired
            }
        }
        if !provider.isInputMonitoringTrusted(prompt: false) {
            guard provider.isInputMonitoringTrusted(prompt: true) else {
                throw PermissionPreflightError.inputMonitoringRequired
            }
        }
    }
}
