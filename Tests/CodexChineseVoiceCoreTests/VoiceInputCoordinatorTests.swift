import Foundation
import XCTest
@testable import CodexChineseVoiceCore

@MainActor
final class VoiceInputCoordinatorTests: XCTestCase {
    func testAudioStartFailureStopsAudioAndCancelsComposer() async throws {
        let harness = CoordinatorHarness(
            audio: CoordinatorAudioSource(startError: CoordinatorTestError.synthetic)
        )
        try await harness.start()

        harness.hotkey.send(.began)
        try await waitUntil { harness.composer.cancelCount == 1 }

        XCTAssertEqual(harness.audio.startCount, 1)
        XCTAssertEqual(harness.audio.stopCount, 1)
        XCTAssertEqual(harness.composer.beginCount, 1)
        XCTAssertEqual(harness.composer.cancelCount, 1)

        await harness.stop()
    }

    func testProviderFailureStopsAudioCancelsComposerAndAllowsNextSession() async throws {
        let harness = CoordinatorHarness()
        try await harness.start()

        harness.hotkey.send(.began)
        try await waitUntil { harness.provider.sessionCount == 1 }
        harness.provider.finish(session: 0, error: CoordinatorTestError.synthetic)
        try await waitUntil { harness.composer.cancelCount == 1 }

        XCTAssertEqual(harness.audio.stopCount, 1)
        XCTAssertEqual(harness.composer.cancelCount, 1)
        XCTAssertTrue(harness.composer.completions.isEmpty)

        harness.hotkey.send(.began)
        try await waitUntil { harness.provider.sessionCount == 2 }
        XCTAssertEqual(harness.audio.startCount, 2)
        XCTAssertEqual(harness.composer.beginCount, 2)

        harness.provider.finish(session: 1, error: CoordinatorTestError.synthetic)
        try await waitUntil { harness.composer.cancelCount == 2 }
        await harness.stop()
    }

    func testProviderCancellationBeforeReleaseStopsAudioAndCancelsComposer() async throws {
        let harness = CoordinatorHarness()
        try await harness.start()

        harness.hotkey.send(.began)
        try await waitUntil { harness.provider.sessionCount == 1 }
        harness.provider.finish(session: 0, error: CancellationError())
        try await waitUntil { harness.composer.cancelCount == 1 }

        XCTAssertEqual(harness.audio.stopCount, 1)
        XCTAssertEqual(harness.composer.cancelCount, 1)
        XCTAssertTrue(harness.composer.completions.isEmpty)

        await harness.stop()
    }

    func testProviderCancellationAfterReleaseCancelsUnfinalizedComposer() async throws {
        let harness = CoordinatorHarness()
        try await harness.start()

        harness.hotkey.send(.began)
        try await waitUntil { harness.provider.sessionCount == 1 }
        harness.provider.send(TranscriptEvent(text: "未完成", isFinal: false), session: 0)
        try await waitUntil { harness.composer.partials == ["未完成"] }
        harness.hotkey.send(.ended)
        try await waitUntil { harness.audio.stopCount == 1 }

        harness.provider.finish(session: 0, error: CancellationError())
        try await waitUntil { harness.audio.stopCount == 2 }

        XCTAssertEqual(harness.composer.cancelCount, 1)
        XCTAssertTrue(harness.composer.completions.isEmpty)

        await harness.stop()
    }

    func testReleaseThenProviderFinishesWithoutEventsClearsSession() async throws {
        let harness = CoordinatorHarness()
        try await harness.start()

        harness.hotkey.send(.began)
        try await waitUntil { harness.provider.sessionCount == 1 }
        harness.hotkey.send(.ended)
        try await waitUntil { harness.audio.stopCount == 1 }
        harness.provider.finish(session: 0)

        harness.hotkey.send(.began)
        let startedAgain = await eventually { harness.provider.sessionCount == 2 }
        XCTAssertTrue(startedAgain)
        XCTAssertTrue(harness.composer.partials.isEmpty)
        XCTAssertTrue(harness.composer.completions.isEmpty)
        XCTAssertEqual(harness.composer.cancelCount, 1)

        await harness.stop()
    }

