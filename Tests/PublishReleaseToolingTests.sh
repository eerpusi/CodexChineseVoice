#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

ARCHIVE="${TEMP_DIR}/CodexChineseVoice-macos.zip"
CHECKSUM="${TEMP_DIR}/CodexChineseVoice-macos.sha256"
touch "${ARCHIVE}"
shasum -a 256 "${ARCHIVE}" > "${CHECKSUM}"

VERSION="0.1.0" \
GITHUB_REPOSITORY="example/CodexChineseVoice" \
HOMEBREW_TAP_REPOSITORY="example/homebrew-tap" \
ARCHIVE_PATH="${ARCHIVE}" \
CHECKSUM_PATH="${CHECKSUM}" \
bash "${ROOT_DIR}/Scripts/publish-release.sh" --check-only

echo "publish release tooling tests passed"
