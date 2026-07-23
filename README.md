# CodexChineseVoice

An independent, open-source native macOS menu bar app for Chinese voice input in Codex.

## Product Goal

- Hold `Command+R` while Codex is focused to record speech.
- Stream audio to a configurable ASR provider and show partial text in the Codex composer.
- Replace the partial text with the final transcript when the shortcut is released.
- Never submit the Codex message automatically.
- Keep provider credentials outside the application bundle and repository.

## Initial Provider

The first provider uses the official Volcengine Doubao streaming ASR 2.0 Agent Plan protocol.
Provider credentials remain local and are never bundled with the executable.

## Install and run

This is a native SwiftPM macOS app, not an Electron or WebView application.

After the first public release, install both the menu bar app and its optional CLI with:

```bash
brew install --cask eerpusi/tap/codex-chinese-voice
```

Until that release exists, build and launch the local app bundle with:

```bash
./script/build_and_run.sh
```

The release app is distributed as a signed and notarized `CodexChineseVoice.app` archive.
Open the app once, then use its menu bar item to configure the provider key and permissions.

The provider key is read from `ARK_PLAN_API_KEY` first. A local fallback file is supported at:

```text
~/.config/codex-chinese-voice/config.toml
```

Its minimal format is:

```toml
ark_plan_api_key = "your-key"
```

Do not put a real key in the repository, shell profile, issue, or log. Export it only in the
terminal session that launches the utility when possible.

## macOS permissions

The first run requests Microphone permission and opens the macOS Accessibility authorization
prompt when needed. Grant access to the terminal or installed executable in **System Settings >
Privacy & Security**, then run the command again. The utility does not change these settings or
send an automatic message.

## Current status

The core voice path and native menu bar app are implemented. Offline coverage includes hotkey
gating, audio framing, Volcengine protocol/provider behavior, composer replacement, permissions,
cancellation, and app presentation preferences. Local universal unsigned app bundles can be built
with `Scripts/build-app.sh --unsigned`.

Real-provider calls, signed/notarized distribution, and end-to-end interaction with a real Codex
input field remain release gates. Do not treat an unsigned local bundle as a production release.

Maintainers can run the complete signed, notarized, GitHub Release, and Homebrew Tap pipeline with
`Scripts/release.sh --publish` after configuring the prerequisites in
[`docs/release.md`](docs/release.md).
