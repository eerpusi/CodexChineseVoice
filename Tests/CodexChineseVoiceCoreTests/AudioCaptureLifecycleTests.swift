import Foundation
import XCTest
@testable import CodexChineseVoiceCore

final class AudioCaptureLifecycleTests: XCTestCase {
    func testCleanupSkipsEngineWhenStartupDidNotInstallResources() {
        let plan = AudioCaptureCleanupPlan(
            active: true,
            tapInstalled: false,
            hasConverter: false
        )

        XCTAssertFalse(plan.shouldRemoveTap)
        XCTAssertFalse(plan.shouldStopEngine)
    }

    func testCallbackGateWaitsForEnteredCallbackBeforeClosing() {
        let gate = AudioCaptureCallbackGate()
        XCTAssertTrue(gate.enter())
        gate.close()
        XCTAssertFalse(gate.enter())

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            gate.waitUntilIdle()
            finished.signal()
        }

        XCTAssertEqual(
            finished.wait(timeout: .now() + 0.05),
            .timedOut
        )
        gate.leave()
        XCTAssertEqual(
            finished.wait(timeout: .now() + 1),
            .success
        )
    }
}
