# CodexChineseVoice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native, Homebrew-installable macOS command that turns hold-to-talk `Command+R` into safe Chinese voice input for the focused Codex composer.

**Architecture:** A Swift Package contains one executable target and one testable core library. Small adapters wrap macOS audio, event-tap, Accessibility, process, and WebSocket APIs; pure state machines own protocol framing and transcript replacement so most behavior is covered without system permissions or network access.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation, AVFoundation, AppKit, ApplicationServices, UserNotifications, URLSessionWebSocketTask, zlib, XCTest, Homebrew.

---

## File Map

- `Package.swift`: Swift package, deployment target, executable/library/test targets, framework links.
- `Sources/CodexChineseVoiceCLI/main.swift`: command entry point only.
- `Sources/CodexChineseVoiceCore/Configuration/*`: environment lookup, config codec, secure file creation, interactive secret prompt.
- `Sources/CodexChineseVoiceCore/ASR/*`: provider contracts, Volcengine binary codec, gzip, WebSocket transport/provider.
- `Sources/CodexChineseVoiceCore/Audio/*`: microphone capture, PCM conversion, 200 ms framing.
- `Sources/CodexChineseVoiceCore/Hotkey/*`: frontmost-app gate and event tap.
- `Sources/CodexChineseVoiceCore/Composer/*`: pure transcript transaction and AX-backed Codex editor.
- `Sources/CodexChineseVoiceCore/Session/*`: recording state machine and component coordination.
- `Sources/CodexChineseVoiceCore/Lifecycle/*`: permissions, background process, PID state, notifications, command routing.
- `Tests/CodexChineseVoiceCoreTests/*`: focused tests mirroring each core responsibility.
- `Packaging/*`, `Scripts/*`, `.github/workflows/ci.yml`: permissions metadata, release archive, Homebrew formula, CI.
- `docs/*`, `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`: user and contributor documentation.

### Task 1: Swift Package And Configuration

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `Sources/CodexChineseVoiceCLI/main.swift`
- Create: `Sources/CodexChineseVoiceCore/Configuration/AppConfiguration.swift`
- Create: `Sources/CodexChineseVoiceCore/Configuration/ConfigFileStore.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/ConfigurationTests.swift`
- Track: `AGENTS.md`

- [ ] **Step 1: Create the package manifest and failing configuration tests**

```swift
func testEnvironmentOverridesSavedKey() throws {
    let store = MemoryConfigStore(apiKey: "saved")
    let loader = ConfigurationLoader(environment: ["ARK_PLAN_API_KEY": "environment"], store: store)
    XCTAssertEqual(try loader.load().apiKey, "environment")
}

func testMissingKeyFailsClearly() {
    let loader = ConfigurationLoader(environment: [:], store: MemoryConfigStore(apiKey: nil))
    XCTAssertThrowsError(try loader.load()) { error in
        XCTAssertEqual(error as? ConfigurationError, .missingAPIKey)
    }
}

private struct MemoryConfigStore: ConfigStoring {
    let apiKey: String?
    func loadAPIKey() throws -> String? { apiKey }
}
```

- [ ] **Step 2: Run the test and verify the new types are missing**

Run: `swift test --filter ConfigurationTests`
Expected: FAIL to compile because `ConfigurationLoader` is not defined.

- [ ] **Step 3: Implement environment-first loading and the generated TOML schema**

```swift
public struct AppConfiguration: Equatable, Sendable { public let apiKey: String }
public enum ConfigurationError: Error, Equatable { case missingAPIKey, unreadableFile, invalidFile }

public struct ConfigurationLoader<Store: ConfigStoring> {
    let environment: [String: String]
    let store: Store

    public func load() throws -> AppConfiguration {
        if let key = environment["ARK_PLAN_API_KEY"], !key.isEmpty { return .init(apiKey: key) }
        guard let key = try store.loadAPIKey(), !key.isEmpty else { throw ConfigurationError.missingAPIKey }
        return .init(apiKey: key)
    }
}
```

