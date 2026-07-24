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
export VERSION="0.1.3"
export BUILD_NUMBER="3"
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

## Post-Release Verification And Learning Log

After every external release, record any interruption, recovery, or verification gap in this
section. Before declaring the release complete, verify all of the following from the remote
services rather than relying on local command startup:

1. The GitHub Release is public and contains the ZIP and checksum asset.
2. The release ZIP digest matches the generated Cask SHA-256.
3. The remote Tap Cask has the intended version, release URL, and `app` stanza.
4. The primary repository branch and working tree are clean after publishing.

### v0.1.2

- The Apple notarization submission was accepted, but the command observer returned while the
  long-running wait was still in progress. Recovery: query the submission ID with
  `xcrun notarytool info`; when accepted, staple and validate the existing app instead of
  submitting it again.
- The GitHub Release assets were created before the Tap update completed, leaving the remote Cask
  at `0.1.1`. Recovery: compare the remote Cask against the Release asset digest, then update the
  Cask through the GitHub contents API and verify its raw remote content.

### v0.1.3 preparation

- Context7 GitHub CLI research confirms that `gh release create` can create a tagged release and
  upload the ZIP and checksum assets together; `gh release upload --clobber` is reserved for an
  intentional replacement of an existing asset. This release uses a new `v0.1.3` tag.
- The compact single-panel settings UI was manually inspected in the fresh development bundle;
  preference switches share a trailing edge and the Key field remains masked.
