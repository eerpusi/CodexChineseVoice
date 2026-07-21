# Development Rules

## Scope

- This is an independent open-source macOS project, not part of Knot.
- Build a native macOS utility. Do not use Electron or a WebView-based desktop shell.
- The shortcut is active only while the Codex desktop app is frontmost.
- Holding `Command+R` records; releasing it finalizes transcription.
- Partial transcripts update the current Codex composer; final text replaces the active partial.
- The tool must never send the message automatically.

## Security

- Never read, print, log, commit, or bundle real API keys.
- Read provider credentials from process environment initially.
- Use `ARK_PLAN_API_KEY` for the initial Volcengine Agent Plan integration.
- Keep fixed protocol constants in code, not as misleading user configuration.
- Do not modify the user's shell profile or persist credentials without explicit authorization at
  action time.

## Architecture

- Keep microphone capture, hotkey handling, ASR transport, transcript editing, and app lifecycle in
  separate modules.
- Define a provider protocol so additional ASR services can be added without changing input logic.
- The initial provider uses Volcengine Doubao streaming ASR 2.0 with incremental and final events.
- Restrict accessibility writes to the focused Codex composer and preserve unrelated text.
- Keep source files below 300 lines; split responsibilities before files approach 250 lines.

## Quality

- Design before implementation and record major decisions in repository documentation.
- Add unit tests for hotkey gating, audio framing, protocol parsing, partial replacement, finalization,
  cancellation, and missing configuration.
- Run a real-provider test only when explicitly authorized and use synthetic, non-user audio.
- Verify the built app manually against Codex on a supported macOS version before claiming the
  workflow works end to end.
