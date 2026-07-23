# Automatic Transcript Submission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Send the complete active Codex composer once after a successful voice transcription, with a persisted setting that defaults to enabled.

**Architecture:** Keep preference storage in `AppPresentationPreferences`, session convergence in `VoiceInputCoordinator`, and system Return-key emission in a new macOS submitter. `CodexComposerEditor` remains the safety boundary: it validates the captured Codex process and focused composer, writes the final text, clears its transaction, and only then invokes the submitter.

**Tech Stack:** Swift 6, SwiftUI, UserDefaults, macOS Accessibility, CoreGraphics keyboard events, XCTest, SwiftPM.

---

### Task 1: Persist The Default-On Preference

**Files:**
- Modify: `Sources/CodexChineseVoiceCore/Application/AppPresentationPreferences.swift`
- Test: `Tests/CodexChineseVoiceCoreTests/AppPresentationPreferencesTests.swift`

- [ ] **Step 1: Write failing default and round-trip tests**

Add tests that load an empty suite and expect `autoSendsTranscription == true`, then save both
`false` and `true` and assert each value reloads:

```swift
func testAutoSendIsEnabledByDefault() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    XCTAssertTrue(AppPresentationPreferences.load(from: defaults).autoSendsTranscription)
}

func testAutoSendRoundTripsThroughUserDefaults() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    AppPresentationPreferences(autoSendsTranscription: false).save(to: defaults)
    XCTAssertFalse(AppPresentationPreferences.load(from: defaults).autoSendsTranscription)

    AppPresentationPreferences(autoSendsTranscription: true).save(to: defaults)
    XCTAssertTrue(AppPresentationPreferences.load(from: defaults).autoSendsTranscription)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter AppPresentationPreferencesTests
```

Expected: compilation fails because `autoSendsTranscription` and its initializer argument do not
exist.

- [ ] **Step 3: Implement the preference**

Add `autoSendsTranscriptionKey`, a default-`true` property and initializer argument, load the
absent key as `true`, and save it alongside `showsDockIcon`:

