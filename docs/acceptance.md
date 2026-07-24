# Release Acceptance

Date: 2026-07-24

## v0.1.3 candidate

- Compact single-panel Settings UI with leading labels, trailing switches, and a contiguous Key
  input/save row: PASS in the fresh development bundle.
- API Key presentation remains masked as `********`; real credentials were not read or printed:
  PASS with focused tests and manual inspection.
- Full Swift suite: PASS, 162 core tests and 9 app tests, 0 failures.

## v0.1.2 candidate

- API-key resolution uses `ARK_PLAN_API_KEY`, then macOS Keychain, then one-time legacy TOML
  migration. Legacy data is deleted only after a successful Keychain save: PASS with deterministic
  tests.
- Keychain generic-password reads, initial writes, duplicate updates, deletion, and access failures:
  PASS with a fake Security client and no user credential access.
- Full Swift suite: PASS, 154 tests, 0 failures.
- Manual saved-Keychain-key save/clear and legacy-file migration in the fresh development app:
  NOT RUN. This remains a release gate so the maintainer can choose a disposable synthetic key.

## Automated

- `swift test`: PASS, 144 tests, 0 failures after removing CLI-only lifecycle coverage.
- Auto-send preference default, persistence, disabled behavior, exactly-once completion, and
  ineligible-session safeguards: PASS with deterministic tests.
- App-only SwiftPM manifest with no CLI product or target: PASS.
- Universal app (`arm64`, `x86_64`) containing only the main executable and resources: PASS.
- Release version stamping (`CFBundleShortVersionString=0.1.1`, `CFBundleVersion=2`): PASS.
- Native app bundle build, LaunchServices launch, and process verification on the macOS host: PASS.
- Homebrew Cask generation with an app stanza and no binary stanza: PASS.
- App bundle structure, Info.plist, code-signature integrity, checksum, secret/config exclusion:
  PASS for the local Developer ID-signed `v0.1.1` candidate.
- Notarization command orchestration: PASS with deterministic tool doubles.
- GitHub Release and Homebrew Tap input validation: PASS without external mutation.

## External release gates

- Developer ID signing, Apple notarization, GitHub Release publication, and Homebrew Cask update
  for `v0.1.3`: PASS. The remote tag points to the release commit and the Cask SHA-256 matches the
  published ZIP asset.
- The signed and notarized `v0.1.0` release remains published with its original artifact.
- Developer ID signing and Hardened Runtime for app-only `v0.1.1`: PASS locally with team
  `DYT47RAAJW`.
- Apple notarization, GitHub publication, and Tap update for app-only `v0.1.1`: PASS. The notarized
  artifact was accepted by Apple, published at GitHub, and referenced by the updated Cask.
- Real Volcengine provider test with repository-owned synthetic audio: NOT RUN; requires explicit
  authorization and a valid `ARK_PLAN_API_KEY`.
- Real Codex end-to-end test: PASS by maintainer confirmation. The maintainer verified Codex-only
  `Command+R`, microphone capture, partial/final replacement, preservation of unrelated composer
  text, cancellation, and auto-send behavior. The Computer Use agent cannot operate its own Codex
  host window because of a platform safety boundary.
- Homebrew Cask remote resolution for `v0.1.1`: PASS. A clean install/upgrade/uninstall cycle was
  not run to avoid replacing the currently verified local app during publication.

The native Settings window and menu bar UI have been inspected on the macOS host. macOS desktop
apps do not use an iOS-style simulator; host execution is the applicable GUI test environment.