`ConfigFileStore` writes only `ark_plan_api_key = "..."`, uses JSONEncoder/JSONDecoder for quoted-string escaping, creates the directory with `0700`, writes atomically, and sets the file to `0600`.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter ConfigurationTests && swift test`
Expected: PASS.

- [ ] **Step 5: Commit the foundation**

```sh
git add Package.swift .gitignore LICENSE AGENTS.md Sources Tests
git commit -m "feat: scaffold Swift command and configuration"
```

### Task 2: Volcengine Binary Protocol

**Files:**
- Create: `Sources/CodexChineseVoiceCore/ASR/TranscriptEvent.swift`
- Create: `Sources/CodexChineseVoiceCore/ASR/ASRProvider.swift`
- Create: `Sources/CodexChineseVoiceCore/ASR/GzipCodec.swift`
- Create: `Sources/CodexChineseVoiceCore/ASR/VolcengineProtocol.swift`
- Create: `Sources/CodexChineseVoiceCore/ASR/VolcengineProtocolParsing.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/GzipCodecTests.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/ProtocolRequestTests.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/ProtocolParsingTests.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/ProtocolTestSupport.swift`

- [ ] **Step 1: Add failing frame and parser tests**

```swift
func testFinalAudioFrameUsesNegativeSequenceAndFinalFlag() throws {
    let frame = try VolcengineProtocol.audioFrame(Data("pcm".utf8), sequence: 7, isFinal: true)
    XCTAssertEqual(Array(frame.prefix(4)), [0x11, 0x23, 0x01, 0x00])
    XCTAssertEqual(frame.readInt32(at: 4), -7)
}

func testFinalServerFlagMarksTranscriptFinal() throws {
    let message = try VolcengineProtocol.parseServerFrame(serverFrame(text: "你好", flags: 0x3))
    XCTAssertEqual(message, TranscriptEvent(text: "你好", isFinal: true))
}
```

- [ ] **Step 2: Verify the protocol tests fail**

Run: `swift test --filter Protocol && swift test --filter GzipCodecTests`
Expected: FAIL to compile because `VolcengineProtocol` is missing.

- [ ] **Step 3: Implement strict framing and gzip**

```swift
public struct TranscriptEvent: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool
}

enum VolcengineMessageType: UInt8 {
    case fullClientRequest = 0x1, audioOnlyRequest = 0x2
    case fullServerResponse = 0x9, errorResponse = 0xF
}
```

Use big-endian `Int32`/`UInt32`, validate every cursor advance and payload length, accept final flags or a negative sequence, and map provider error payloads to typed errors. `GzipCodec` uses zlib `deflateInit2`/`inflateInit2` with gzip window bits and hard output limits.

- [ ] **Step 4: Cover malformed and unsupported frames**

Run: `swift test --filter Protocol && swift test --filter GzipCodecTests`
Expected: PASS for request, audio, partial, final, truncated, invalid-size, invalid-gzip, and error-frame tests.

- [ ] **Step 5: Commit protocol support**

```sh
git add Sources/CodexChineseVoiceCore/ASR \
  Tests/CodexChineseVoiceCoreTests/GzipCodecTests.swift \
  Tests/CodexChineseVoiceCoreTests/ProtocolRequestTests.swift \
  Tests/CodexChineseVoiceCoreTests/ProtocolParsingTests.swift \
  Tests/CodexChineseVoiceCoreTests/ProtocolTestSupport.swift
git commit -m "feat: add Volcengine streaming protocol"
```

### Task 3: Streaming ASR Provider

**Files:**
- Create: `Sources/CodexChineseVoiceCore/ASR/WebSocketTransport.swift`
- Create: `Sources/CodexChineseVoiceCore/ASR/VolcengineStreamingProvider.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/VolcengineProviderTests.swift`

- [ ] **Step 1: Add a fake-transport test for partial then final**

```swift
func testProviderYieldsChangedPartialThenFinal() async throws {
    let transport = FakeWebSocketTransport(responses: [partial("安排"), final("安排复习高数" )])
    let provider = VolcengineStreamingProvider(apiKey: "test-key", transport: transport)
    var events: [TranscriptEvent] = []
    for try await event in provider.events(audio: audioStream([Data("pcm".utf8)])) {
        events.append(event)
    }
    XCTAssertEqual(events, [.init(text: "安排", isFinal: false), .init(text: "安排复习高数", isFinal: true)])
}
```

- [ ] **Step 2: Verify it fails before transport implementation**

Run: `swift test --filter VolcengineProviderTests`
Expected: FAIL to compile because the provider and transport are missing.

- [ ] **Step 3: Implement URLSession transport and provider concurrency**

```swift
public protocol ASRProvider: Sendable {
    func events(audio: AsyncThrowingStream<Data, Error>) -> AsyncThrowingStream<TranscriptEvent, Error>
}

