import CoreGraphics
import XCTest
@testable import CodexChineseVoiceCore

final class CodexMessageSubmitterTests: XCTestCase {
    func testSubmitPostsUnmodifiedReturnDownThenUp() throws {
        var posted: [(CGEventType, Int64, CGEventFlags)] = []
        let submitter = CodexMessageSubmitter(
            makeEvent: { keyDown in
                CGEvent(
                    keyboardEventSource: nil,
                    virtualKey: 36,
                    keyDown: keyDown
                )
            },
            post: { event in
                posted.append((
                    event.type,
                    event.getIntegerValueField(.keyboardEventKeycode),
                    event.flags
                ))
            }
        )

        try submitter.submit()

        XCTAssertEqual(posted.map(\.0), [.keyDown, .keyUp])
        XCTAssertEqual(posted.map(\.1), [36, 36])
        XCTAssertEqual(posted.map(\.2), [[], []])
    }

    func testMissingEventThrowsWithoutPosting() {
        var postCount = 0
        let submitter = CodexMessageSubmitter(
            makeEvent: { _ in nil },
            post: { _ in postCount += 1 }
        )

        XCTAssertThrowsError(try submitter.submit()) { error in
            XCTAssertEqual(
                error as? CodexInputBridgeError,
                .autoSubmitUnavailable
            )
        }
        XCTAssertEqual(postCount, 0)
    }

    func testValidationFailureDoesNotPostReturnEvents() {
        var postCount = 0
        let submitter = CodexMessageSubmitter(
            makeEvent: { keyDown in
                CGEvent(
                    keyboardEventSource: nil,
                    virtualKey: 36,
                    keyDown: keyDown
                )
            },
            post: { _ in postCount += 1 }
        )

        XCTAssertThrowsError(
            try submitter.submit(validate: { throw SubmitterTestError.focusLost })
        )
        XCTAssertEqual(postCount, 0)
    }
}

private enum SubmitterTestError: Error {
    case focusLost
}