    func testCompletedSessionSubmitsByDefaultExactlyOnce() async throws {
        let harness = CoordinatorHarness()
        try await harness.start()

        harness.hotkey.send(.began)
        try await waitUntil { harness.provider.sessionCount == 1 }
        harness.provider.send(TranscriptEvent(text: "完成", isFinal: true), session: 0)
        harness.provider.finish(session: 0)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(harness.composer.completions.isEmpty)

        harness.hotkey.send(.ended)
        try await waitUntil { harness.composer.completions.count == 1 }
        harness.hotkey.send(.began)
        let startedAgain = await eventually { harness.provider.sessionCount == 2 }

        XCTAssertTrue(startedAgain)
        XCTAssertTrue(harness.composer.partials.isEmpty)
        XCTAssertEqual(
            harness.composer.completions,
            [CoordinatorCompletion(text: "完成", submit: true)]
        )

        await harness.stop()
    }

    func testFinalCompletesWithoutRedundantPartialWrite() async throws {
        let harness = CoordinatorHarness()
        try await harness.start()

        harness.hotkey.send(.began)
        try await waitUntil { harness.provider.sessionCount == 1 }
        harness.provider.send(TranscriptEvent(text: "你", isFinal: false), session: 0)
        try await waitUntil { harness.composer.partials == ["你"] }

        harness.hotkey.send(.ended)
        try await waitUntil { harness.audio.stopCount == 1 }
        harness.provider.send(TranscriptEvent(text: "你好", isFinal: true), session: 0)
        harness.provider.finish(session: 0)
        try await waitUntil { harness.composer.completions.count == 1 }

        XCTAssertEqual(harness.composer.partials, ["你"])
        XCTAssertEqual(
            harness.composer.completions,
            [CoordinatorCompletion(text: "你好", submit: true)]
        )
        XCTAssertEqual(harness.composer.cancelCount, 0)

        await harness.stop()
    }

    func testPartialWithoutFinalNeverSubmitsWhenProviderFinishes() async throws {
        let harness = CoordinatorHarness()
        try await harness.start()

        harness.hotkey.send(.began)
        try await waitUntil { harness.provider.sessionCount == 1 }
        harness.provider.send(TranscriptEvent(text: "未确认", isFinal: false), session: 0)
        try await waitUntil { harness.composer.partials == ["未确认"] }
        harness.hotkey.send(.ended)
        harness.provider.finish(session: 0)
        try await waitUntil {
            harness.composer.cancelCount == 1 || !harness.composer.completions.isEmpty
        }

        XCTAssertTrue(harness.composer.completions.isEmpty)
        XCTAssertEqual(harness.composer.cancelCount, 1)

        await harness.stop()
    }

    func testDisabledPreferenceCompletesWithoutSubmitting() async throws {
        let harness = CoordinatorHarness(autoSendEnabled: { false })
        try await harness.start()

        harness.hotkey.send(.began)
        try await waitUntil { harness.provider.sessionCount == 1 }
        harness.hotkey.send(.ended)
        harness.provider.send(TranscriptEvent(text: "最终", isFinal: true), session: 0)
        harness.provider.finish(session: 0)
        try await waitUntil { harness.composer.completions.count == 1 }

        XCTAssertEqual(
            harness.composer.completions,
            [CoordinatorCompletion(text: "最终", submit: false)]
        )

        await harness.stop()
    }

    func testRepeatedBeganDoesNotStartAnotherSession() async throws {
        let harness = CoordinatorHarness()
        try await harness.start()

        harness.hotkey.send(.began)
        harness.hotkey.send(.began)
        try await waitUntil { harness.provider.sessionCount == 1 }
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(harness.audio.startCount, 1)
        XCTAssertEqual(harness.composer.beginCount, 1)
        XCTAssertEqual(harness.provider.sessionCount, 1)

        harness.hotkey.send(.ended)
        harness.provider.finish(session: 0)
        await harness.stop()
    }

