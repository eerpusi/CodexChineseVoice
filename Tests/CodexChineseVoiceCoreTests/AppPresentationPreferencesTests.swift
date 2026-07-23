import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class AppPresentationPreferencesTests: XCTestCase {
    func testDockIconIsVisibleByDefault() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPresentationPreferences.load(from: defaults)

        XCTAssertTrue(preferences.showsDockIcon)
    }

    func testDockIconVisibilityRoundTripsThroughUserDefaults() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppPresentationPreferences(showsDockIcon: false).save(to: defaults)

        let preferences = AppPresentationPreferences.load(from: defaults)

        XCTAssertFalse(preferences.showsDockIcon)
    }

    func testDockIconVisibilitySelectsApplicationActivationMode() {
        XCTAssertEqual(
            AppPresentationPreferences(showsDockIcon: true).activationMode,
            .regular
        )
        XCTAssertEqual(
            AppPresentationPreferences(showsDockIcon: false).activationMode,
            .accessory
        )
    }
}

private extension AppPresentationPreferencesTests {
    func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "AppPresentationPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
