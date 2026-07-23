# Menu Bar Indicator And Hotkey Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the menu bar indicator reliably visible and add privacy-safe evidence for the existing `Command+R` listener without changing the shortcut contract.

**Architecture:** Keep `MenuBarExtra` and the existing `VoiceApplicationModel` ownership. Move the deterministic icon choice into a small Core presentation value so it can be tested without launching AppKit; the SwiftUI view will use a stable SF Symbol in idle states and a larger level indicator while recording. Add bounded `Logger` events at the hotkey/coordinator boundaries, recording only lifecycle/error categories and never credentials, audio, or transcript text.

**Tech Stack:** Swift 6, SwiftUI `MenuBarExtra`, AppKit/CoreGraphics event tap, XCTest, Apple unified logging.

---

### Task 1: Define the menu bar indicator presentation contract

**Files:**
- Create: `Sources/CodexChineseVoiceCore/Application/MenuBarIndicatorPresentation.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/MenuBarIndicatorPresentationTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests proving idle state uses a stable waveform symbol and recording state exposes the level meter with a bounded normalized level:

```swift
func testIdleUsesStableWaveformSymbolAndDoesNotDependOnAudioLevel() {
    let presentation = MenuBarIndicatorPresentation(isRecording: false, level: 0.8)
    XCTAssertEqual(presentation.symbolName, "waveform")
    XCTAssertFalse(presentation.showsMeter)
    XCTAssertEqual(presentation.normalizedLevel, 0)
}

func testRecordingShowsMeterAndClampsLevel() {
    let presentation = MenuBarIndicatorPresentation(isRecording: true, level: 2)
    XCTAssertTrue(presentation.showsMeter)
    XCTAssertEqual(presentation.normalizedLevel, 1)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run `swift test --filter MenuBarIndicatorPresentationTests`. It must fail because the presentation type does not exist yet.

- [ ] **Step 3: Implement the minimal presentation value**

Create a `Sendable` value with `symbolName`, `showsMeter`, and `normalizedLevel`. Clamp the level to `0...1`, and return zero for idle state.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run `swift test --filter MenuBarIndicatorPresentationTests` and confirm both tests pass.

### Task 2: Replace the compressed custom label with a stable SwiftUI indicator

**Files:**
- Modify: `Sources/CodexChineseVoiceApp/Views/MenuBarInputLevelView.swift`
- Modify: `Sources/CodexChineseVoiceApp/App/CodexChineseVoiceApp.swift`

- [ ] **Step 1: Write the failing view-facing assertion**

Extend the Core presentation tests with the user-visible contract: idle symbol is `waveform`, recording label text is the recording accessibility label, and the meter has a fixed width of at least 18 points. Run the focused tests and verify RED before changing the view.

- [ ] **Step 2: Implement the minimal SwiftUI view change**

Use `MenuBarIndicatorPresentation` in `MenuBarInputLevelView`. Render `Image(systemName: "waveform")` at a fixed 18×18 frame when idle. Render the existing bars at a fixed 22×18 frame only while recording, with a red foreground and clamped meter level. Keep the accessibility label and add a concise `.help` string. Do not add a second scene or change app activation policy.

- [ ] **Step 3: Run focused tests and build the app**

Run `swift test --filter MenuBarIndicatorPresentationTests` followed by `swift build --product CodexChineseVoice`. Both must pass before runtime inspection.

### Task 3: Add privacy-safe hotkey boundary telemetry

**Files:**
- Modify: `Sources/CodexChineseVoiceCore/MacOS/CodexInputBridge.swift`
- Modify: `Sources/CodexChineseVoiceCore/Runtime/VoiceInputCoordinator.swift`
- Modify: `Tests/CodexChineseVoiceCoreTests/VoiceInputCoordinatorTests.swift` only if a deterministic lifecycle callback assertion is needed.

- [ ] **Step 1: Add a deterministic test for the existing report boundary**

Use the existing coordinator harness to assert that a hotkey start failure reports a message containing the listener failure category and never includes configuration values. Run the focused test and verify RED if this behavior is not already covered.

- [ ] **Step 2: Add bounded unified logs**

Create one `Logger` per feature category. Log only: event tap start success/failure, `Command+R` began/ended, audio-session start/stop, and composer/provider failure category. Never interpolate API keys, audio bytes, transcript text, or accessibility field contents.

- [ ] **Step 3: Run focused coordinator/hotkey tests**

Run `swift test --filter HotkeyGatingTests` and `swift test --filter VoiceInputCoordinatorTests`. Confirm all pass and no sensitive payload appears in test output or source strings.

### Task 4: Build, relaunch, and verify the real menu bar boundary

**Files:**
- No source changes unless the verification exposes a build/runtime regression.

- [ ] **Step 1: Build and launch through the project script**

Run `./script/build_and_run.sh --verify`.

- [ ] **Step 2: Confirm the status item is visible and no longer compressed**

With read-only macOS accessibility inspection, confirm the `CodexChineseVoice` status menu item exists and its width is at least 18 points. Confirm the menu opens and shows the current state text.

- [ ] **Step 3: Run the full automated suite**

Run `swift test`. The release checkpoint must report zero failures.

- [ ] **Step 4: Perform the manual hotkey check with the user**

The user brings `/Applications/ChatGPT.app` to the front, focuses the composer, holds `Command+R` briefly, and releases it. Inspect logs with `/usr/bin/log show --last 5m --style compact --predicate 'process == "CodexChineseVoice"'`. This manual step is the only real-provider/audio workflow and must not be simulated by the agent.

---

## Self-review

- Scope is limited to the two reported symptoms: status-item visibility and evidence for the existing hotkey path.
- No API key, audio, or transcript data is logged.
- The shortcut remains `Command+R`; configurable shortcuts are explicitly deferred until telemetry proves a collision.
- Each behavior change has a focused RED-GREEN test before implementation.
