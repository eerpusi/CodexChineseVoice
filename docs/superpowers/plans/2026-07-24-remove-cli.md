# Remove the CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship and maintain CodexChineseVoice only as a native macOS app, with no CLI product, bundled helper, Homebrew terminal command, or CLI-only lifecycle code.

**Architecture:** The SwiftUI app remains the only executable and continues to start `VoiceApplicationModel` directly from `ApplicationDelegate`. Packaging signs and archives only the universal app executable and resources; the Cask installs only the app. Permission and configuration services stay in the core library, while detached-process command infrastructure is removed.

**Tech Stack:** Swift 6, SwiftPM, macOS SwiftUI/AppKit, Bash release tooling, Homebrew Cask, XCTest, codesign.

---

## Working Rules

- Work only in `/Users/lianenguang/Desktop/CodexChineseVoice`; Git worktrees are prohibited.
- Preserve the existing modified `AGENTS.md` and untracked `.vscode/` and documentation files.
- Use `apply_patch` for every manual edit and deletion.
- Do not create a Git commit unless the user explicitly requests one.
- Do not modify `v0.1.0`, publish `v0.1.1`, or push a Tap update during this plan.

### Task 1: Make the App Archive Reject CLI Helpers

**Files:**
- Modify: `Tests/ReleaseArtifactTests.sh`
- Modify: `Scripts/build-app.sh`

- [ ] **Step 1: Build the current artifact as the RED fixture**

Run:

```bash
Scripts/build-app.sh --unsigned
```

Expected: exit 0 and an archive at `.build/release-artifacts/CodexChineseVoice-macos.zip` that still contains `CodexChineseVoice.app/Contents/Helpers/codex-chinese-voice`.

- [ ] **Step 2: Change the artifact test to require an app-only bundle**

Remove the `CLI_BINARY` variable, CLI executable assertion, CLI architecture assertion, and CLI `--help` smoke check from `Tests/ReleaseArtifactTests.sh`. Add this assertion immediately after the main executable assertion:

```bash
[[ ! -e "${APP}/Contents/Helpers" ]] || {
    echo "app bundle must not contain CLI helpers" >&2
    exit 1
}
```

- [ ] **Step 3: Run the artifact test and verify RED**

Run:

```bash
Tests/ReleaseArtifactTests.sh
```

Expected: FAIL with `app bundle must not contain CLI helpers` because the fixture was built before the packaging change.

- [ ] **Step 4: Remove CLI build, copy, and signing behavior**

In `Scripts/build-app.sh`:

- remove `CLI_NAME` and `CLI_BINARY`;
- make `--check-only` reject `${APP_DIR}/Contents/Helpers` instead of validating a CLI;
- remove the CLI `swift build`, built-binary lookup, and executable check;
- create only `Contents/MacOS` and `Contents/Resources`;
- copy and chmod only the app binary;
- sign only the app bundle in both unsigned and Developer ID branches;
- verify only the app bundle.

The check-only assertion must be:

```bash
[[ ! -e "${APP_DIR}/Contents/Helpers" ]] || {
    echo "app bundle must not contain CLI helpers" >&2
    exit 1
}
```

- [ ] **Step 5: Rebuild and verify GREEN**

Run:

```bash
Scripts/build-app.sh --unsigned
Tests/ReleaseArtifactTests.sh
Scripts/build-app.sh --check-only
```

Expected: all three commands exit 0; the archive test prints `release artifact tests passed`, and check-only prints `release artifact checks passed`.

### Task 2: Stop Homebrew from Installing a Terminal Command

**Files:**
- Create: `Tests/HomebrewCaskTests.sh`
- Modify: `Scripts/generate-homebrew-cask.sh`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add the failing Cask-generation test**

Create `Tests/HomebrewCaskTests.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

ARCHIVE="${TEMP_DIR}/CodexChineseVoice-macos.zip"
CASK="${TEMP_DIR}/codex-chinese-voice.rb"
touch "${ARCHIVE}"

GITHUB_OWNER="example" \
GITHUB_REPOSITORY="CodexChineseVoice" \
VERSION="0.1.1" \
ARCHIVE="${ARCHIVE}" \
OUTPUT="${CASK}" \
bash "${ROOT_DIR}/Scripts/generate-homebrew-cask.sh"

grep -F 'app "CodexChineseVoice.app"' "${CASK}" >/dev/null
if grep -F 'binary ' "${CASK}" >/dev/null; then
    echo "Cask must not install a CLI binary" >&2
    exit 1
fi

echo "homebrew cask tests passed"
```