    func testLateCompletionFromOldSessionCannotClearCurrentSession() async throws {
        let hotkey = CoordinatorHotkeySource()
        let audio = CoordinatorAudioSource()
        let provider = CoordinatorLateProvider()
        let composer = CoordinatorComposer(
            partialError: CoordinatorTestError.synthetic,
            onFirstCancel: { hotkey.send(.began) }
        )
        let coordinator = VoiceInputCoordinator(
            hotkey: hotkey,
            audio: audio,
            provider: provider,
            composer: composer
        )
        let runTask = Task { await coordinator.run() }
        try await waitUntil { hotkey.startCount == 1 }

        hotkey.send(.began)
        try await waitUntil { provider.sessionCount == 1 }
        provider.send(TranscriptEvent(text: "旧会话", isFinal: false), session: 0)
        try await waitUntil { provider.sessionCount == 2 }

        provider.finish(session: 0)
        try await Task.sleep(for: .milliseconds(20))
        hotkey.send(.ended)
        try await waitUntil { audio.stopCount == 2 }
        hotkey.send(.began)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(provider.sessionCount, 2)

        provider.finish(session: 1)
        hotkey.finish()
        await runTask.value
    }

    func testStopEndsHotkeyLoopAndCancelsActiveSession() async throws {
        let hotkey = CoordinatorHotkeySource()
        let audio = CoordinatorAudioSource()
        let provider = CoordinatorProvider()
        let composer = CoordinatorComposer()
        let coordinator = VoiceInputCoordinator(
            hotkey: hotkey,
            audio: audio,
            provider: provider,
            composer: composer
        )
        let runTask = Task { await coordinator.run() }
        try await waitUntil { hotkey.startCount == 1 }
        hotkey.send(.began)
        try await waitUntil { provider.sessionCount == 1 }

        coordinator.stop()
        await runTask.value

        XCTAssertEqual(hotkey.stopCount, 1)
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(composer.cancelCount, 1)
    }
}

@MainActor
private final class CoordinatorHarness {
    let hotkey = CoordinatorHotkeySource()
    let audio: CoordinatorAudioSource
    let provider: CoordinatorProvider
    let composer = CoordinatorComposer()
    private let coordinator: VoiceInputCoordinator
    private var runTask: Task<Void, Never>?

    init(
        audio: CoordinatorAudioSource = CoordinatorAudioSource(),
        provider: CoordinatorProvider = CoordinatorProvider(),
        autoSendEnabled: @escaping @MainActor () -> Bool = { true }
    ) {
        self.audio = audio
        self.provider = provider
        coordinator = VoiceInputCoordinator(
            hotkey: hotkey,
            audio: audio,
            provider: provider,
            composer: composer,
            autoSendEnabled: autoSendEnabled
        )
    }

    func start() async throws {
        runTask = Task { await coordinator.run() }
        try await waitUntil { hotkey.startCount == 1 }
    }

    func stop() async {
        hotkey.finish()
        await runTask?.value
    }
}

private enum CoordinatorTestError: Error {
    case synthetic
}

private enum CoordinatorTestTimeout: Error {
    case expired
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw CoordinatorTestTimeout.expired
}

@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

private final class CoordinatorHotkeySource: VoiceInputHotkeySource, @unchecked Sendable {
    let events: AsyncStream<VoiceInputHotkeyEvent>
    private let continuation: AsyncStream<VoiceInputHotkeyEvent>.Continuation
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    private var isStopped = false

    init() {
        let pair = AsyncStream.makeStream(of: VoiceInputHotkeyEvent.self)
        events = pair.stream
        continuation = pair.continuation
    }

    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }

    func start() throws {
        lock.withLock { starts += 1 }
    }

    func stop() {
        let shouldFinish = lock.withLock {
            guard !isStopped else { return false }
            isStopped = true
            stops += 1
            return true
        }
        if shouldFinish { continuation.finish() }
    }

    func send(_ event: VoiceInputHotkeyEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }
}

private final class CoordinatorAudioSource: VoiceInputAudioSource, @unchecked Sendable {
    private let lock = NSLock()
    private let startError: Error?
    private var starts = 0
    private var stops = 0
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?

