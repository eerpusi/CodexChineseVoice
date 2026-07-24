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

enum ComposerValueResolution: Equatable {
    case empty
    case text(String)
    case ambiguous
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

func resolveComposerValue(
    _ value: String,
    placeholder: String?,
    semanticLabels: [String] = [],
    characterCount: Int?
) -> ComposerValueResolution {
    if characterCount == 0 {
        return .empty
    }
    let normalized = normalizedComposerValue(
        value,
        placeholder: placeholder,
        semanticLabels: semanticLabels
    )
    if normalized.isEmpty {
        return .empty
    }
    if characterCount == nil && semanticLabels.isEmpty && placeholder == nil {
        return .ambiguous
    }
    return .text(normalized)
}
