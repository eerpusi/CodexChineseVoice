import XCTest
@testable import CodexChineseVoiceCore

final class LifecycleCommandRouterTests: XCTestCase {
    func testStartRoutesToBackgroundController() throws {
        let controller = FakeLifecycleController()
        controller.startResult = .started(pid: 4123)
        let router = LifecycleCommandRouter(controller: controller)

        let result = try router.run(.start)

        XCTAssertEqual(result, .message("CodexChineseVoice started (PID 4123)."))
        XCTAssertEqual(controller.calls, [.start])
    }

    func testStopRoutesWithoutStartingAgent() throws {
        let controller = FakeLifecycleController()
        controller.stopResult = .notRunning
        let router = LifecycleCommandRouter(controller: controller)

        let result = try router.run(.stop)

        XCTAssertEqual(result, .message("CodexChineseVoice is not running."))
        XCTAssertEqual(controller.calls, [.stop])
    }

    func testStatusReportsMatchingAgent() throws {
        let controller = FakeLifecycleController()
        controller.statusResult = .running(pid: 8127)
        let router = LifecycleCommandRouter(controller: controller)

        let result = try router.run(.status)

        XCTAssertEqual(result, .message("CodexChineseVoice is running (PID 8127)."))
        XCTAssertEqual(controller.calls, [.status])
    }

    func testNonProcessCommandsReturnActionsWithoutTouchingController() throws {
        let controller = FakeLifecycleController()
        let router = LifecycleCommandRouter(controller: controller)

        XCTAssertEqual(try router.run(.runAgent), .runAgent)
        XCTAssertEqual(try router.run(.config), .configure)
        XCTAssertEqual(try router.run(.doctor), .diagnose)
        XCTAssertEqual(
            try router.run(.help),
            .message(LifecycleCommand.publicHelp)
        )
        XCTAssertTrue(controller.calls.isEmpty)
    }
}

private final class FakeLifecycleController: BackgroundProcessControlling {
    enum Call: Equatable {
        case start
        case stop
        case status
    }

    var startResult: BackgroundStartResult = .alreadyRunning(pid: 1)
    var stopResult: BackgroundStopResult = .stopped(pid: 1)
    var statusResult: BackgroundProcessStatus = .stopped
    private(set) var calls: [Call] = []

    func start() throws -> BackgroundStartResult {
        calls.append(.start)
        return startResult
    }

    func stop() throws -> BackgroundStopResult {
        calls.append(.stop)
        return stopResult
    }

    func status() throws -> BackgroundProcessStatus {
        calls.append(.status)
        return statusResult
    }
}
