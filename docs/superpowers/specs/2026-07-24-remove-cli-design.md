# Remove the CLI Design

Date: 2026-07-24

## Goal

CodexChineseVoice is distributed and operated only as a native macOS menu bar app. The project
must not build, bundle, install, document, or maintain a command-line executable.

## Observable Result

- SwiftPM exposes the `CodexChineseVoice` app executable and core library, with no
  `codex-chinese-voice` executable product or `CodexChineseVoiceCLI` target.
- `CodexChineseVoice.app` contains its main executable and resources but no `Contents/Helpers`
  directory or CLI executable.
- The Homebrew Cask installs only `CodexChineseVoice.app` and creates no terminal command.
- The app continues to start its voice coordinator directly through `ApplicationDelegate` and
  `VoiceApplicationModel`.

## Code Scope

Delete `Sources/CodexChineseVoiceCLI` and the core lifecycle implementation that exists only for
CLI commands and detached background-process management:

- command parsing and routing;
- PID and lock-file state;
- detached process launching and POSIX spawning;
- background process inspection, signaling, and control.

Keep `PermissionPreflight` and `SystemPermissionProvider`. The menu bar app uses both for its
permission workflow. Keep the existing configuration directory and Homebrew Cask token because
they are persistent product identifiers, not evidence of terminal functionality.

## Packaging and Distribution

`Scripts/build-app.sh` builds only the universal `CodexChineseVoice` app executable. Signing and
notarization apply to the app bundle without a nested helper. `Scripts/generate-homebrew-cask.sh`
emits only the `app` stanza.

The published `v0.1.0` assets remain immutable. A later `v0.1.1` release will contain the app-only
archive and update the Tap Cask. Publishing that version is a separate externally visible action
and requires confirmation after local verification.

## Test Strategy

Implementation follows focused RED-GREEN slices:

1. Add a package-manifest check that rejects the CLI product and target, observe it fail, then
   remove the target and CLI source.
2. Change the release artifact test to reject `Contents/Helpers` and the CLI executable, observe it
   fail against a freshly built current artifact, then remove helper build, copy, and signing steps.
3. Add a Cask-generation check that rejects a `binary` stanza, observe it fail, then remove that
   stanza from the generator.
4. Delete CLI-only lifecycle tests and production modules together, then run the full Swift suite
   to prove the remaining app and core compile and pass.
5. Update README, release, and acceptance documentation to describe an app-only product.

Final verification builds one fresh unsigned universal app archive, runs release artifact and
release tooling checks, runs `swift test`, and confirms repository searches contain no executable
CLI target, bundled helper, Homebrew `binary` stanza, or user instructions for CLI commands.

## Stop Conditions

Stop for user input before changing an already published GitHub Release, pushing a new release or
Tap update, or removing a persistent configuration path that could affect existing users.
