#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION="0.1.0" \
GITHUB_REPOSITORY="example/CodexChineseVoice" \
HOMEBREW_TAP_REPOSITORY="example/homebrew-tap" \
bash "${ROOT_DIR}/Scripts/release.sh" --check-only

echo "release pipeline tests passed"
