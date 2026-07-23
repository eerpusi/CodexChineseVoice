# Release Acceptance

Date: 2026-07-23

## Automated

- `swift test`: PASS, 192 tests, 0 failures.
- Auto-send preference default, persistence, disabled behavior, exactly-once completion, and
  ineligible-session safeguards: PASS with deterministic tests.
- Universal app and bundled CLI (`arm64`, `x86_64`): PASS.
- Native app bundle build, LaunchServices launch, and process verification on the macOS host: PASS.
- CLI `--help`, `status`, and `stop` smoke checks without an API key: PASS.
- App bundle structure, Info.plist, code-signature integrity, checksum, secret/config exclusion:
  PASS for the local ad-hoc artifact.
- Notarization command orchestration: PASS with deterministic tool doubles.
- GitHub Release and Homebrew Tap input validation: PASS without external mutation.

## External release gates

- Developer ID Application signing: NOT RUN. No valid signing identity is currently installed.
- Apple notarization and stapling: NOT RUN.
- Real Volcengine provider test with repository-owned synthetic audio: NOT RUN; requires explicit
  authorization and a valid `ARK_PLAN_API_KEY`.
- Real Codex end-to-end test: NOT RUN for the final signed artifact. Must verify Codex-only
  `Command+R`, microphone capture, visible partial replacement, final replacement, preservation of
  unrelated composer text, and cancellation. With auto-send enabled, each successful non-empty
  final transcription must send exactly once; with it disabled, final text must remain in the
  composer. Partial, empty, failed, cancelled, stale, and unfocused sessions must never send.
- GitHub Release publication: NOT RUN. GitHub CLI authentication and repository remote are missing.
- Homebrew Tap clean install/upgrade/uninstall: NOT RUN until the GitHub Release exists.

The native Settings window and menu bar UI have been inspected on the macOS host. macOS desktop
apps do not use an iOS-style simulator; host execution is the applicable GUI test environment.
