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

func normalizedComposerValue(
    _ value: String,
    placeholder: String?,
    semanticLabels: [String] = []
) -> String {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedValue.isEmpty { return "" }
    let labels = [placeholder].compactMap { $0 } + semanticLabels
    if labels.contains(where: {
        let trimmedLabel = $0.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedLabel.isEmpty && trimmedValue == trimmedLabel
    }) {
        return ""
    }
    return value
}