Make the new test executable:

```bash
chmod +x Tests/HomebrewCaskTests.sh
```

- [ ] **Step 2: Run the Cask test and verify RED**

Run:

```bash
Tests/HomebrewCaskTests.sh
```

Expected: FAIL with `Cask must not install a CLI binary`.

- [ ] **Step 3: Remove the generated `binary` stanza**

Delete this line from `Scripts/generate-homebrew-cask.sh`:

```bash
printf '  binary "#{appdir}/CodexChineseVoice.app/Contents/Helpers/codex-chinese-voice"\n'
```

- [ ] **Step 4: Run the Cask test and verify GREEN**

Run:

```bash
Tests/HomebrewCaskTests.sh
```

Expected: PASS with `homebrew cask tests passed`.

- [ ] **Step 5: Add the check to CI**

Add `Tests/HomebrewCaskTests.sh` to the existing `Test release tooling` command block in `.github/workflows/ci.yml`, before `Tests/PublishReleaseToolingTests.sh`.

### Task 3: Remove the SwiftPM CLI Product and Source Target

**Files:**
- Create: `Tests/AppOnlyPackageTests.sh`
- Modify: `Package.swift`
- Delete: `Sources/CodexChineseVoiceCLI/CodexChineseVoiceCLI.swift`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add a package-manifest test**

Create `Tests/AppOnlyPackageTests.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_JSON="$(mktemp)"
trap 'rm -f "${MANIFEST_JSON}"' EXIT

cd "${ROOT_DIR}"
swift package dump-package > "${MANIFEST_JSON}"

test "$(plutil -extract products raw -o - "${MANIFEST_JSON}")" = "2"
test "$(plutil -extract products.0.name raw -o - "${MANIFEST_JSON}")" = "CodexChineseVoiceCore"
test "$(plutil -extract products.1.name raw -o - "${MANIFEST_JSON}")" = "CodexChineseVoice"
test "$(plutil -extract targets raw -o - "${MANIFEST_JSON}")" = "3"
test "$(plutil -extract targets.0.name raw -o - "${MANIFEST_JSON}")" = "CodexChineseVoiceCore"
test "$(plutil -extract targets.1.name raw -o - "${MANIFEST_JSON}")" = "CodexChineseVoiceApp"
test "$(plutil -extract targets.2.name raw -o - "${MANIFEST_JSON}")" = "CodexChineseVoiceCoreTests"
[[ ! -d "${ROOT_DIR}/Sources/CodexChineseVoiceCLI" ]] || {
    echo "CLI source target must be removed" >&2
    exit 1
}

echo "app-only package tests passed"
```

Make the new test executable:

```bash
chmod +x Tests/AppOnlyPackageTests.sh
```

- [ ] **Step 2: Run the package test and verify RED**

Run:

```bash
Tests/AppOnlyPackageTests.sh
```

Expected: FAIL because the manifest currently has three products and four targets.

- [ ] **Step 3: Remove the CLI product and target**

Delete these declarations from `Package.swift`:

```swift
.executable(
    name: "codex-chinese-voice",
    targets: ["CodexChineseVoiceCLI"]
),
```

```swift
.executableTarget(
    name: "CodexChineseVoiceCLI",
    dependencies: ["CodexChineseVoiceCore"]
),
```

Delete `Sources/CodexChineseVoiceCLI/CodexChineseVoiceCLI.swift`.

- [ ] **Step 4: Run the package test and verify GREEN**

Run:

```bash
Tests/AppOnlyPackageTests.sh
swift build --product CodexChineseVoice
```

Expected: the package test prints `app-only package tests passed`, and the app product builds successfully.

- [ ] **Step 5: Add the package check to CI**

Add a new CI step immediately before `Run Swift tests`:

