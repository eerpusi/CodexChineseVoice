import ApplicationServices
import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class ComposerEditingTests: XCTestCase {
    func testPartialUpdatesReplaceOnlyOwnedSelection() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = NSRange(location: 2, length: 2)
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        try editor.replacePartial("临时")
        XCTAssertEqual(document.value, "前缀临时后缀")
        XCTAssertEqual(document.selection, NSRange(location: 4, length: 0))

        try editor.replacePartial("临时文本")
        XCTAssertEqual(document.value, "前缀临时文本后缀")
        XCTAssertEqual(document.selection, NSRange(location: 6, length: 0))
        XCTAssertTrue(editor.isActive)
    }

    func testFinalReplacesPartialAndOnlyWritesTextAndSelection() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = NSRange(location: 2, length: 2)
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        try editor.replacePartial("临时")
        document.operations.removeAll()

        try editor.finalize("最终")

        XCTAssertEqual(document.value, "前缀最终后缀")
        XCTAssertEqual(document.selection, NSRange(location: 4, length: 0))
        XCTAssertFalse(editor.isActive)
        XCTAssertEqual(
            document.operations,
            [
                .read,
                .setValue("前缀最终后缀"),
                .setSelection(NSRange(location: 4, length: 0)),
            ]
        )
        XCTAssertThrowsError(try editor.replacePartial("不应写入")) { error in
            XCTAssertEqual(error as? CodexInputBridgeError, .noActiveComposition)
        }
    }

    func testCompletionWritesFinalTextBeforeSubmitting() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "已有文字")
        var submittedValues: [String] = []
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: NSRange(location: 4, length: 0),
            frontmost: frontmost,
            submitMessage: { validate in
                try validate()
                submittedValues.append(document.value)
            }
        )

        try editor.begin()
        try editor.replacePartial("临时")
        try editor.complete("最终语音", submit: true)

        XCTAssertEqual(document.value, "已有文字最终语音")
        XCTAssertEqual(submittedValues, ["已有文字最终语音"])
        XCTAssertFalse(editor.isActive)
    }

    func testCompletionCanLeaveFinalTextUnsubmitted() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "已有文字")
        var submitCount = 0
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: NSRange(location: 4, length: 0),
            frontmost: frontmost,
            submitMessage: { _ in submitCount += 1 }
        )

        try editor.begin()
        try editor.complete("最终语音", submit: false)

        XCTAssertEqual(document.value, "已有文字最终语音")
        XCTAssertEqual(submitCount, 0)
        XCTAssertFalse(editor.isActive)
    }

    func testSubmissionFailureLeavesFinalTextAndClearsSession() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "已有文字")
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: NSRange(location: 4, length: 0),
            frontmost: frontmost,
            submitMessage: { validate in
                try validate()
                throw TestDocumentError.submissionFailed
            }
        )

        try editor.begin()

        XCTAssertThrowsError(try editor.complete("最终语音", submit: true))
        XCTAssertEqual(document.value, "已有文字最终语音")
        XCTAssertFalse(editor.isActive)
    }

    func testCompletionDoesNotWriteOrSubmitAfterComposerLosesFocus() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "已有文字")
        var submitCount = 0
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: NSRange(location: 4, length: 0),
            frontmost: frontmost,
            submitMessage: { _ in submitCount += 1 }
        )

        try editor.begin()
        try editor.replacePartial("临时")
        document.isFocused = false

        XCTAssertThrowsError(try editor.complete("最终语音", submit: true)) { error in
            XCTAssertEqual(error as? CodexInputBridgeError, .noFocusedComposer)
        }
        XCTAssertEqual(document.value, "已有文字临时")
        XCTAssertEqual(submitCount, 0)
        XCTAssertTrue(editor.isActive)
    }

    func testSubmissionBoundaryRechecksFocusBeforePosting() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "已有文字")
        var submitCount = 0
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: NSRange(location: 4, length: 0),
            frontmost: frontmost,
            submitMessage: { validate in
                document.isFocused = false
                try validate()
                submitCount += 1
            }
        )

        try editor.begin()

        XCTAssertThrowsError(try editor.complete("最终语音", submit: true)) { error in
            XCTAssertEqual(error as? CodexInputBridgeError, .noFocusedComposer)
        }
        XCTAssertEqual(document.value, "已有文字最终语音")
        XCTAssertEqual(submitCount, 0)
        XCTAssertFalse(editor.isActive)
    }

    func testCancelRestoresOriginalSelectionAndClearsSession() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = NSRange(location: 2, length: 2)
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        try editor.replacePartial("临时")
        document.value += "，用户补充"
        editor.cancel()

        XCTAssertEqual(document.value, "前缀原文后缀，用户补充")
        XCTAssertEqual(document.selection, NSRange(location: 2, length: 2))
        XCTAssertFalse(editor.isActive)
        editor.cancel()
        XCTAssertEqual(document.value, "前缀原文后缀，用户补充")
    }

    func testExternalTextOutsideOwnedRangeSurvivesFinalization() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = NSRange(location: 2, length: 2)
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        try editor.replacePartial("临时")
        document.value = "前缀临时后缀用户补充"
        try editor.finalize("最终")

        XCTAssertEqual(document.value, "前缀最终后缀用户补充")
        XCTAssertFalse(editor.isActive)
    }

    func testPartialRelocatesOwnedRangeAfterUTF16InsertionBeforeIt() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = (document.value as NSString).range(of: "原文")
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        try editor.replacePartial("临时")
        let externallyEdited = NSMutableString(string: document.value)
        externallyEdited.insert("用户🚀", at: selection.location)
        document.value = String(externallyEdited)

        try editor.replacePartial("更新")

        XCTAssertEqual(document.value, "前缀用户🚀更新后缀")
        XCTAssertEqual(
            document.selection,
            NSRange(
                location: NSMaxRange((document.value as NSString).range(of: "更新")),
                length: 0
            )
        )
    }

    func testFinalRelocatesOwnedRangeAfterUTF16InsertionBeforeIt() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = (document.value as NSString).range(of: "原文")
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        try editor.replacePartial("临时")
        let externallyEdited = NSMutableString(string: document.value)
        externallyEdited.insert("用户🚀", at: selection.location)
        document.value = String(externallyEdited)

        try editor.finalize("最终")

        XCTAssertEqual(document.value, "前缀用户🚀最终后缀")
        XCTAssertFalse(editor.isActive)
    }

    func testCancelRelocatesOwnedRangeAfterUTF16InsertionBeforeIt() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = (document.value as NSString).range(of: "原文")
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        try editor.replacePartial("临时")
        let externallyEdited = NSMutableString(string: document.value)
        externallyEdited.insert("用户🚀", at: selection.location)
        document.value = String(externallyEdited)

        editor.cancel()

        XCTAssertEqual(document.value, "前缀用户🚀原文后缀")
        XCTAssertEqual(
            document.selection,
            (document.value as NSString).range(of: "原文")
        )
        XCTAssertFalse(editor.isActive)
    }

    func testEditInsideOwnedRangeIsRejectedWithoutWriting() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = (document.value as NSString).range(of: "原文")
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        try editor.replacePartial("临时")
        document.value = "前缀临外后缀"
        document.operations.removeAll()

        XCTAssertThrowsError(try editor.replacePartial("更新")) { error in
            XCTAssertEqual(error as? CodexInputBridgeError, .textChangedExternally)
        }
        XCTAssertEqual(document.value, "前缀临外后缀")
        XCTAssertEqual(document.operations, [.read])
    }

    func testPartialDoesNotWriteCapturedDocumentThatLostFocus() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = (document.value as NSString).range(of: "原文")
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        document.isFocused = false
        document.operations.removeAll()

        XCTAssertThrowsError(try editor.replacePartial("不应写入")) { error in
            XCTAssertEqual(error as? CodexInputBridgeError, .noFocusedComposer)
        }
        XCTAssertEqual(document.value, "前缀原文后缀")
        XCTAssertEqual(document.operations, [])
    }

    func testFinalDoesNotWriteCapturedDocumentThatLostFocus() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = (document.value as NSString).range(of: "原文")
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        document.isFocused = false
        document.operations.removeAll()

        XCTAssertThrowsError(try editor.finalize("不应写入")) { error in
            XCTAssertEqual(error as? CodexInputBridgeError, .noFocusedComposer)
        }
        XCTAssertEqual(document.value, "前缀原文后缀")
        XCTAssertEqual(document.operations, [])
    }

    func testCancelRestoresCapturedDocumentWhileAnotherAppIsFrontmost() throws {
        let frontmost = FrontmostState()
        let capturedProcessID = frontmost.processID
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = (document.value as NSString).range(of: "原文")
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        try editor.replacePartial("临时")
        frontmost.bundleIdentifier = "com.apple.Safari"
        frontmost.processID = capturedProcessID + 1

        editor.cancel()

        XCTAssertEqual(document.value, "前缀原文后缀")
        XCTAssertEqual(document.selection, selection)
        XCTAssertFalse(editor.isActive)
    }

    func testCancelDoesNotWriteCapturedDocumentThatLostFocus() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = (document.value as NSString).range(of: "原文")
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        try editor.replacePartial("临时")
        document.isFocused = false
        document.operations.removeAll()

        editor.cancel()

        XCTAssertEqual(document.value, "前缀临时后缀")
        XCTAssertEqual(document.operations, [])
        XCTAssertFalse(editor.isActive)
    }

    func testSelectionWriteFailureCanBeCancelledAndSessionReused() throws {
        let frontmost = FrontmostState()
        let document = MemoryComposerDocument(value: "前缀原文后缀")
        let selection = NSRange(location: 2, length: 2)
        let editor = makeEditor(
            document: document,
            originalValue: document.value,
            selection: selection,
            frontmost: frontmost
        )

        try editor.begin()
        document.failNextSelectionWrite = true
        XCTAssertThrowsError(try editor.replacePartial("失败"))
        editor.cancel()

        XCTAssertEqual(document.value, "前缀原文后缀")
        XCTAssertFalse(editor.isActive)

        try editor.begin()
        try editor.replacePartial("恢复")
        try editor.finalize("完成")
        XCTAssertEqual(document.value, "前缀完成后缀")
        XCTAssertFalse(editor.isActive)
    }

    private func makeEditor(
        document: MemoryComposerDocument,
        originalValue: String,
        selection: NSRange,
        frontmost: FrontmostState,
        submitMessage: @escaping (_ validate: () throws -> Void) throws -> Void = {
            validate in try validate()
        }
    ) -> CodexComposerEditor {
        CodexComposerEditor(
            frontmostBundleIdentifier: { frontmost.bundleIdentifier },
            frontmostProcessIdentifier: { frontmost.processID },
            accessibilityTrusted: { true },
            compositionSeed: { processID in
                ComposerSeed(
                    document: document,
                    processID: processID,
                    originalValue: originalValue,
                    originalSelection: selection
                )
            },
            submitMessage: submitMessage
        )
    }
}

private final class FrontmostState {
    var bundleIdentifier = CodexHotkeyMonitor.codexBundleIdentifier
    var processID = getpid()
}

private final class MemoryComposerDocument: ComposerDocument {
    enum Operation: Equatable {
        case read
        case setValue(String)
        case setSelection(NSRange)
    }

    var value: String
    var selection = NSRange(location: 0, length: 0)
    var operations: [Operation] = []
    var failNextSelectionWrite = false
    var isFocused = true

    init(value: String) {
        self.value = value
    }

    func readValue() throws -> String {
        operations.append(.read)
        return value
    }

    func writeValue(_ value: String) throws {
        operations.append(.setValue(value))
        self.value = value
    }

    func writeSelection(_ range: NSRange) throws {
        operations.append(.setSelection(range))
        if failNextSelectionWrite {
            failNextSelectionWrite = false
            throw TestDocumentError.selectionWriteFailed
        }
        selection = range
    }

    func isFocused(in processID: pid_t) -> Bool {
        isFocused
    }
}

private enum TestDocumentError: Error {
    case selectionWriteFailed
    case submissionFailed
}
