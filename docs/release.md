# Release Process

The public artifact is a universal native macOS app containing an optional universal CLI helper.
The final archive is signed with Developer ID, notarized by Apple, attached to a GitHub Release,
and referenced by a Cask in `eerpusi/homebrew-tap`.

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
export VERSION="0.1.0"
export GITHUB_REPOSITORY="eerpusi/CodexChineseVoice"
export HOMEBREW_TAP_REPOSITORY="eerpusi/homebrew-tap"
```

Run the complete pipeline:

```bash
Scripts/release.sh --publish
```

The command builds and signs both architectures, submits the ZIP to Apple, staples the ticket,
rebuilds and checksums the final ZIP, publishes or updates `v$VERSION`, and commits the matching
Cask SHA-256 to the Tap. `--prepare` stops before GitHub; `--check-only` validates existing local
artifacts and release metadata without publishing.

After publishing, verify a clean Homebrew install:

```bash
brew uninstall --cask codex-chinese-voice 2>/dev/null || true
brew install --cask eerpusi/tap/codex-chinese-voice
codex-chinese-voice status
```

Do not publish an ad-hoc signed archive. A real release must pass Apple notarization and the manual
acceptance checklist in `docs/acceptance.md`.