```yaml
- name: Verify app-only package
  run: Tests/AppOnlyPackageTests.sh
```

### Task 4: Delete CLI-Only Background Process Infrastructure

**Files:**
- Modify: `Tests/AppOnlyPackageTests.sh`
- Delete: `Sources/CodexChineseVoiceCore/Lifecycle/AgentProcessState.swift`
- Delete: `Sources/CodexChineseVoiceCore/Lifecycle/BackgroundProcessController.swift`
- Delete: `Sources/CodexChineseVoiceCore/Lifecycle/DetachedAgentProcessLauncher.swift`
- Delete: `Sources/CodexChineseVoiceCore/Lifecycle/LifecycleCommand.swift`
- Delete: `Sources/CodexChineseVoiceCore/Lifecycle/LifecycleCommandRouter.swift`
- Delete: `Sources/CodexChineseVoiceCore/Lifecycle/POSIXSpawnExecutor.swift`
- Delete: `Sources/CodexChineseVoiceCore/Lifecycle/SystemAgentProcessInspector.swift`
- Delete: `Sources/CodexChineseVoiceCore/Lifecycle/SystemAgentProcessSignaler.swift`
- Delete: `Tests/CodexChineseVoiceCoreTests/BackgroundProcessLockingTests.swift`
- Delete: `Tests/CodexChineseVoiceCoreTests/DetachedAgentProcessLauncherTests.swift`
- Delete: `Tests/CodexChineseVoiceCoreTests/LifecycleCommandRouterTests.swift`
- Delete: `Tests/CodexChineseVoiceCoreTests/LifecycleTests.swift`
- Delete: `Tests/CodexChineseVoiceCoreTests/PIDFileLockTests.swift`
- Delete: `Tests/CodexChineseVoiceCoreTests/PIDFileStoreTests.swift`
- Delete: `Tests/CodexChineseVoiceCoreTests/POSIXSpawnExecutorTests.swift`
- Delete: `Tests/CodexChineseVoiceCoreTests/SystemAgentProcessInspectorTests.swift`
- Delete: `Tests/CodexChineseVoiceCoreTests/SystemAgentProcessSignalerTests.swift`

- [ ] **Step 1: Extend the structural test with the exact removal list**

Add this block before the final success message in `Tests/AppOnlyPackageTests.sh`:

```bash
CLI_ONLY_PATHS=(
    Sources/CodexChineseVoiceCore/Lifecycle/AgentProcessState.swift
    Sources/CodexChineseVoiceCore/Lifecycle/BackgroundProcessController.swift
    Sources/CodexChineseVoiceCore/Lifecycle/DetachedAgentProcessLauncher.swift
    Sources/CodexChineseVoiceCore/Lifecycle/LifecycleCommand.swift
    Sources/CodexChineseVoiceCore/Lifecycle/LifecycleCommandRouter.swift
    Sources/CodexChineseVoiceCore/Lifecycle/POSIXSpawnExecutor.swift
    Sources/CodexChineseVoiceCore/Lifecycle/SystemAgentProcessInspector.swift
    Sources/CodexChineseVoiceCore/Lifecycle/SystemAgentProcessSignaler.swift
)
for path in "${CLI_ONLY_PATHS[@]}"; do
    [[ ! -e "${ROOT_DIR}/${path}" ]] || {
        echo "CLI-only source must be removed: ${path}" >&2
        exit 1
    }
done
```

- [ ] **Step 2: Run the structural test and verify RED**

Run:

```bash
Tests/AppOnlyPackageTests.sh
```

Expected: FAIL naming `Sources/CodexChineseVoiceCore/Lifecycle/AgentProcessState.swift`.

- [ ] **Step 3: Delete the listed CLI-only source and test files**

Delete every source and test file listed under Task 4. Keep these app-required files:

```text
Sources/CodexChineseVoiceCore/Lifecycle/PermissionPreflight.swift
Sources/CodexChineseVoiceCore/Lifecycle/SystemPermissionProvider.swift
Tests/CodexChineseVoiceCoreTests/PermissionPreflightTests.swift
```

- [ ] **Step 4: Verify GREEN and the remaining app behavior**

