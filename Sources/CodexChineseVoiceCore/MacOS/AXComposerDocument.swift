import ApplicationServices
import Foundation

final class AXComposerDocument: ComposerDocument {
    private let element: AXUIElement
    private let focusRoot: AXUIElement?
    private let allowsApplicationTreeFocus: Bool
    private let placeholderValue: String?
    private var lastWrittenValue: String?

    init(
        element: AXUIElement,
        focusRoot: AXUIElement? = nil,
        allowsApplicationTreeFocus: Bool = false,
        placeholderValue: String? = nil
    ) {
        self.element = element
        self.focusRoot = focusRoot
        self.allowsApplicationTreeFocus = allowsApplicationTreeFocus
        self.placeholderValue = placeholderValue
    }

    func isFocused(in processID: pid_t) throws -> Bool {
        let application = AXUIElementCreateApplication(processID)
        let focusedRaw: CFTypeRef
        do {
            focusedRaw = try CodexComposerEditor.copyAttribute(
                kAXFocusedUIElementAttribute,
                from: application,
                missing: .noFocusedComposer
            )
        } catch {
            guard allowsApplicationTreeFocus else { throw error }
            return AXComposerElementFinder().contains(application, target: element)
        }
        guard CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() else {
            return false
        }
        let currentFocused = focusedRaw as! AXUIElement
        if CFEqual(currentFocused, element) { return true }
        if let focusRoot, CFEqual(currentFocused, focusRoot) { return true }
        return AXComposerElementFinder().contains(currentFocused, target: element)
    }

    func readValue() throws -> String {
        let raw = try CodexComposerEditor.copyAttribute(
            kAXValueAttribute,
            from: element,
            missing: .focusedElementNotEditable
        )
        guard let rawValue = raw as? String else {
            throw CodexInputBridgeError.focusedElementNotEditable
        }
        if let knownValue = knownComposerDocumentValue(
            rawValue: rawValue,
            placeholderValue: placeholderValue,
            lastWrittenValue: lastWrittenValue
        ) {
            return knownValue
        }
        return try CodexComposerEditor.resolvedComposerValue(rawValue, from: element)
    }

    func writeValue(_ value: String) throws {
        try CodexComposerEditor.setAttribute(
            kAXValueAttribute,
            value: value as CFTypeRef,
            on: element
        )
        lastWrittenValue = value
    }

    func writeSelection(_ range: NSRange) throws {
        try CodexComposerEditor.setSelection(range, on: element)
    }
}
