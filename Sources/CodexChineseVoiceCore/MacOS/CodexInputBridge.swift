import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

private let hotkeyLogger = Logger(
    subsystem: "com.lianenguang.CodexChineseVoice",
    category: "Hotkey"
)

/// A session event tap for Command+R. Only the matching key events are hidden
/// from the frontmost Codex application; every other event is returned intact.
public final class CodexHotkeyMonitor: @unchecked Sendable {
    public static let codexBundleIdentifier = "com.openai.codex"
    public static let commandRKeyCode: CGKeyCode = 15

    public let events: AsyncStream<VoiceInputHotkeyEvent>

    private let continuation: AsyncStream<VoiceInputHotkeyEvent>.Continuation
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
        let stream = AsyncStream.makeStream(of: VoiceInputHotkeyEvent.self)
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
            hotkeyLogger.error("event tap start blocked by accessibility permission")
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
            hotkeyLogger.error("event tap creation failed")
            throw CodexInputBridgeError.eventTapUnavailable
        }

        guard let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            tap,
            0
        ) else {
            CFMachPortInvalidate(tap)
            hotkeyLogger.error("event tap run loop setup failed")
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
            hotkeyLogger.error("event tap thread did not become ready")
            throw CodexInputBridgeError.eventTapSetupFailed
        }
        hotkeyLogger.info("event tap started")
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
        hotkeyLogger.info("event tap stopped")
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
            if isRepeat, keyCode == Self.commandRKeyCode {
                lock.lock()
                let isCaptured = capturedCommandR
                lock.unlock()
                if isCaptured {
                    return nil
                }
            }

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
            hotkeyLogger.info("Command-R began")
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
        hotkeyLogger.info("Command-R ended")
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
