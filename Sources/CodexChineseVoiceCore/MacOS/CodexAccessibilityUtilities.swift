import ApplicationServices
import Foundation

struct ComposerSeed {
    let element: AXUIElement
    let processID: pid_t
    let originalValue: String
    let originalSelection: NSRange
}

extension CodexComposerEditor {
    func liveCompositionSeed(processID: pid_t) throws -> ComposerSeed {
        let application = AXUIElementCreateApplication(processID)
        let focusedRaw = try copyAttribute(
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
        return ComposerSeed(
            element: focused,
            processID: processID,
            originalValue: value,
            originalSelection: selection
        )
    }

    func selectionRange(from element: AXUIElement) throws -> NSRange {
        let raw = try copyAttribute(
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
        let raw = try copyAttribute(
            attribute,
            from: element,
            missing: .focusedElementNotEditable
        )
        guard let number = raw as? NSNumber else {
            throw CodexInputBridgeError.focusedElementNotEditable
        }
        return number.boolValue
    }

    func copyAttribute(
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

    func setAttribute(
        _ attribute: String,
        value: CFTypeRef,
        on element: AXUIElement
    ) throws {
        let status = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        guard status == .success else {
            throw CodexInputBridgeError.accessibilityFailure(Int32(status.rawValue))
        }
    }

    func setSelection(_ range: NSRange, on element: AXUIElement) throws {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else {
            throw CodexInputBridgeError.invalidSelectionRange
        }
        try setAttribute(kAXSelectedTextRangeAttribute, value: value, on: element)
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
