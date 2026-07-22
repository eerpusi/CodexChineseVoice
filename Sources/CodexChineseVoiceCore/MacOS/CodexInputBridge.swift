import AppKit
import ApplicationServices
import CoreGraphics
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

/// A session event tap for Command+R. Only the matching key events are hidden
/// from the frontmost Codex application; every other event is returned intact.
public final class CodexHotkeyMonitor: @unchecked Sendable {
    public static let codexBundleIdentifier = "com.openai.codex"
    public static let commandRKeyCode: CGKeyCode = 15

    public let events: AsyncStream<CodexHotkeyEvent>
    public var eventStream: AsyncStream<CodexHotkeyEvent> { events }

    private let continuation: AsyncStream<CodexHotkeyEvent>.Continuation
    private let frontmostBundleIdentifier: () -> String?
    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventRunLoop: CFRunLoop?
    private var eventThread: Thread?
    private var isStarted = false
    private var capturedCommandR = false

    public init(
        frontmostBundleIdentifier: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        let stream = AsyncStream.makeStream(of: CodexHotkeyEvent.self)
        events = stream.stream
        continuation = stream.continuation
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
    }

    deinit {
        stop()
        continuation.finish()
    }

    /// Installs a session event tap. The process must already be trusted for
    /// Accessibility; this method never attempts to change system settings.
    public func start() throws {
        lock.lock()
        if isStarted {
            lock.unlock()
            return
        }
        lock.unlock()

        guard AXIsProcessTrusted() else {
            throw CodexInputBridgeError.accessibilityPermissionDenied
        }

        let keyDownMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let keyUpMask = CGEventMask(1) << CGEventType.keyUp.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyDownMask | keyUpMask,
            callback: codexEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw CodexInputBridgeError.eventTapUnavailable
        }

        guard let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            tap,
            0
        ) else {
            CFMachPortInvalidate(tap)
            throw CodexInputBridgeError.eventTapSetupFailed
        }

        lock.lock()
        eventTap = tap
        runLoopSource = source
        isStarted = true
        lock.unlock()

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                return
            }
            self.runEventLoop(ready: ready)
        }
        eventThread = thread
        thread.name = "CodexChineseVoice.EventTap"
        thread.start()

        if ready.wait(timeout: .now() + 1) == .timedOut {
            stop()
            throw CodexInputBridgeError.eventTapSetupFailed
        }
    }

    /// Removes the tap and finishes the event stream. A monitor is intended
    /// to have one start/stop lifecycle; unrelated input is never synthesized.
    public func stop() {
        lock.lock()
        let tap = eventTap
        let source = runLoopSource
        let runLoop = eventRunLoop
        let wasStarted = isStarted
        eventTap = nil
        runLoopSource = nil
        eventRunLoop = nil
        eventThread = nil
        isStarted = false
        capturedCommandR = false
        lock.unlock()

        guard wasStarted else { return }
        if let runLoop, let source {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopStop(runLoop)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        continuation.finish()
    }

    /// Pure matching helper kept public so callers can make the same gate
    /// decision before starting a recording transaction.
    public static func matchesCommandR(
        bundleIdentifier: String?,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        isAutoRepeat: Bool = false
    ) -> Bool {
        guard bundleIdentifier == codexBundleIdentifier,
              keyCode == commandRKeyCode,
              !isAutoRepeat,
              flags.contains(.maskCommand) else {
            return false
        }

        let disallowed = CGEventFlags.maskShift.rawValue
            | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskControl.rawValue
            | CGEventFlags.maskSecondaryFn.rawValue
        return flags.rawValue & disallowed == 0
    }

    private func runEventLoop(ready: DispatchSemaphore) {
        lock.lock()
        guard let source = runLoopSource else {
            lock.unlock()
            ready.signal()
            return
        }
        let runLoop = CFRunLoopGetCurrent()
        eventRunLoop = runLoop
        lock.unlock()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        ready.signal()
        CFRunLoopRun()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = eventTap
            lock.unlock()
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if type == .keyDown {
            guard Self.matchesCommandR(
                bundleIdentifier: frontmostBundleIdentifier(),
                keyCode: keyCode,
                flags: event.flags,
                isAutoRepeat: isRepeat
            ) else {
                return Unmanaged.passUnretained(event)
            }

            lock.lock()
            let shouldBegin = !capturedCommandR
            if shouldBegin { capturedCommandR = true }
            lock.unlock()
            guard shouldBegin else {
                return nil
            }
            continuation.yield(.began)
            return nil
        }

        // Once a Codex key-down was captured, consume its release even if the
        // user changes windows before releasing R. This prevents a stray
        // Command+R release from reaching another application.
        guard keyCode == Self.commandRKeyCode else {
            return Unmanaged.passUnretained(event)
        }
        lock.lock()
        let shouldEnd = capturedCommandR
        capturedCommandR = false
        lock.unlock()
        guard shouldEnd else {
            return Unmanaged.passUnretained(event)
        }
        continuation.yield(.ended)
        return nil
    }
}

private let codexEventTapCallback: CGEventTapCallBack = {
    _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<CodexHotkeyMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}

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
