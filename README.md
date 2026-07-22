# CodexChineseVoice

An independent, open-source macOS command-line utility for Chinese voice input in Codex.

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

This is a native SwiftPM executable, not an Electron or WebView application.

```bash
swift build -c release
swift run codex-chinese-voice
```

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

The repository contains a work-in-progress prototype for Codex-only `Command+R` gating,
microphone conversion to 16 kHz mono 16-bit PCM, Volcengine WebSocket streaming, partial/final
composer replacement, and configuration loading. Offline protocol and configuration tests pass;
provider, audio, composer, and coordinator coverage is still incomplete.

Real-provider calls and end-to-end interaction with a real Codex input field have not yet been
verified. Do not treat this repository state as a production distribution until those checks and
packaging/signing work are completed.