    init(startError: Error? = nil) {
        self.startError = startError
    }

    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }

    func start() throws -> AsyncThrowingStream<Data, Error> {
        try lock.withLock {
            starts += 1
            if let startError { throw startError }
        }
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        lock.withLock { continuation = pair.continuation }
        return pair.stream
    }

    func stop() {
        let pending = lock.withLock {
            stops += 1
            defer { continuation = nil }
            return continuation
        }
        pending?.finish()
    }
}

private final class CoordinatorProvider: ASRProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<TranscriptEvent, Error>.Continuation] = []

    var sessionCount: Int { lock.withLock { continuations.count } }

    func events(
        audio: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<TranscriptEvent, Error> {
        let pair = AsyncThrowingStream<TranscriptEvent, Error>.makeStream()
        lock.withLock { continuations.append(pair.continuation) }
        return pair.stream
    }

    func send(_ event: TranscriptEvent, session: Int) {
        lock.withLock { continuations[session] }.yield(event)
    }

    func finish(session: Int, error: Error? = nil) {
        let continuation = lock.withLock { continuations[session] }
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

private struct CoordinatorCompletion: Equatable {
    let text: String
    let submit: Bool
}

private final class CoordinatorComposer: VoiceInputComposer, @unchecked Sendable {
    private let lock = NSLock()
    private var partialError: Error?
    private var firstCancelCallback: (@Sendable () -> Void)?
    private var begins = 0
    private var partialValues: [String] = []
    private var completionValues: [CoordinatorCompletion] = []
    private var cancels = 0

    var beginCount: Int { lock.withLock { begins } }
    var partials: [String] { lock.withLock { partialValues } }
    var completions: [CoordinatorCompletion] { lock.withLock { completionValues } }
    var cancelCount: Int { lock.withLock { cancels } }

    init(
        partialError: Error? = nil,
        onFirstCancel: (@Sendable () -> Void)? = nil
    ) {
        self.partialError = partialError
        firstCancelCallback = onFirstCancel
    }

    func begin() throws {
        lock.withLock { begins += 1 }
    }

    func replacePartial(_ text: String) throws {
        let error = lock.withLock {
            partialValues.append(text)
            defer { partialError = nil }
            return partialError
        }
        if let error { throw error }
    }

    func complete(_ text: String, submit: Bool) throws {
        lock.withLock {
            completionValues.append(CoordinatorCompletion(text: text, submit: submit))
        }
    }

    func cancel() {
        let callback = lock.withLock {
            cancels += 1
            defer { firstCancelCallback = nil }
            return firstCancelCallback
        }
        callback?()
    }
}

private final class CoordinatorLateProvider: ASRProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let firstSource = CoordinatorDelayedTranscriptSource()
    private var sessions = 0
    private var later: [Int: AsyncThrowingStream<TranscriptEvent, Error>.Continuation] = [:]

    var sessionCount: Int { lock.withLock { sessions } }

    func events(
        audio: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<TranscriptEvent, Error> {
        let index = lock.withLock {
            defer { sessions += 1 }
            return sessions
        }
        if index == 0 {
            return AsyncThrowingStream(unfolding: { [firstSource] in
                await firstSource.next()
            })
        }
        let pair = AsyncThrowingStream<TranscriptEvent, Error>.makeStream()
        lock.withLock { later[index] = pair.continuation }
        return pair.stream
    }

    func send(_ event: TranscriptEvent, session: Int) {
        if session == 0 {
            Task { await firstSource.enqueue(event) }
        } else {
            lock.withLock { later[session] }?.yield(event)
        }
    }

    func finish(session: Int) {
        if session == 0 {
            Task { await firstSource.enqueue(nil) }
        } else {
            lock.withLock { later[session] }?.finish()
        }
    }
}

private actor CoordinatorDelayedTranscriptSource {
    private var queued: [TranscriptEvent?] = []
    private var waiter: CheckedContinuation<TranscriptEvent?, Never>?

    func next() async -> TranscriptEvent? {
        if !queued.isEmpty {
            return queued.removeFirst()
        }
        return await withCheckedContinuation { waiter = $0 }
    }

    func enqueue(_ event: TranscriptEvent?) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: event)
        } else {
            queued.append(event)
        }
    }
}
