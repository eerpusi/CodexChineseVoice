# CodexChineseVoice Design

Date: 2026-07-21
Status: Approved for implementation planning; auto-send requirement updated 2026-07-23
License: MIT

> **Requirement update:** The original no-submit rule is superseded by the
> [Automatic Transcript Submission Design](2026-07-23-auto-send-transcription-design.md).
> Auto-send is user-configurable, defaults to enabled, and applies only to a successful non-empty
> final transcription after `Command+R` is released.

## 1. Product

CodexChineseVoice is an independent open-source native macOS menu bar utility for Chinese voice
input in the Codex desktop app. It includes an optional command-line interface and has no
dependency on another local project or service. Its Settings window manages the provider key,
permissions, Dock visibility, and the auto-send preference.

The user-facing workflow is intentionally small:

```sh
brew install --cask eerpusi/tap/codex-chinese-voice
open -a CodexChineseVoice
```

On the first launch, the app guides the user through the Volcengine API key, microphone permission,
and Accessibility permission. Later launches use the saved configuration.

While Codex (`com.openai.codex`) is frontmost:

1. Pressing and holding `Command+R` starts recording.
2. Partial recognition text appears in the focused Codex composer.
3. Releasing `Command+R` stops recording.
4. The final transcript replaces only the partial text owned by the current recording session.
5. If auto-send is enabled, the completed composer is submitted exactly once. If it is disabled,
   the final text remains in the composer.

In every other app, `Command+R` keeps its normal behavior.

## 2. Scope

Version 1 includes:

- A native Swift menu bar app and bundled command-line executable installed with Homebrew.
- A Settings window for credentials, permissions, Dock visibility, and auto-send.
- Background start, stop, status, configuration, and diagnostics commands.
- Codex-only `Command+R` press and release handling.
- Microphone capture and conversion to provider-ready PCM.
- Volcengine Doubao streaming ASR 2.0 through Agent Plan.
- Partial and final transcript replacement in the focused Codex composer.
- A user-controlled, default-on setting for submitting successful final transcriptions.
- Clear first-run permission and configuration guidance.
- Automated tests and an opt-in real-provider test using synthetic audio.
- Signed and notarized release archives for macOS 14 or later.
- Universal release binaries for Apple Silicon and Intel Macs.

Version 1 does not include:

- Automatic launch at login.
- Custom shortcuts or provider selection.
- Audio history, transcript history, analytics, or telemetry.

## 3. Commands And Local Files

The primary command is `codex-chinese-voice start`. If configuration is missing, the command asks
for it before starting the background process.

Supporting commands are:

```sh
codex-chinese-voice stop
codex-chinese-voice status
codex-chinese-voice config
codex-chinese-voice doctor
```

Configuration is stored at:

```text
~/.config/codex-chinese-voice/config.toml
```

The directory is created with mode `0700` and the file with mode `0600`. The API key is accepted
through hidden interactive input and saved only after that explicit user action. The tool never
modifies shell profiles.

Credential lookup order is:

1. `ARK_PLAN_API_KEY` in the current process environment.
2. The value saved by `codex-chinese-voice config`.
3. A clear missing-configuration error.

Provider endpoints, resource IDs, audio requirements, and protocol values are fixed product
constants in source code, not user settings.

Runtime state such as the background process identifier is kept under:

```text
~/Library/Application Support/CodexChineseVoice/
```

The tool does not start automatically after login in version 1. The user starts it explicitly.

## 4. Repository Structure

```text
CodexChineseVoice/
|-- Package.swift
|-- README.md
|-- LICENSE
|-- AGENTS.md
|-- Sources/
|   |-- CodexChineseVoiceCLI/
|   |   `-- main.swift
|   `-- CodexChineseVoiceCore/
|       |-- Configuration/
|       |-- Hotkey/
|       |-- Audio/
|       |-- ASR/
|       |-- Composer/
|       |-- Session/
|       `-- Support/
|-- Tests/
|   `-- CodexChineseVoiceCoreTests/
|       |-- HotkeyTests.swift
|       |-- AudioTests.swift
|       |-- ProtocolTests.swift
|       |-- ComposerTests.swift
|       |-- SessionTests.swift
|       `-- ConfigurationTests.swift
|-- Packaging/
|   |-- Info.plist
|   `-- Homebrew/
|       `-- codex-chinese-voice.rb
|-- Scripts/
|   `-- build-release.sh
`-- docs/
    |-- design.md
    |-- privacy.md
    `-- troubleshooting.md
```

Source files stay below 300 lines and are split before they approach 250 lines.

## 5. Components

### CLI and lifecycle

The CLI validates configuration and permissions, starts one background instance, reports status,
and stops it cleanly. A repeated `start` reports that the service is already running instead of
starting a duplicate.

### Hotkey monitor

The hotkey monitor observes key-down and key-up events. It checks the frontmost bundle identifier
before intercepting anything. It suppresses `Command+R` only for Codex, ignores key-repeat events,
and passes every unrelated event through unchanged.

If Codex loses focus during recording, the current voice session is cancelled immediately.

### Audio capture

The audio component uses native macOS audio APIs. It converts microphone input to 16 kHz, 16-bit,
mono, little-endian PCM and produces frames of approximately 200 ms. Audio exists only in memory
long enough to stream it and is never written to disk.

### ASR provider

Input logic depends on an `ASRProvider` protocol rather than a concrete vendor. Version 1 provides
only the Volcengine implementation.

The Volcengine adapter uses these fixed constants:

```text
wss://openspeech.bytedance.com/api/v3/plan/sauc/bigmodel_async
volc.seedasr.sauc.duration
```

