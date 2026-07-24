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
