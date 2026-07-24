import ApplicationServices
import Foundation

func canonicalComposerSelection(
    _ selection: NSRange,
    resolvedValue: String,
    characterCount: Int?
) -> NSRange? {
    let valueLength = NSString(string: resolvedValue).length
    if selection.location >= 0,
       selection.length >= 0,
       selection.location <= valueLength,
       selection.length <= valueLength - selection.location {
        return selection
    }
    guard resolvedValue.isEmpty, characterCount == 0 else { return nil }
    return NSRange(location: 0, length: 0)
}

func knownComposerDocumentValue(
    rawValue: String,
    placeholderValue: String?,
    lastWrittenValue: String?
) -> String? {
    if rawValue == placeholderValue {
        return ""
    }
    guard rawValue == lastWrittenValue else { return nil }
    return rawValue
}

extension CodexComposerEditor {
    static func resolvedComposerValue(
        _ rawValue: String,
        from element: AXUIElement,
        characterCount: Int? = nil
    ) throws -> String {
        switch resolveComposerValue(
            rawValue,
            placeholder: nil,
            semanticLabels: composerSemanticLabels(from: element),
            characterCount: characterCount ?? self.characterCount(from: element)
        ) {
        case .empty:
            return ""
        case let .text(value):
            return value
        case .ambiguous:
            throw CodexInputBridgeError.ambiguousComposerValue
        }
    }

    static func composerSemanticLabels(from element: AXUIElement) -> [String] {
        var labels = semanticLabels(on: element)
        var ancestor = parent(of: element)
        for _ in 0..<2 {
            guard let current = ancestor else { break }
            labels.append(contentsOf: semanticLabels(on: current))
            labels.append(contentsOf: staticTextLabels(near: current, limit: 24))
            ancestor = parent(of: current)
        }
        return labels
    }

    static func characterCount(from element: AXUIElement) -> Int? {
        guard let raw = optionalAttribute(kAXNumberOfCharactersAttribute, from: element),
              let count = raw as? NSNumber,
              count.intValue >= 0 else {
            return nil
        }
        return count.intValue
    }

    private static func semanticLabels(on element: AXUIElement) -> [String] {
        [
            kAXPlaceholderValueAttribute,
            kAXDescriptionAttribute,
            kAXTitleAttribute,
            kAXHelpAttribute,
        ].compactMap { attribute in
            guard let raw = try? copyAttribute(
                attribute,
                from: element,
                missing: .focusedElementNotEditable
            ), let label = raw as? String else {
                return nil
            }
            return label
        }
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        guard let raw = optionalAttribute(kAXParentAttribute, from: element),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return nil
        }
        return (raw as! AXUIElement)
    }

    private static func staticTextLabels(near element: AXUIElement, limit: Int) -> [String] {
        var labels: [String] = []
        var pending = children(of: element)
        var visited = Set<CFHashCode>()
        while let current = pending.popLast(), labels.count < limit, visited.count < 64 {
            guard visited.insert(CFHash(current)).inserted else { continue }
            let role = optionalAttribute(kAXRoleAttribute, from: current) as? String
            if role == kAXStaticTextRole,
               let value = optionalAttribute(kAXValueAttribute, from: current) as? String {
                labels.append(value)
            }
            pending.append(contentsOf: children(of: current))
        }
        return labels
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let raw = optionalAttribute(kAXChildrenAttribute, from: element),
              let array = raw as? [Any] else {
            return []
        }
        return array.compactMap { value in
            guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
    }

    private static func optionalAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else {
            return nil
        }
        return raw
    }
}
