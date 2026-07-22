import AppKit
import ApplicationServices
import Foundation

/// An Accessibility-backed transaction for one focused Codex composer.
///
/// AX text ranges use UTF-16 offsets. Keeping the owned range and expected
/// substring together means a user edit outside the range is preserved, while
/// an edit inside it is detected instead of being overwritten silently.
public final class CodexComposerEditor: @unchecked Sendable {
    private struct Composition {
        let element: AXUIElement
        let processID: pid_t
        let originalValue: String
        let originalSelection: NSRange
        var ownedRange: NSRange
        var lastPartial: String
    }

    private let frontmostBundleIdentifier: () -> String?
    private let frontmostProcessIdentifier: () -> pid_t?
    private let accessibilityTrusted: () -> Bool
    private let lock = NSLock()
    private var composition: Composition?

    public init(
        frontmostBundleIdentifier: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        frontmostProcessIdentifier: @escaping () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        accessibilityTrusted: @escaping () -> Bool = AXIsProcessTrusted
    ) {
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
        self.accessibilityTrusted = accessibilityTrusted
    }

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return composition != nil
    }

    /// Captures the currently focused editable AX element and its selection.
    public func begin() throws {
        lock.lock()
        guard composition == nil else {
            lock.unlock()
            return
        }
        lock.unlock()

        guard frontmostBundleIdentifier() == CodexHotkeyMonitor.codexBundleIdentifier else {
            throw CodexInputBridgeError.codexNotFrontmost
        }
        guard accessibilityTrusted() else {
            throw CodexInputBridgeError.accessibilityPermissionDenied
        }
        guard let processID = frontmostProcessIdentifier(), processID > 0 else {
            throw CodexInputBridgeError.noFocusedComposer
        }

        let application = AXUIElementCreateApplication(processID)
        let focusedRaw: CFTypeRef
        do {
            focusedRaw = try copyAttribute(
                kAXFocusedUIElementAttribute,
                from: application,
                missing: .noFocusedComposer
            )
        } catch {
            throw error
        }
        guard CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() else {
            throw CodexInputBridgeError.noFocusedComposer
        }
        let focused = focusedRaw as! AXUIElement

        var focusedProcessID: pid_t = 0
        let pidStatus = AXUIElementGetPid(focused, &focusedProcessID)
        guard pidStatus == .success, focusedProcessID == processID else {
            throw CodexInputBridgeError.noFocusedComposer
        }

        if let editable = try? boolAttribute(kAXIsEditableAttribute, from: focused), !editable {
            throw CodexInputBridgeError.focusedElementNotEditable
        }

        let valueRaw = try copyAttribute(
            kAXValueAttribute,
            from: focused,
            missing: .focusedElementNotEditable
        )
        guard let value = valueRaw as? String else {
            throw CodexInputBridgeError.focusedElementNotEditable
        }
        let selection = try selectionRange(from: focused)
        guard valid(selection, in: value) else {
            throw CodexInputBridgeError.invalidSelectionRange
        }

        lock.lock()
        composition = Composition(
            element: focused,
            processID: processID,
            originalValue: value,
            originalSelection: selection,
            ownedRange: selection,
            lastPartial: substring(value, range: selection)
        )
        lock.unlock()
    }

    /// Replaces the complete partial result owned by this recording session.
    public func replacePartial(_ text: String) throws {
        try mutate(text: text, finish: false)
    }

    /// Replaces the owned partial with the final result. An empty final rolls
    /// back to the value and selection captured by `begin`.
    public func finalize(_ text: String) throws {
        lock.lock()
        guard var active = composition else {
            lock.unlock()
            throw CodexInputBridgeError.noActiveComposition
        }
        try ensureFrontmost(active)

        if text.isEmpty {
            try restoreOriginal(&active)
            composition = nil
            lock.unlock()
            return
        }

        try replaceOwnedValue(&active, with: text)
        composition = nil
        lock.unlock()
    }

    /// Cancels the transaction and restores the original selected text.
    public func cancel() {
        lock.lock()
        guard var active = composition else {
            lock.unlock()
            return
        }
        // If focus was lost, avoid writing into an unrelated application.
        if frontmostBundleIdentifier() == CodexHotkeyMonitor.codexBundleIdentifier,
           frontmostProcessIdentifier() == active.processID {
            try? restoreOriginal(&active)
        }
        composition = nil
        lock.unlock()
    }

    func cancelIfActive() {
        cancel()
    }

    private func mutate(text: String, finish: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        guard var active = composition else {
            throw CodexInputBridgeError.noActiveComposition
        }
        try ensureFrontmost(active)
        try replaceOwnedValue(&active, with: text)
        if finish { composition = nil } else { composition = active }
    }

    private func ensureFrontmost(_ active: Composition) throws {
        guard frontmostBundleIdentifier() == CodexHotkeyMonitor.codexBundleIdentifier,
              frontmostProcessIdentifier() == active.processID else {
            throw CodexInputBridgeError.codexNotFrontmost
        }
    }

    private func replaceOwnedValue(_ active: inout Composition, with text: String) throws {
        let currentRaw = try copyAttribute(
            kAXValueAttribute,
            from: active.element,
            missing: .focusedElementNotEditable
        )
        guard let current = currentRaw as? String,
              valid(active.ownedRange, in: current),
              substring(current, range: active.ownedRange) == active.lastPartial else {
            throw CodexInputBridgeError.textChangedExternally
        }

        let mutable = NSMutableString(string: current)
        mutable.replaceCharacters(in: active.ownedRange, with: text)
        let updated = String(mutable)
        try setAttribute(kAXValueAttribute, value: updated as CFTypeRef, on: active.element)

        let insertion = NSRange(
            location: active.ownedRange.location + (NSString(string: text).length),
            length: 0
        )
        try setSelection(insertion, on: active.element)
        active.ownedRange = NSRange(
            location: active.ownedRange.location,
            length: NSString(string: text).length
        )
        active.lastPartial = text
    }

    private func restoreOriginal(_ active: inout Composition) throws {
        let currentRaw = try copyAttribute(
            kAXValueAttribute,
            from: active.element,
            missing: .focusedElementNotEditable
        )
        guard let current = currentRaw as? String,
              valid(active.ownedRange, in: current),
              substring(current, range: active.ownedRange) == active.lastPartial else {
            throw CodexInputBridgeError.textChangedExternally
        }
        let originalText = substring(
            active.originalValue,
            range: active.originalSelection
        )
        let mutable = NSMutableString(string: current)
        mutable.replaceCharacters(in: active.ownedRange, with: originalText)
        let restored = String(mutable)
        if restored != current {
            try setAttribute(
                kAXValueAttribute,
                value: restored as CFTypeRef,
                on: active.element
            )
        }
        try setSelection(
            NSRange(
                location: active.ownedRange.location,
                length: NSString(string: originalText).length
            ),
            on: active.element
        )
    }

}
