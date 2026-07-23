import XCTest
@testable import CodexChineseVoiceCore

final class MenuBarIndicatorPresentationTests: XCTestCase {
    func testIdleUsesStableWaveformSymbolAndDoesNotDependOnAudioLevel() {
        let presentation = MenuBarIndicatorPresentation(
            isRecording: false,
            level: 0.8
        )

        XCTAssertEqual(presentation.symbolName, "waveform")
        XCTAssertFalse(presentation.showsMeter)
        XCTAssertEqual(presentation.normalizedLevel, 0)
    }

    func testRecordingShowsMeterAndClampsLevel() {
        let presentation = MenuBarIndicatorPresentation(
            isRecording: true,
            level: 2
        )

        XCTAssertTrue(presentation.showsMeter)
        XCTAssertEqual(presentation.normalizedLevel, 1)
    }

    func testIndicatorReservesStableMenuBarWidth() {
        XCTAssertEqual(
            MenuBarIndicatorPresentation(isRecording: false, level: 0)
                .reservedWidth,
            18
        )
        XCTAssertEqual(
            MenuBarIndicatorPresentation(isRecording: true, level: 0)
                .reservedWidth,
            22
        )
    }
}
