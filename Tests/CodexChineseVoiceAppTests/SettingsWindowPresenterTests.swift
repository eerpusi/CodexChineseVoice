import XCTest
@testable import CodexChineseVoiceApp

final class SettingsWindowPresenterTests: XCTestCase {
    func testStatusBarMenuListsSettingsRestartAndQuit() {
        XCTAssertEqual(
            StatusBarMenuAction.allCases.map(\.title),
            ["设置", "重新启动", "退出"]
        )
    }

    @MainActor
    func testStatusBarUsesTheOriginalWaveformSymbol() {
        let symbolName = StatusBarController.idleSymbolName
        XCTAssertEqual(symbolName, "waveform")
    }

    func testSettingsWindowUsesMeasuredContentHeightAtFixedWidth() {
        XCTAssertEqual(
            SettingsWindowLayout.contentSize(for: NSSize(width: 120, height: 272)),
            NSSize(width: 300, height: 272)
        )
    }

    func testAPIKeyInputUsesCompactFixedWidth() {
        XCTAssertEqual(SettingsWindowLayout.apiKeyInputWidth, 100)
    }

    func testKeyLabelUsesCompactCopy() {
        XCTAssertEqual(SettingsWindowLayout.apiKeyLabel, "Key")
    }

    func testSettingsContentUsesLeadingAlignment() {
        XCTAssertEqual(SettingsWindowLayout.contentAlignment, .leading)
    }

    func testSettingsPanelUsesOneCompactSurface() {
        XCTAssertEqual(SettingsWindowLayout.width, 300)
        XCTAssertEqual(SettingsWindowLayout.rowHeight, 42)
        XCTAssertEqual(SettingsWindowLayout.panelSpacing, 0)
    }

    func testToggleRowsReserveStableTrailingControlWidth() {
        XCTAssertEqual(SettingsWindowLayout.toggleControlWidth, 38)
    }

    func testPresentActivatesApplicationBeforeShowingSettingsWindow() {
        var events: [String] = []

        SettingsWindowPresenter.present(
            activate: { events.append("activate") },
            show: { events.append("show") }
        )

        XCTAssertEqual(events, ["activate", "show"])
    }
}