It sends gzip-compressed v3 binary frames and parses incremental and final responses defensively.
The codec validates header sizes, sequence fields, payload lengths, compression, serialization,
server errors, and final-message flags before exposing transcript events.

The request uses `model_name=bigmodel`, punctuation and text normalization, full-result responses,
and low-latency streaming without second-pass non-stream recognition.

### Codex composer editor

The composer editor uses macOS Accessibility APIs. Before recording, it verifies that the focused
editable element belongs to the frontmost Codex process and records the current selection.

Each recording owns one text range. Every partial result replaces that same range as a complete
value; partials are never concatenated as deltas. The final result replaces the owned partial range.
Text outside that range is preserved. After a successful final write, the editor may synthesize one
unmodified Return key when auto-send is enabled. It must revalidate the captured Codex process and
focused composer immediately before submission.

### Session coordinator

The coordinator owns the state transitions:

```text
idle -> recording -> finalizing -> idle
                   -> failed -> idle
     -> cancelled -> idle
```

Only one session may run at a time. It coordinates the hotkey, audio stream, provider stream, and
composer transaction, and guarantees cleanup when any component stops or fails.

## 6. Data Flow

1. `Command+R` key-down arrives while Codex and an editable composer are focused.
2. The tool records the target element and insertion range, then starts audio capture and ASR.
3. PCM frames stream to the provider while recognition events stream back concurrently.
4. Each partial event replaces the current session-owned range.
5. `Command+R` key-up closes audio input and sends the provider's final audio frame.
6. The final event replaces the partial and ends the session.
7. The completed composer is submitted once when auto-send is enabled; otherwise focus remains in
   the composer so the user can edit or send it manually.

## 7. Failure And Cancellation

- Missing configuration or permissions prevent startup and show an exact corrective action.
- Network, timeout, authentication, and provider errors stop recording and show a macOS
  notification directing the user to `codex-chinese-voice doctor`.
- Losing Codex focus, losing the target composer, or stopping the service cancels the current
  recording. Repeated or overlapping start events are ignored while a session is active.
- On failure or cancellation, the editor removes only this session's partial text and restores any
  selected text that the session replaced. Unrelated composer text is preserved.
- An empty final transcript leaves the original composer unchanged.
- All cancellation paths stop the microphone and close the WebSocket promptly.

Logs may contain timestamps, component names, error categories, and provider request identifiers.
They must never contain API keys, raw audio, full request headers, or transcript text.

## 8. Privacy And Security

- Audio is sent directly from the local tool to Volcengine only while the shortcut is held.
- Audio and transcripts are not retained locally.
- Accessibility access is used only for the focused Codex composer.
- The API key is never bundled, printed, logged, or committed.
- Configuration output reports only whether a key is present, never its value.
- Real-provider tests are disabled by default and require explicit authorization at execution time.
- Release binaries are signed and notarized; release checks verify that no credential or local
  configuration file is included.

The README and privacy document must state that speech audio is processed by Volcengine and link to
the applicable provider terms.

## 9. Testing And Acceptance

Automated tests cover:

- Codex frontmost gating and pass-through behavior in other applications.
- Key-down, key-repeat, key-up, overlapping sessions, and cancellation.
- PCM sample format, channel conversion, resampling, and 200 ms framing.
- Client request frames, audio frames, final frames, server partials, server finals, malformed
  payloads, and provider error frames.
- Full-result partial replacement without concatenation.
- Final replacement, empty final, cancellation rollback, selected-text restoration, and preservation
  of unrelated composer text.
- Default-on preference persistence, disabled behavior, exactly-once final submission, and
  prevention of submission for partial, empty, failed, cancelled, stale, or unfocused sessions.
- Missing, unreadable, and permission-invalid configuration.
- Cleanup after audio, network, provider, focus, and process-stop failures.

Provider-independent tests use fakes and synthetic PCM. A real Volcengine test is opt-in, requires
explicit authorization, reads the credential without printing it, and streams repository-owned
synthetic Chinese audio at real-time intervals.

Before a release is described as usable, a signed build must be manually verified on a supported
macOS version against the real Codex desktop composer. The check must cover first-run permissions,
Codex-only shortcut interception, visible partial updates, final replacement, original-text
preservation, and cancellation. The check must also confirm exactly one send for a successful final
transcription when auto-send is enabled, retained final text when it is disabled, and no send from
any ineligible session.

## 10. Distribution

GitHub Releases publishes signed and notarized archives plus checksums. The Homebrew formula installs
the executable and its required metadata, and removal deletes installed program files without
silently deleting user configuration.

The release checklist includes clean-machine installation, permission onboarding, upgrade,
uninstall, checksum verification, secret scanning, automated tests, the opt-in provider test when
authorized, and manual Codex end-to-end verification.

Contributions use Swift Package Manager, focused modules, tests for behavior changes, and the MIT
License. Provider additions must implement `ASRProvider` without changing hotkey, audio, composer, or
session behavior.

## 11. Protocol Reference And Release Risk

The binary framing, audio constraints, Resource ID, and streaming behavior are based on the
[official Volcengine streaming ASR documentation](https://www.volcengine.com/docs/6561/1354869?lang=zh).

The public documentation describes the standard `api/v3/sauc/bigmodel_async` route, while this
product uses the Agent Plan-specific `api/v3/plan/sauc/bigmodel_async` route required by its billing
plan. The Agent Plan endpoint is therefore treated as a versioned integration constant rather than
a permanent public contract. The authorized synthetic-audio provider test must pass before every
release that changes protocol or provider code.
