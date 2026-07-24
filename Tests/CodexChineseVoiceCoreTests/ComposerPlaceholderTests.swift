import XCTest
@testable import CodexChineseVoiceCore

final class ComposerPlaceholderTests: XCTestCase {
    func testPlaceholderOnlyValueIsTreatedAsEmptyComposer() {
        XCTAssertEqual(
            normalizedComposerValue("Work with ChatGPT", placeholder: "Work with ChatGPT"),
            ""
        )
    }

    func testSemanticFallbackLabelIsTreatedAsEmptyComposer() {
        XCTAssertEqual(
            normalizedComposerValue(
                "随心输入",
                placeholder: nil,
                semanticLabels: ["随心输入"]
            ),
            ""
        )
    }

    func testZeroCharacterCountTreatsRawPlaceholderValueAsEmpty() {
        XCTAssertEqual(
            resolveComposerValue(
                "随心输入",
                placeholder: nil,
                semanticLabels: [],
                characterCount: 0
            ),
            .empty
        )
    }

    func testZeroCharacterCountCanonicalizesPlaceholderSelectionToEmptyCursor() {
        XCTAssertEqual(
            canonicalComposerSelection(
                NSRange(location: 3, length: 0),
                resolvedValue: "",
                characterCount: 0
            ),
            NSRange(location: 0, length: 0)
        )
    }

    func testInvalidSelectionWithoutEmptyEvidenceIsRejected() {
        XCTAssertNil(
            canonicalComposerSelection(
                NSRange(location: 3, length: 0),
                resolvedValue: "",
                characterCount: nil
            )
        )
    }

    func testKnownWrittenPartialWinsOverStaleZeroCharacterCount() {
        XCTAssertEqual(
            knownComposerDocumentValue(
                rawValue: "你",
                placeholderValue: "随心输入",
                lastWrittenValue: "你"
            ),
            "你"
        )
    }

    func testMissingPlaceholderEvidenceIsAmbiguousInsteadOfText() {
        XCTAssertEqual(
            resolveComposerValue(
                "unlabeled value",
                placeholder: nil,
                semanticLabels: [],
                characterCount: nil
            ),
            .ambiguous
        )
    }

    func testRealTextIsPreservedWhenItDiffersFromPlaceholder() {
        XCTAssertEqual(
            normalizedComposerValue("Work with ChatGPT now", placeholder: "Work with ChatGPT"),
            "Work with ChatGPT now"
        )
    }
}
