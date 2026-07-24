#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PLIST="${ROOT_DIR}/.build/release-artifacts/CodexChineseVoice.app/Contents/Info.plist"

[[ -f "${APP_PLIST}" ]] || {
    echo "release pipeline test requires a prepared release artifact" >&2
    exit 1
}

ARTIFACT_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "${APP_PLIST}")"
ARTIFACT_BUILD_NUMBER="$(plutil -extract CFBundleVersion raw -o - "${APP_PLIST}")"

if ! rg -q 'verify-release-inputs\.sh' "${ROOT_DIR}/Scripts/release.sh"; then
    echo "release pipeline must verify committed release inputs before building" >&2
    exit 1
fi

VERSION="${ARTIFACT_VERSION}" \
BUILD_NUMBER="${ARTIFACT_BUILD_NUMBER}" \
GITHUB_REPOSITORY="example/CodexChineseVoice" \
HOMEBREW_TAP_REPOSITORY="example/homebrew-tap" \
bash "${ROOT_DIR}/Scripts/release.sh" --check-only

if VERSION="9.9.9" \
    BUILD_NUMBER="99" \
    GITHUB_REPOSITORY="example/CodexChineseVoice" \
    HOMEBREW_TAP_REPOSITORY="example/homebrew-tap" \
    bash "${ROOT_DIR}/Scripts/release.sh" --check-only > /dev/null 2>&1; then
    echo "release check must reject an archive whose app version does not match VERSION" >&2
    exit 1
fi

echo "release pipeline tests passed"