```swift
public static let autoSendsTranscriptionKey = "autoSendsTranscription"

public var autoSendsTranscription: Bool

public init(
    showsDockIcon: Bool = true,
    autoSendsTranscription: Bool = true
) {
    self.showsDockIcon = showsDockIcon
    self.autoSendsTranscription = autoSendsTranscription
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run `swift test --filter AppPresentationPreferencesTests`.
Expected: all preference tests pass.

### Task 2: Create A Deterministic Return-Key Submitter

**Files:**
- Create: `Sources/CodexChineseVoiceCore/MacOS/CodexMessageSubmitter.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/CodexMessageSubmitterTests.swift`
- Modify: `Sources/CodexChineseVoiceCore/MacOS/CodexInputBridgeTypes.swift`

- [ ] **Step 1: Write failing event-order and creation-failure tests**

Define tests against an internal `CodexMessageSubmitter` initializer that injects event creation and
posting. Record the posted event types, key codes, and flags, then expect exactly one unmodified
Return key-down followed by key-up. A factory returning `nil` must throw
`CodexInputBridgeError.autoSubmitUnavailable` and post nothing.

```swift
func testSubmitPostsUnmodifiedReturnDownThenUp() throws {
    var posted: [(CGEventType, Int64, CGEventFlags)] = []
    let submitter = CodexMessageSubmitter(
        makeEvent: { keyDown in
            CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: keyDown)
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
```

- [ ] **Step 2: Run submitter tests and verify RED**

Run `swift test --filter CodexMessageSubmitterTests`.
Expected: compilation fails because the submitter and error case do not exist.

- [ ] **Step 3: Implement the isolated system boundary**

Create a submitter with injected closures for tests and production defaults using
`CGEvent(keyboardEventSource:virtualKey:keyDown:)` and `.post(tap: .cghidEventTap)`. Set both event
flags to `[]` before posting:

```swift
import CoreGraphics

struct CodexMessageSubmitter {
    private let makeEvent: (_ keyDown: Bool) -> CGEvent?
    private let post: (CGEvent) -> Void

    init() {
        makeEvent = { keyDown in
            CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: keyDown)
        }
        post = { event in event.post(tap: .cghidEventTap) }
    }

    init(
        makeEvent: @escaping (_ keyDown: Bool) -> CGEvent?,
        post: @escaping (CGEvent) -> Void
    ) {
        self.makeEvent = makeEvent
        self.post = post
    }

    func submit() throws {
        guard let keyDown = makeEvent(true),
              let keyUp = makeEvent(false) else {
            throw CodexInputBridgeError.autoSubmitUnavailable
        }
        keyDown.flags = []
        keyUp.flags = []
        post(keyDown)
        post(keyUp)
    }
}
```

Add this error case and Chinese description:

```swift
case autoSubmitUnavailable
// errorDescription: "无法创建自动发送按键事件"
```

- [ ] **Step 4: Run submitter tests and verify GREEN**

Run `swift test --filter CodexMessageSubmitterTests`.
Expected: both event planning tests pass.

### Task 3: Complete And Submit The Captured Composer Safely

**Files:**
- Modify: `Sources/CodexChineseVoiceCore/MacOS/CodexInputBridge+Composer.swift`
- Test: `Tests/CodexChineseVoiceCoreTests/ComposerEditingTests.swift`

- [ ] **Step 1: Write failing completion tests**

Extend the test editor factory with an injected `submit: () throws -> Void`. Add focused tests that:

- Start with `"已有文字"` and an insertion selection at its end.
- Replace a partial, call `complete("最终语音", submit: true)`, and assert the document value is
  `"已有文字最终语音"` when the submit closure runs.
- Call `complete(..., submit: false)` and assert the closure is not called.
- Make the closure throw and assert final text remains while `editor.isActive == false`.
- Mark the document unfocused before completion and assert neither final write nor submission occurs.

The primary enabled test is:

```swift
func testCompletionWritesFinalTextBeforeSubmitting() throws {
    let document = MemoryComposerDocument(value: "已有文字")
    var submittedValues: [String] = []
    let editor = makeEditor(
        document: document,
        selection: NSRange(location: 4, length: 0),
        submit: { submittedValues.append(document.value) }
    )

    try editor.begin()
    try editor.replacePartial("临时")
    try editor.complete("最终语音", submit: true)

    XCTAssertEqual(document.value, "已有文字最终语音")
    XCTAssertEqual(submittedValues, ["已有文字最终语音"])
    XCTAssertFalse(editor.isActive)
}
```

- [ ] **Step 2: Run composer tests and verify RED**

Run `swift test --filter ComposerEditingTests`.
Expected: compilation fails because `complete(_:submit:)` and the injected submission boundary do
not exist.

- [ ] **Step 3: Implement completion without rollback after submission starts**

Add a production submit closure backed by `CodexMessageSubmitter().submit()`. Keep
`finalize(_:)` as a compatibility wrapper around `complete(_:submit: false)`. The completion method
must validate and update while holding the editor lock, clear `composition`, unlock, and only then
call the submit closure:

```swift
private let submitMessage: () throws -> Void

// In the public initializer:
submitMessage = { try CodexMessageSubmitter().submit() }

// Add this parameter to the internal test initializer:
submitMessage: @escaping () throws -> Void = {
    try CodexMessageSubmitter().submit()
}
```

```swift
public func finalize(_ text: String) throws {
    try complete(text, submit: false)
}

public func complete(_ text: String, submit shouldSubmit: Bool) throws {
    lock.lock()
    guard var active = composition else {
        lock.unlock()
        throw CodexInputBridgeError.noActiveComposition
    }
    do {
        try ensureFrontmost(active)
        if text.isEmpty {
            try restoreOriginal(&active)
        } else {
            try replaceOwnedValue(&active, with: text)
        }
        if shouldSubmit && !text.isEmpty {
            try ensureFrontmost(active)
        }
        composition = nil
        lock.unlock()
    } catch {
        composition = active
        lock.unlock()
        throw error
    }

    if shouldSubmit && !text.isEmpty {
        try submitMessage()
    }
}
```

If text mutation or focus validation fails, retain the active composition for `cancel()` recovery.
If submission itself fails, the composition is already cleared and final text remains intact.

- [ ] **Step 4: Run composer tests and verify GREEN**

Run `swift test --filter 'ComposerEditingTests|ComposerLockingTests'`.
Expected: all composer transaction and locking tests pass.

### Task 4: Converge Each Session Before One Optional Submission

**Files:**
- Modify: `Sources/CodexChineseVoiceCore/Runtime/VoiceInputCoordinator.swift`
- Modify: `Sources/CodexChineseVoiceCore/Runtime/PlatformAdapters.swift`
- Test: `Tests/CodexChineseVoiceCoreTests/VoiceInputCoordinatorTests.swift`

- [ ] **Step 1: Write failing coordinator tests**

Replace the fake composer's `finalize` recording with
`complete(_ text: String, submit: Bool)`. Add tests for these observable rules:

```swift
private struct CoordinatorCompletion: Equatable {
    let text: String
    let submit: Bool
}

private final class CoordinatorComposer: VoiceInputComposer {
    var completions: [CoordinatorCompletion] = []

    func complete(_ text: String, submit: Bool) throws {
        completions.append(CoordinatorCompletion(text: text, submit: submit))
    }
}
```

```swift
func testCompletedSessionSubmitsByDefaultExactlyOnce() async throws {
    let harness = CoordinatorHarness()
    try await harness.start()

    harness.hotkey.send(.began)
    try await waitUntil { harness.provider.sessionCount == 1 }
    harness.provider.send(TranscriptEvent(text: "最终", isFinal: true), session: 0)
    harness.provider.finish(session: 0)
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertTrue(harness.composer.completions.isEmpty)

    harness.hotkey.send(.ended)
    try await waitUntil { harness.composer.completions.count == 1 }
    XCTAssertEqual(harness.composer.completions[0].text, "最终")
    XCTAssertTrue(harness.composer.completions[0].submit)

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

    XCTAssertEqual(harness.composer.completions[0].text, "最终")
    XCTAssertFalse(harness.composer.completions[0].submit)

    await harness.stop()
}
```

Also assert empty, cancelled, failed, and stale sessions never record a submitted completion.

- [ ] **Step 2: Run coordinator tests and verify RED**

Run `swift test --filter VoiceInputCoordinatorTests`.
Expected: compilation fails because the protocol and initializer do not expose completion and the
dynamic preference closure.

- [ ] **Step 3: Implement session convergence**

Change `VoiceInputComposer` to expose `complete(_:submit:)`. Inject this default-on dynamic closure:

```swift
private let autoSendEnabled: @MainActor () -> Bool

public init(
    hotkey: VoiceInputHotkeySource,
    audio: VoiceInputAudioSource,
    provider: ASRProvider,
    composer: VoiceInputComposer,
    autoSendEnabled: @escaping @MainActor () -> Bool = { true },
    report: @escaping @MainActor (String) -> Void = { _ in }
)
```

Pass the closure through the existing harness so enabled and disabled tests use the same runtime
path:

```swift
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
```

Treat every provider event as an update to the owned partial range. Only
`finishReleasedSession()` completes a non-empty result, passing `autoSendEnabled()`. Empty results
cancel. Remove early finalization state so provider-final-before-key-up cannot submit early or
duplicate submission.

```swift
private func receive(_ event: TranscriptEvent, sessionID: UInt64) {
    guard activeSessionID == sessionID else { return }
    currentText = event.text
    do {
        try composer.replacePartial(event.text)
    } catch {
        report("无法更新 Codex 输入框：\(error.localizedDescription)")
        cancelSession()
    }
}

private func finishReleasedSession() {
    guard !currentText.isEmpty else {
        composer.cancel()
        clearSession()
        return
    }
    do {
        try composer.complete(currentText, submit: autoSendEnabled())
    } catch {
        report("无法完成 Codex 输入：\(error.localizedDescription)")
        composer.cancel()
    }
    clearSession()
}
```

- [ ] **Step 4: Run coordinator tests and verify GREEN**

Run `swift test --filter VoiceInputCoordinatorTests`.
Expected: all lifecycle tests pass, including exactly-once enabled and disabled completion.

### Task 5: Expose The Setting And Wire The Live Preference

**Files:**
- Modify: `Sources/CodexChineseVoiceApp/Views/AppSettingsView.swift`
- Modify: `Sources/CodexChineseVoiceApp/Models/VoiceApplicationModel.swift`

- [ ] **Step 1: Add the SwiftUI preference control**

Bind the same default-on key and put the toggle in the existing application section:

```swift
@AppStorage(AppPresentationPreferences.autoSendsTranscriptionKey)
private var autoSendsTranscription = true

Section("应用") {
    Toggle("转写完成后自动发送", isOn: $autoSendsTranscription)
    Toggle("在 Dock 中显示", isOn: $showsDockIcon)
}
```

This UI wiring has no separate view-test framework; Task 1 covers its persisted contract.

- [ ] **Step 2: Read the live preference at session completion**

Inject this closure when constructing the app coordinator:

```swift
autoSendEnabled: {
    AppPresentationPreferences.load().autoSendsTranscription
},
```

The CLI uses the coordinator's default-on closure.

- [ ] **Step 3: Build and run all automated verification**

Run:

```bash
swift test
Scripts/build-app.sh --unsigned
Tests/ReleaseArtifactTests.sh
Tests/ReleasePipelineTests.sh
```

Expected: 0 test failures, successful universal App and CLI builds, and passing release checks.

- [ ] **Step 4: Commit the green implementation checkpoint**

Stage only the feature, tests, and this plan; do not stage `.vscode/` or
`docs/AI-CODING-WORKFLOW-SURVEY.md`:

```bash
git add Sources Tests docs/superpowers/plans/2026-07-23-auto-send-transcription.md
git commit -m "feat: optionally submit completed voice input"
```

### Task 6: Rebuild The Signed Artifact And Run Manual Acceptance

**Files:**
- Update after verification: `docs/acceptance.md`

- [ ] **Step 1: Produce and verify a fresh signed, notarized artifact**

Run with the installed Developer ID identity and Keychain profile:

```bash
CODE_SIGN_IDENTITY='Developer ID Application: enguang lian (DYT47RAAJW)' \
NOTARYTOOL_PROFILE='codex-chinese-voice' \
Scripts/release.sh --prepare
```

Expected: Apple status `Accepted`, successful stapling, and Gatekeeper source
`Notarized Developer ID`.

- [ ] **Step 2: Manually verify both setting states in Codex**

Launch the notarized app. With auto-send enabled, begin with valid existing text, dictate once, and
confirm one sent message containing existing plus final voice text without placeholder content.
Disable the setting, dictate again, and confirm final text remains unsent. Confirm cancellation and
focus loss do not send.

- [ ] **Step 3: Record only observed acceptance evidence**

Update `docs/acceptance.md` with the new automated count, signed/notarized artifact result, and the
manual outcomes actually observed. Do not mark GitHub Release or Homebrew clean install complete
until those external actions run.

- [ ] **Step 4: Publish only after manual acceptance**

After the user confirms the manual workflow, run `Scripts/release.sh --publish` with `VERSION=0.1.0`,
`GITHUB_REPOSITORY=eerpusi/CodexChineseVoice`, and
`HOMEBREW_TAP_REPOSITORY=eerpusi/homebrew-tap`, then verify a clean Homebrew installation.
