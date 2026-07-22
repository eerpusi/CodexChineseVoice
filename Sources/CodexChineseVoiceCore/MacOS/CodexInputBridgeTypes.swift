import AppKit
import Foundation

/// Compatibility name for the coordinator's platform-neutral event type.
public typealias CodexHotkeyEvent = VoiceInputHotkeyEvent

/// Errors shared by the event and Accessibility bridges.
public enum CodexInputBridgeError: Error, Equatable, Sendable {
    case accessibilityPermissionDenied
    case eventTapUnavailable
    case eventTapSetupFailed
    case codexNotFrontmost
    case noFocusedComposer
    case focusedElementNotEditable
    case accessibilityFailure(Int32)
    case invalidSelectionRange
    case textChangedExternally
    case noActiveComposition
}

public typealias CodexHotkeyError = CodexInputBridgeError
public typealias CodexComposerError = CodexInputBridgeError

/// Convenience owner for applications that want one object for both pieces
/// of the bridge. It deliberately exposes no submit/send operation.
public final class CodexInputBridge: @unchecked Sendable {
    public let hotkeyMonitor: CodexHotkeyMonitor
    public let composerEditor: CodexComposerEditor

    public init(
        frontmostBundleIdentifier: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        hotkeyMonitor = CodexHotkeyMonitor(
            frontmostBundleIdentifier: frontmostBundleIdentifier
        )
        composerEditor = CodexComposerEditor(
            frontmostBundleIdentifier: frontmostBundleIdentifier
        )
    }

    public func start() throws { try hotkeyMonitor.start() }
    public func stop() { hotkeyMonitor.stop(); composerEditor.cancelIfActive() }
}
