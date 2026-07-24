#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

if CODE_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
    bash "${ROOT_DIR}/Scripts/build-app.sh" >"${TEMP_DIR}/missing-version.log" 2>&1; then
    echo "signed release build must require VERSION" >&2
    exit 1
fi
grep -F "VERSION is required for a signed release build" "${TEMP_DIR}/missing-version.log" >/dev/null

if CODE_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
    VERSION="0.1.1" \
    bash "${ROOT_DIR}/Scripts/build-app.sh" >"${TEMP_DIR}/missing-build.log" 2>&1; then
    echo "signed release build must require BUILD_NUMBER" >&2
    exit 1
fi
grep -F "BUILD_NUMBER is required for a signed release build" "${TEMP_DIR}/missing-build.log" >/dev/null

echo "release versioning tests passed"
