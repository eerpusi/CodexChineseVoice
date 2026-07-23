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
        let document: any ComposerDocument
        let processID: pid_t
        let originalValue: String
        let originalSelection: NSRange
        var ownedRange: NSRange
        var lastPartial: String
        var trackedValue: String
    }

    private let frontmostBundleIdentifier: () -> String?
    private let frontmostProcessIdentifier: () -> pid_t?
    private let accessibilityTrusted: () -> Bool
    private let compositionSeed: ((pid_t) throws -> ComposerSeed)?
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
        compositionSeed = nil
    }

    init(
        frontmostBundleIdentifier: @escaping () -> String?,
        frontmostProcessIdentifier: @escaping () -> pid_t?,
        accessibilityTrusted: @escaping () -> Bool,
        compositionSeed: @escaping (pid_t) throws -> ComposerSeed
    ) {
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
        self.accessibilityTrusted = accessibilityTrusted
        self.compositionSeed = compositionSeed
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

        let seed: ComposerSeed
        if let compositionSeed {
            seed = try compositionSeed(processID)
        } else {
            seed = try liveCompositionSeed(processID: processID)
        }
        let selection = seed.originalSelection
        guard seed.processID == processID,
              valid(selection, in: seed.originalValue) else {
            throw CodexInputBridgeError.invalidSelectionRange
        }

        lock.lock()
        composition = Composition(
            document: seed.document,
            processID: seed.processID,
            originalValue: seed.originalValue,
            originalSelection: selection,
            ownedRange: selection,
            lastPartial: substring(seed.originalValue, range: selection),
            trackedValue: seed.originalValue
        )
        lock.unlock()
    }

    /// Replaces the complete partial result owned by this recording session.
    public func replacePartial(_ text: String) throws {
        try mutate(text: text)
    }

    /// Replaces the owned partial with the final result. An empty final rolls
    /// back to the value and selection captured by `begin`.
    public func finalize(_ text: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard var active = composition else {
            throw CodexInputBridgeError.noActiveComposition
        }
        do {
            try ensureFrontmost(active)

            if text.isEmpty {
                try restoreOriginal(&active)
            } else {
                try replaceOwnedValue(&active, with: text)
            }
            composition = nil
        } catch {
            // A value write can succeed before selection placement fails. Keep
            // the latest owned range so cancel() can still restore it.
            composition = active
            throw error
        }
    }

    /// Cancels the transaction and restores the original selected text.
    public func cancel() {
        lock.lock()
        guard var active = composition else {
            lock.unlock()
            return
        }
        if (try? active.document.isFocused(in: active.processID)) == true {
            try? restoreOriginal(&active)
        }
        composition = nil
        lock.unlock()
    }

    private func mutate(text: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard var active = composition else {
            throw CodexInputBridgeError.noActiveComposition
        }
        do {
            try ensureFrontmost(active)
            try replaceOwnedValue(&active, with: text)
            composition = active
        } catch {
            composition = active
            throw error
        }
    }

    private func ensureFrontmost(_ active: Composition) throws {
        guard frontmostBundleIdentifier() == CodexHotkeyMonitor.codexBundleIdentifier,
              frontmostProcessIdentifier() == active.processID else {
            throw CodexInputBridgeError.codexNotFrontmost
        }
        guard try active.document.isFocused(in: active.processID) else {
            throw CodexInputBridgeError.noFocusedComposer
        }
    }

    private func replaceOwnedValue(_ active: inout Composition, with text: String) throws {
        let current = try active.document.readValue()
        try synchronizeOwnedRange(&active, current: current)

        let mutable = NSMutableString(string: current)
        mutable.replaceCharacters(in: active.ownedRange, with: text)
        let updated = String(mutable)
        try active.document.writeValue(updated)

        let insertion = NSRange(
            location: active.ownedRange.location + (NSString(string: text).length),
            length: 0
        )
        active.ownedRange = NSRange(
            location: active.ownedRange.location,
            length: NSString(string: text).length
        )
        active.lastPartial = text
        active.trackedValue = updated
        try active.document.writeSelection(insertion)
    }

    private func restoreOriginal(_ active: inout Composition) throws {
        let current = try active.document.readValue()
        try synchronizeOwnedRange(&active, current: current)
        let originalText = substring(
            active.originalValue,
            range: active.originalSelection
        )
        let mutable = NSMutableString(string: current)
        mutable.replaceCharacters(in: active.ownedRange, with: originalText)
        let restored = String(mutable)
        if restored != current {
            try active.document.writeValue(restored)
        }
        let restoredRange = NSRange(
            location: active.ownedRange.location,
            length: NSString(string: originalText).length
        )
        active.ownedRange = restoredRange
        active.lastPartial = originalText
        active.trackedValue = restored
        try active.document.writeSelection(restoredRange)
    }

    private func synchronizeOwnedRange(
        _ active: inout Composition,
        current: String
    ) throws {
        guard let range = relocatedRange(
            active.ownedRange,
            from: active.trackedValue,
            to: current
        ), valid(range, in: current),
            substring(current, range: range) == active.lastPartial else {
            throw CodexInputBridgeError.textChangedExternally
        }
        active.ownedRange = range
        active.trackedValue = current
    }

}
