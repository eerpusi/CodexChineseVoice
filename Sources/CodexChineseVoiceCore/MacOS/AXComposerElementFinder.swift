import ApplicationServices
import Foundation

struct AXComposerElementFinder {
    func findComposer(in root: AXUIElement) -> AXUIElement? {
        let candidates = collectCandidates(in: root)
        guard let index = selectComposerCandidate(candidates.map(\.candidate)) else {
            return nil
        }
        return candidates[index].element
    }

    func contains(_ root: AXUIElement, target: AXUIElement) -> Bool {
        var visited = Set<CFHashCode>()
        return contains(root, target: target, visited: &visited)
    }

    private struct Candidate {
        let element: AXUIElement
        let candidate: ComposerAccessibilityCandidate
    }

    private func collectCandidates(in root: AXUIElement) -> [Candidate] {
        var visited = Set<CFHashCode>()
        return collectCandidates(in: root, visited: &visited)
    }

    private func collectCandidates(
        in element: AXUIElement,
        visited: inout Set<CFHashCode>
    ) -> [Candidate] {
        guard visited.insert(CFHash(element)).inserted else { return [] }

        var matches: [Candidate] = []
        if let candidate = candidate(for: element), candidate.isUsable {
            matches.append(Candidate(element: element, candidate: candidate))
        }

        for child in children(of: element) {
            matches.append(contentsOf: collectCandidates(in: child, visited: &visited))
        }
        return matches
    }

    private func contains(
        _ element: AXUIElement,
        target: AXUIElement,
        visited: inout Set<CFHashCode>
    ) -> Bool {
        guard visited.insert(CFHash(element)).inserted else { return false }
        if CFEqual(element, target) { return true }
        return children(of: element).contains {
            contains($0, target: target, visited: &visited)
        }
    }

    private func candidate(for element: AXUIElement) -> ComposerAccessibilityCandidate? {
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let editable = boolAttribute(kAXIsEditableAttribute, from: element)
            ?? ["AXTextArea", "AXTextField", "AXComboBox"].contains(role)
        return ComposerAccessibilityCandidate(
            role: role,
            isEditable: editable,
            supportsValue: supportsStringValue(element),
            supportsSelection: supportsSelectionRange(element),
            isFocused: boolAttribute(kAXFocusedAttribute, from: element) ?? false
        )
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &raw
        ) == .success,
        let array = raw as? [Any] else { return [] }
        return array.compactMap { value in
            guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
    }

    private func supportsStringValue(_ element: AXUIElement) -> Bool {
        var raw: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &raw
        ) == .success && raw is String
    }

    private func supportsSelectionRange(_ element: AXUIElement) -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &raw
        ) == .success,
        let raw,
        CFGetTypeID(raw) == AXValueGetTypeID() else { return false }
        let value = raw as! AXValue
        return AXValueGetType(value) == .cfRange
    }

    private func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let number = raw as? NSNumber else { return nil }
        return number.boolValue
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else {
            return nil
        }
        return raw as? String
    }
}
