import ApplicationServices
import OSLog

private let accessibilityLogger = Logger(
    subsystem: "com.lianenguang.CodexChineseVoice",
    category: "Accessibility"
)

enum CodexAccessibilityDiagnostics {
    static func focusedElement(_ element: AXUIElement, processID: pid_t) {
        let role = stringAttribute(kAXRoleAttribute, from: element)
        let subrole = stringAttribute(kAXSubroleAttribute, from: element)
        let editable = attributeStatus(kAXIsEditableAttribute, from: element)
        let value = attributeStatus(kAXValueAttribute, from: element)
        let selection = attributeStatus(kAXSelectedTextRangeAttribute, from: element)

        accessibilityLogger.info(
            "focused element pid=\(processID) role=\(role, privacy: .public) subrole=\(subrole, privacy: .public) editable=\(editable, privacy: .public) value=\(value, privacy: .public) selection=\(selection, privacy: .public)"
        )
    }

    static func attributeFailure(_ attribute: String, status: AXError) {
        accessibilityLogger.error(
            "AX attribute failed name=\(attribute, privacy: .public) status=\(status.rawValue, privacy: .public)"
        )
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String {
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
        guard status == .success, let raw else { return "status=\(status.rawValue)" }
        return (raw as? String) ?? String(describing: raw)
    }

    private static func attributeStatus(_ attribute: String, from element: AXUIElement) -> String {
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
        guard status == .success else { return "status=\(status.rawValue)" }
        guard let raw else { return "nil" }
        if let value = raw as? NSNumber { return value.boolValue ? "true" : "false" }
        return "supported"
    }
}
