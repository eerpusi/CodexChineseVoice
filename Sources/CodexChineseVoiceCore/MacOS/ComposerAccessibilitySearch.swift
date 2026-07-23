import Foundation

struct ComposerAccessibilityCandidate: Equatable {
    let role: String
    let isEditable: Bool
    let supportsValue: Bool
    let supportsSelection: Bool
    let isFocused: Bool

    var isUsable: Bool {
        isEditable && supportsValue && supportsSelection
    }
}

func selectComposerCandidate(
    _ candidates: [ComposerAccessibilityCandidate]
) -> Int? {
    candidates.firstIndex { $0.isFocused && $0.isUsable }
        ?? candidates.firstIndex { $0.isUsable }
}

func normalizedComposerValue(_ value: String, placeholder: String?) -> String {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedPlaceholder = placeholder?.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedValue.isEmpty { return "" }
    if let trimmedPlaceholder, !trimmedPlaceholder.isEmpty, trimmedValue == trimmedPlaceholder {
        return ""
    }
    if trimmedValue == "Work with ChatGPT" {
        return ""
    }
    return value
}
