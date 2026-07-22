import ApplicationServices
import Foundation

protocol ComposerDocument: AnyObject {
    func isFocused(in processID: pid_t) throws -> Bool
    func readValue() throws -> String
    func writeValue(_ value: String) throws
    func writeSelection(_ range: NSRange) throws
}

struct ComposerSeed {
    let document: any ComposerDocument
    let processID: pid_t
    let originalValue: String
    let originalSelection: NSRange

    init(
        document: any ComposerDocument,
        processID: pid_t,
        originalValue: String,
        originalSelection: NSRange
    ) {
        self.document = document
        self.processID = processID
        self.originalValue = originalValue
        self.originalSelection = originalSelection
    }

    // Keep the test and internal callers that construct a seed from an AX
    // element source-compatible while the editor works through ComposerDocument.
    init(
        element: AXUIElement,
        processID: pid_t,
        originalValue: String,
        originalSelection: NSRange
    ) {
        self.init(
            document: AXComposerDocument(element: element),
            processID: processID,
            originalValue: originalValue,
            originalSelection: originalSelection
        )
    }
}

extension CodexComposerEditor {
    func liveCompositionSeed(processID: pid_t) throws -> ComposerSeed {
        let application = AXUIElementCreateApplication(processID)
        let focusedRaw = try Self.copyAttribute(
            kAXFocusedUIElementAttribute,
            from: application,
            missing: .noFocusedComposer
        )
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

        let valueRaw = try Self.copyAttribute(
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
        return ComposerSeed(
            element: focused,
            processID: processID,
            originalValue: value,
            originalSelection: selection
        )
    }

    func selectionRange(from element: AXUIElement) throws -> NSRange {
        let raw = try Self.copyAttribute(
            kAXSelectedTextRangeAttribute,
            from: element,
            missing: .invalidSelectionRange
        )
        guard CFGetTypeID(raw) == AXValueGetTypeID() else {
            throw CodexInputBridgeError.invalidSelectionRange
        }
        let axValue = raw as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            throw CodexInputBridgeError.invalidSelectionRange
        }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue, .cfRange, &range), range.location >= 0,
              range.length >= 0 else {
            throw CodexInputBridgeError.invalidSelectionRange
        }
        return NSRange(location: range.location, length: range.length)
    }

    func boolAttribute(_ attribute: String, from element: AXUIElement) throws -> Bool {
        let raw = try Self.copyAttribute(
            attribute,
            from: element,
            missing: .focusedElementNotEditable
        )
        guard let number = raw as? NSNumber else {
            throw CodexInputBridgeError.focusedElementNotEditable
        }
        return number.boolValue
    }

    static func copyAttribute(
        _ attribute: String,
        from element: AXUIElement,
        missing: CodexInputBridgeError
    ) throws -> CFTypeRef {
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &raw
        )
        guard status == .success else {
            if status == .cannotComplete || status == .notImplemented {
                throw missing
            }
            throw CodexInputBridgeError.accessibilityFailure(Int32(status.rawValue))
        }
        guard let raw else { throw missing }
        return raw
    }

    static func setAttribute(
        _ attribute: String,
        value: CFTypeRef,
        on element: AXUIElement
    ) throws {
        let status = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        guard status == .success else {
            throw CodexInputBridgeError.accessibilityFailure(Int32(status.rawValue))
        }
    }

    static func setSelection(_ range: NSRange, on element: AXUIElement) throws {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else {
            throw CodexInputBridgeError.invalidSelectionRange
        }
        try Self.setAttribute(kAXSelectedTextRangeAttribute, value: value, on: element)
    }

    func valid(_ range: NSRange, in value: String) -> Bool {
        range.location >= 0 && range.length >= 0
            && range.location <= NSString(string: value).length
            && range.length <= NSString(string: value).length - range.location
    }

    func substring(_ value: String, range: NSRange) -> String {
        (value as NSString).substring(with: range)
    }

}

private final class AXComposerDocument: ComposerDocument {
    private let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    func isFocused(in processID: pid_t) throws -> Bool {
        let application = AXUIElementCreateApplication(processID)
        let focusedRaw = try CodexComposerEditor.copyAttribute(
            kAXFocusedUIElementAttribute,
            from: application,
            missing: .noFocusedComposer
        )
        guard CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() else {
            return false
        }
        return CFEqual(focusedRaw, element)
    }

    func readValue() throws -> String {
        let raw = try CodexComposerEditor.copyAttribute(
            kAXValueAttribute,
            from: element,
            missing: .focusedElementNotEditable
        )
        guard let value = raw as? String else {
            throw CodexInputBridgeError.focusedElementNotEditable
        }
        return value
    }

    func writeValue(_ value: String) throws {
        try CodexComposerEditor.setAttribute(
            kAXValueAttribute,
            value: value as CFTypeRef,
            on: element
        )
    }

    func writeSelection(_ range: NSRange) throws {
        try CodexComposerEditor.setSelection(range, on: element)
    }
}