static let endpoint = URL(string: "wss://openspeech.bytedance.com/api/v3/plan/sauc/bigmodel_async")!
static let resourceID = "volc.seedasr.sauc.duration"
```

Build headers `X-Api-Key`, `X-Api-Resource-Id`, `X-Api-Request-Id`, `X-Api-Connect-Id`, and `X-Api-Sequence`. Send 200 ms audio frames while receiving concurrently, deduplicate unchanged full-result partials, send a final empty audio frame, and cancel both tasks on any failure.

- [ ] **Step 4: Test errors and cleanup**

Run: `swift test --filter VolcengineProviderTests`
Expected: PASS for headers, request body, partial/final ordering, sender failure, receiver failure, cancellation, and no-final-response cases.

- [ ] **Step 5: Commit the provider**

```sh
git add Sources/CodexChineseVoiceCore/ASR Tests/CodexChineseVoiceCoreTests/VolcengineProviderTests.swift
git commit -m "feat: stream audio to Volcengine ASR"
```

### Task 4: Audio Conversion And Framing

**Files:**
- Create: `Sources/CodexChineseVoiceCore/Audio/AudioFrameAccumulator.swift`
- Create: `Sources/CodexChineseVoiceCore/Audio/PCMConverter.swift`
- Create: `Sources/CodexChineseVoiceCore/Audio/MicrophoneCapture.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/AudioTests.swift`

- [ ] **Step 1: Add deterministic audio tests**

```swift
func testAccumulatorProducesExactlyTwoHundredMillisecondFrames() {
    var accumulator = AudioFrameAccumulator(frameByteCount: 6_400)
    XCTAssertTrue(accumulator.append(Data(repeating: 1, count: 3_200)).isEmpty)
    XCTAssertEqual(accumulator.append(Data(repeating: 2, count: 3_200)).first?.count, 6_400)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter AudioTests`
Expected: FAIL to compile because audio types are missing.

- [ ] **Step 3: Implement native conversion and capture**

Use `AVAudioEngine` input taps and `AVAudioConverter` to output signed 16-bit little-endian mono PCM at 16 kHz. Expose an `AsyncThrowingStream<Data, Error>` and ensure stream termination removes the tap and stops the engine.

- [ ] **Step 4: Verify format, framing, and cancellation**

Run: `swift test --filter AudioTests`
Expected: PASS for sample conversion, channel mixing, frame boundaries, remainder flush, and cancellation cleanup.

- [ ] **Step 5: Commit audio support**

```sh
git add Sources/CodexChineseVoiceCore/Audio Tests/CodexChineseVoiceCoreTests/AudioTests.swift
git commit -m "feat: capture provider-ready microphone audio"
```

### Task 5: Transcript Replacement Transaction

**Files:**
- Create: `Sources/CodexChineseVoiceCore/Composer/TranscriptEditSession.swift`
- Create: `Sources/CodexChineseVoiceCore/Composer/ComposerAccessing.swift`
- Create: `Sources/CodexChineseVoiceCore/Composer/AXCodexComposer.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/ComposerTests.swift`

- [ ] **Step 1: Add pure replacement tests**

```swift
func testFinalReplacesPartialAndPreservesSurroundingText() throws {
    var session = TranscriptEditSession(value: "before after", selection: NSRange(location: 7, length: 0))
    XCTAssertEqual(try session.replacePartial("安排").value, "before 安排after")
    XCTAssertEqual(try session.finalize("安排复习").value, "before 安排复习after")
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter ComposerTests`
Expected: FAIL to compile because `TranscriptEditSession` is missing.

- [ ] **Step 3: Implement owned-range edits and AX adapter**

The pure transaction stores the original selected text, current owned range, and last partial. Each update verifies the expected owned substring before replacing it. Cancellation restores selected text; an empty final restores the original state. The AX adapter resolves the focused element from the frontmost Codex PID and writes only `AXValue` and `AXSelectedTextRange`.

- [ ] **Step 4: Test mutation conflicts and cancellation**

Run: `swift test --filter ComposerTests`
Expected: PASS for partial replacement, final replacement, selected text, empty final, cancellation, surrounding edits, and ownership mismatch.

- [ ] **Step 5: Commit composer editing**

```sh
git add Sources/CodexChineseVoiceCore/Composer Tests/CodexChineseVoiceCoreTests/ComposerTests.swift
git commit -m "feat: safely replace Codex composer transcripts"
```

### Task 6: Codex-Only Hold Shortcut

**Files:**
- Create: `Sources/CodexChineseVoiceCore/Hotkey/HotkeyGate.swift`
- Create: `Sources/CodexChineseVoiceCore/Hotkey/FrontmostApplicationProvider.swift`
- Create: `Sources/CodexChineseVoiceCore/Hotkey/HotkeyMonitor.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/HotkeyTests.swift`

- [ ] **Step 1: Add gate tests**

```swift
func testCommandRIsCapturedOnlyForFrontmostCodex() {
    XCTAssertEqual(HotkeyGate.decide(bundleID: "com.openai.codex", keyCode: 15, command: true, repeat: false), .begin)
    XCTAssertEqual(HotkeyGate.decide(bundleID: "com.apple.Safari", keyCode: 15, command: true, repeat: false), .passThrough)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter HotkeyTests`
Expected: FAIL to compile because `HotkeyGate` is missing.

- [ ] **Step 3: Implement the pure gate and CGEventTap adapter**

Listen for key-down and key-up through `CGEventTap`. Suppress only the matched Codex events, ignore auto-repeat, keep swallowing the release for a session that began in Codex, and pass all unrelated events unchanged.

- [ ] **Step 4: Verify all gate transitions**

Run: `swift test --filter HotkeyTests`
Expected: PASS for other apps, missing Command, other keys, repeat, down/up, focus loss, and disabled-event-tap recovery.

- [ ] **Step 5: Commit shortcut handling**

```sh
git add Sources/CodexChineseVoiceCore/Hotkey Tests/CodexChineseVoiceCoreTests/HotkeyTests.swift
git commit -m "feat: gate hold-to-talk shortcut to Codex"
```

### Task 7: Voice Session Coordinator

**Files:**
- Create: `Sources/CodexChineseVoiceCore/Session/VoiceInputCoordinator.swift`
- Create: `Sources/CodexChineseVoiceCore/Session/VoiceSessionState.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/SessionTests.swift`

- [ ] **Step 1: Add end-to-end state tests with fakes**

```swift
func testReleaseFinalizesWithoutSubmitting() async throws {
    let harness = VoiceSessionHarness(events: [.init(text: "安排", isFinal: false), .init(text: "安排复习", isFinal: true)])
    await harness.coordinator.keyDown()
    await harness.coordinator.keyUp()
    XCTAssertEqual(harness.composer.value, "安排复习")
    XCTAssertEqual(harness.submitCount, 0)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter SessionTests`
Expected: FAIL to compile because the coordinator is missing.

- [ ] **Step 3: Implement state transitions and structured cancellation**

```swift
public enum VoiceSessionState: Equatable, Sendable {
    case idle, recording, finalizing, failed, cancelled
}
```

The coordinator owns one task group for capture, send, receive, and edit operations. `keyUp` finishes audio, focus loss and stop cancel, and every terminal path stops capture, closes transport, and returns to idle. There is no submit dependency or submit method.

- [ ] **Step 4: Verify success and every cancellation source**

Run: `swift test --filter SessionTests`
Expected: PASS for partial/final, key repeat, overlapping start, empty final, focus loss, audio failure, provider failure, composer conflict, and explicit stop.

- [ ] **Step 5: Commit coordination**

```sh
git add Sources/CodexChineseVoiceCore/Session Tests/CodexChineseVoiceCoreTests/SessionTests.swift
git commit -m "feat: coordinate hold-to-talk voice sessions"
```

### Task 8: CLI, Permissions, And Background Lifecycle

**Files:**
- Create: `Sources/CodexChineseVoiceCore/Lifecycle/CommandRouter.swift`
- Create: `Sources/CodexChineseVoiceCore/Lifecycle/BackgroundProcessController.swift`
- Create: `Sources/CodexChineseVoiceCore/Lifecycle/PermissionChecker.swift`
- Create: `Sources/CodexChineseVoiceCore/Lifecycle/RuntimePaths.swift`
- Create: `Sources/CodexChineseVoiceCore/Lifecycle/FailureNotifier.swift`
- Modify: `Sources/CodexChineseVoiceCLI/main.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/LifecycleTests.swift`

- [ ] **Step 1: Add command routing and stale-PID tests**

```swift
func testStartConfiguresBeforeLaunchingAgent() async throws {
    let harness = LifecycleHarness(configurationPresent: false)
    try await harness.router.run(["start"])
    XCTAssertEqual(harness.actions, [.promptForKey, .checkPermissions, .launchAgent])
}
```

- [ ] **Step 2: Verify lifecycle tests fail**

Run: `swift test --filter LifecycleTests`
Expected: FAIL to compile because lifecycle types are missing.

- [ ] **Step 3: Implement commands and permissions**

Support public commands `start`, `stop`, `status`, `config`, `doctor` and private `run-agent`. `start` validates configuration, requests microphone access, opens Accessibility settings when trust is absent, launches one detached child with stdio redirected, and records its PID atomically. `doctor` reports only present/missing states and never the key value.

- [ ] **Step 4: Verify lifecycle behavior**

Run: `swift test --filter LifecycleTests`
Expected: PASS for first start, already running, stale PID, stop, missing permission, environment credential, saved credential, and redacted diagnostics.

- [ ] **Step 5: Commit the runnable command**

```sh
git add Sources/CodexChineseVoiceCLI Sources/CodexChineseVoiceCore/Lifecycle Tests/CodexChineseVoiceCoreTests/LifecycleTests.swift
git commit -m "feat: add background CLI lifecycle"
```

### Task 9: Documentation, CI, And Homebrew Packaging

**Files:**
- Modify: `README.md`
- Create: `CONTRIBUTING.md`
- Create: `SECURITY.md`
- Create: `docs/privacy.md`
- Create: `docs/troubleshooting.md`
- Create: `Packaging/Info.plist`
- Create: `Packaging/Homebrew/codex-chinese-voice.rb`
- Create: `Scripts/build-release.sh`
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write release validation assertions**

`Scripts/build-release.sh` must fail unless the archive contains one universal executable, embedded microphone usage text, a valid code signature when signing variables are set, no config file, and no occurrence of `ARK_PLAN_API_KEY=`.

- [ ] **Step 2: Verify the packaging check fails before files exist**

Run: `bash Scripts/build-release.sh --check-only`
Expected: FAIL because the release executable and metadata are not built.

- [ ] **Step 3: Add user docs and packaging**

README documents only the simple path first:

```sh
brew install codex-chinese-voice
codex-chinese-voice start
```

Document microphone, Accessibility, provider audio processing, uninstall behavior, troubleshooting, contribution tests, responsible disclosure, MIT terms, and the rule that the tool never sends messages. CI runs `swift test` and `swift build -c release` without provider credentials.

- [ ] **Step 4: Build and inspect the release artifact**

Run: `swift test && bash Scripts/build-release.sh --unsigned`
Expected: PASS and produce a checksum-addressed archive containing no credentials or user configuration.

- [ ] **Step 5: Commit distribution assets**

```sh
git add README.md CONTRIBUTING.md SECURITY.md docs Packaging Scripts .github
git commit -m "docs: add installation and release workflow"
```

### Task 10: Opt-In Provider Test And Acceptance Record

**Files:**
- Create: `Tests/Fixtures/synthetic-zh.wav`
- Create: `Tests/CodexChineseVoiceCoreTests/LiveVolcengineTests.swift`
- Create: `docs/acceptance.md`

- [ ] **Step 1: Add an explicitly gated live test**

```swift
func testLiveSyntheticChineseAudio() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["CODEX_CHINESE_VOICE_RUN_LIVE_ASR"] == "1")
    let configuration = try ConfigurationLoader(
        environment: ProcessInfo.processInfo.environment,
        store: ConfigFileStore.default
    ).load()
    var events: [TranscriptEvent] = []
    for try await event in VolcengineStreamingProvider(apiKey: configuration.apiKey)
        .events(audio: fixtureStream()) {
        events.append(event)
    }
    XCTAssertTrue(events.contains { !$0.isFinal && !$0.text.isEmpty })
    XCTAssertEqual(events.last?.isFinal, true)
}
```

- [ ] **Step 2: Verify default tests skip network access**

Run: `env -u ARK_PLAN_API_KEY swift test`
Expected: PASS with the live test skipped and no network call.

- [ ] **Step 3: Run complete offline verification**

Run: `swift test && swift build -c release && git diff --check`
Expected: PASS.

- [ ] **Step 4: Record gated checks without claiming them complete**

`docs/acceptance.md` lists the real-provider command and the real Codex checklist as `NOT RUN`. Do not execute the provider test without explicit authorization. Do not mark the Codex workflow verified until a signed build is manually exercised against the actual composer.

- [ ] **Step 5: Commit the test gate and acceptance record**

```sh
git add Tests/Fixtures Tests/CodexChineseVoiceCoreTests/LiveVolcengineTests.swift docs/acceptance.md
git commit -m "test: add gated provider and acceptance checks"
```

## Final Verification

- [ ] Run `swift test`; expect all offline tests passing and the live provider test skipped.
- [ ] Run `swift build -c release`; expect a successful release build.
- [ ] Run `bash Scripts/build-release.sh --unsigned`; expect an unsigned local archive and checksum.
- [ ] Run `git diff --check`; expect no whitespace errors.
- [ ] Scan tracked files for secret-shaped assignments; expect no real credential values.
- [ ] Leave provider and real-Codex acceptance marked `NOT RUN` until separately authorized and completed.
