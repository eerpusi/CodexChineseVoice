# CodexChineseVoice

An independent, open-source native macOS menu bar app for Chinese voice input in Codex.

## Product Goal

- Hold `Command+R` while Codex is focused to record speech.
- Stream audio to a configurable ASR provider and show partial text in the Codex composer.
- Replace the partial text with the final transcript when the shortcut is released.
- Automatically submit a successful final transcript when the user-controlled setting is enabled.
  The setting defaults to enabled and can be turned off to leave the final text in the composer.
- Keep provider credentials outside the application bundle and repository.

## Initial Provider

The first provider uses the official Volcengine Doubao streaming ASR 2.0 Agent Plan protocol.
Provider credentials remain local and are never bundled with the executable.

## Install and run

This is a native SwiftPM macOS app, not an Electron or WebView application.

Install the signed and notarized menu bar app with:

```bash
brew install --cask eerpusi/tap/codex-chinese-voice
```

Alternatively, download `CodexChineseVoice-macos.zip` from the
[GitHub Releases page](https://github.com/eerpusi/CodexChineseVoice/releases), extract it, and move
`CodexChineseVoice.app` to `/Applications`.

For local development, build and launch the app bundle with:

```bash
./script/build_and_run.sh
```

This creates and launches `dist/CodexChineseVoice Dev.app`, a development-only app with a separate
bundle identifier. It can run alongside the production `CodexChineseVoice.app` installed from
Homebrew or a release zip.

Starting with `v0.1.1`, the release contains only the signed and notarized
`CodexChineseVoice.app`; it does not install a terminal command.
Open the app once, then use its menu bar item to configure the provider key, permissions, and
whether completed transcriptions are sent automatically.

The app stores a saved provider key in the macOS Keychain. `ARK_PLAN_API_KEY` takes priority for
the current process, which is useful for temporary local runs and is never persisted by the app.
On first use after upgrading, a legacy local configuration at
`~/.config/codex-chinese-voice/config.toml` is copied into Keychain and deleted only after the
Keychain write succeeds. The Settings window can clear the saved Keychain key without displaying
its value.

Do not put a real key in the repository, shell profile, issue, or log. Export it only in the
terminal session that launches the utility when possible.

## macOS permissions

The first run requests Microphone permission and opens the macOS Accessibility authorization
prompt when needed. Grant access to the terminal or installed executable in **System Settings >
Privacy & Security**, then run the command again. The utility does not change these settings or
send partial, empty, failed, cancelled, stale, or unfocused transcriptions. A successful final
transcription is sent once only when the auto-send setting is enabled.

## Current status

The core voice path and native menu bar app are implemented. Offline coverage includes hotkey
gating, audio framing, Volcengine protocol/provider behavior, composer replacement, permissions,
cancellation, configurable final-transcript submission, and app presentation preferences. Local
universal unsigned app bundles can be built with `Scripts/build-app.sh --unsigned`.

The signed and notarized `v0.1.0` release is public. The next release is app-only and removes the
legacy CLI from SwiftPM, the app bundle, and Homebrew. Real-provider calls and end-to-end
interaction with a real Codex input field remain manual acceptance gates for each release.

Maintainers can run the complete signed, notarized, GitHub Release, and Homebrew Tap pipeline with
`Scripts/release.sh --publish` after configuring the prerequisites in
[`docs/release.md`](docs/release.md).

Release builds receive their app version from `VERSION` and their incrementing build number from
`BUILD_NUMBER`; the packaging script writes both values into the generated app bundle.

## Maintainer rules

The production bundle identifier is permanently `com.lianenguang.CodexChineseVoice`. Each new
distributable build is signed and notarized independently; this is signing and notarization, not
encryption, and historical release archives remain unchanged. Local replacement removes only the
old `dist/CodexChineseVoice Dev.app` before launching its fresh replacement, so it does not disturb
an installed production app.

Before implementation or other state-changing work, maintainers query current Context7
documentation and record the result in a design or research note. A prior query in the same Codex
session can be reused for related work; query again when the subject changes. The project PreToolUse
hook enforces this requirement for code edits and mutating shell commands. Read-only inspection
and Context7 queries remain available while research is being gathered.
