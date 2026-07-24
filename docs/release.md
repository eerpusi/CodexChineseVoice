# Release Process

The public artifact is a universal native macOS app with no command-line executable. The final
archive is signed with Developer ID, notarized by Apple, attached to a GitHub Release, and
referenced by a Cask in `eerpusi/homebrew-tap`.

## Stable identity and local replacement

Every release uses the same production bundle identifier:
`com.lianenguang.CodexChineseVoice`. Release version and build numbers change independently. A
new app build is signed and notarized again; this is code-signing trust, not encryption, and old
published archives are not rebuilt.

For local development replacement, stop the running app and remove only the previous local
`CodexChineseVoice Dev.app` before copying the fresh bundle to
`dist/CodexChineseVoice Dev.app`. Do not delete source files, user configuration, production app
bundles, or GitHub Release assets. Keeping one local development bundle registered with
LaunchServices prevents macOS from opening a stale duplicate.

## Context7-first changes

Before changing code, building, signing, publishing, or deleting files, query current Context7
documentation for the relevant framework, tool, or API and record the conclusion in the design or
research notes. A prior query in the same Codex session can be reused for related work; query again
when the subject changes. The project `PreToolUse` hook blocks `apply_patch` and mutating Bash
commands until the session transcript contains a Context7 query. Read-only inspection and
Context7 queries are intentionally allowed before the gate is satisfied.

## One-time setup

Install a valid `Developer ID Application` certificate and its private key in the login Keychain.
Confirm that macOS can see it:

```bash
security find-identity -p codesigning -v
```

Store notarization credentials in Keychain. This command prompts interactively and does not put the
app-specific password in the repository or shell profile:

```bash
xcrun notarytool store-credentials codex-chinese-voice
```

Authenticate GitHub CLI and confirm the account:

```bash
gh auth login -h github.com
gh auth status
```

## Publish

Set release metadata only for the current terminal session:

```bash
export CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARYTOOL_PROFILE="codex-chinese-voice"
export VERSION="0.1.1"
export BUILD_NUMBER="2"
export GITHUB_REPOSITORY="eerpusi/CodexChineseVoice"
export HOMEBREW_TAP_REPOSITORY="eerpusi/homebrew-tap"
```

Run the complete pipeline:

```bash
Scripts/release.sh --publish
```

The command builds and signs both architectures, stamps `CFBundleShortVersionString` from
`VERSION` and `CFBundleVersion` from `BUILD_NUMBER`, submits the ZIP to Apple, staples the ticket,
rebuilds and checksums the final ZIP, publishes or updates `v$VERSION`, and commits the matching
Cask SHA-256 to the Tap. `--prepare` stops before GitHub; `--check-only` validates existing local
artifacts and release metadata without publishing.

After publishing, verify a clean Homebrew install:

```bash
brew uninstall --cask codex-chinese-voice 2>/dev/null || true
brew install --cask eerpusi/tap/codex-chinese-voice
test -d "/Applications/CodexChineseVoice.app"
open -a CodexChineseVoice
```

The generated Cask must contain an `app "CodexChineseVoice.app"` stanza and no `binary` stanza.

Do not publish an ad-hoc signed archive. A real release must pass Apple notarization and the manual
acceptance checklist in `docs/acceptance.md`.