Run:

```bash
Tests/AppOnlyPackageTests.sh
swift test
```

Expected: the package test passes and the full Swift test suite exits 0 with no failures.

### Task 5: Align Active Documentation with an App-Only Product

**Files:**
- Modify: `README.md`
- Modify: `docs/release.md`
- Modify: `docs/acceptance.md`

- [ ] **Step 1: Update installation and status language**

In `README.md`:

- change the install sentence to `Install the signed and notarized menu bar app with:`;
- remove all references to installing an optional CLI;
- remove the obsolete `Until that release exists` wording;
- keep the Homebrew Cask command and config directory path;
- state that the release contains only `CodexChineseVoice.app`;
- update Current status to say `v0.1.0` is published and a later app-only release removes the legacy CLI.

- [ ] **Step 2: Update the release procedure**

In `docs/release.md`:

- describe the public artifact as a universal native app with no CLI helper;
- change the example version to `0.1.1`;
- replace `codex-chinese-voice status` in the clean-install check with:

```bash
test -d "/Applications/CodexChineseVoice.app"
open -a CodexChineseVoice
```

- state that a release Cask must contain an `app` stanza and no `binary` stanza.

- [ ] **Step 3: Update the acceptance record**

In `docs/acceptance.md`:

- replace the universal app and bundled CLI bullet with an app-only universal bundle bullet;
- replace CLI smoke checks with app-only manifest and Cask-generation checks;
- state that `v0.1.0` remains the prior published release and that signed/notarized `v0.1.1` publication is not part of this local change;
- leave real-provider and real-Codex manual checks as explicit external gates.

- [ ] **Step 4: Check active documentation**

Run:

```bash
rg -n 'optional CLI|bundled CLI|CLI helper|codex-chinese-voice status|Contents/Helpers' README.md docs/release.md docs/acceptance.md
```

Expected: no matches.

### Task 6: Fresh Integration Verification

**Files:**
- Verify only; no additional files should change.

- [ ] **Step 1: Terminate running app processes before building**

Run:

```bash
pkill -x CodexChineseVoice 2>/dev/null || true
```

Expected: no `CodexChineseVoice` process remains.

- [ ] **Step 2: Build exactly one fresh local app bundle**

Run:

```bash
script/build_and_run.sh
```

Expected: exit 0, one fresh app at `dist/CodexChineseVoice.app`, and the app launches from that absolute path.

- [ ] **Step 3: Verify the running executable and fresh bundle**

Run:

```bash
pgrep -x CodexChineseVoice
ps -p "$(pgrep -x CodexChineseVoice | head -1)" -o command=
stat -f '%Sm %N' -t '%Y-%m-%d %H:%M:%S' dist/CodexChineseVoice.app
test ! -e dist/CodexChineseVoice.app/Contents/Helpers
```

Expected: the command path resolves inside `/Users/lianenguang/Desktop/CodexChineseVoice/dist/CodexChineseVoice.app`, the bundle timestamp matches this build, and the helper assertion passes.

- [ ] **Step 4: Run all automated release checks from fresh outputs**

Run:

```bash
swift test
Tests/AppOnlyPackageTests.sh
Tests/HomebrewCaskTests.sh
Scripts/build-app.sh --unsigned
Tests/ReleaseArtifactTests.sh
Tests/NotarizationToolingTests.sh
Tests/PublishReleaseToolingTests.sh
VERSION=0.1.1 \
GITHUB_REPOSITORY=example/CodexChineseVoice \
HOMEBREW_TAP_REPOSITORY=example/homebrew-tap \
Scripts/release.sh --check-only
```

Expected: every command exits 0; Swift reports no failures; the app-only, Cask, artifact, notarization, publishing, and release pipeline checks print their success messages.

- [ ] **Step 5: Review the final scope**

Run:

```bash
git status --short
git diff --stat
git diff -- Package.swift Scripts Tests README.md docs/release.md docs/acceptance.md .github/workflows/ci.yml
```

Expected: only the planned CLI-removal files plus the approved spec and plan are changed; pre-existing user-owned changes remain untouched.

Report local verification results and ask for explicit authorization before publishing `v0.1.1`.
