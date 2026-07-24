#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION="0.1.1" \
BUILD_NUMBER="2" \
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
