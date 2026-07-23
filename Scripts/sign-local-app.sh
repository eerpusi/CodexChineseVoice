#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-}"

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
    echo "usage: $0 /absolute/path/CodexChineseVoice.app" >&2
    exit 2
fi

identity="${LOCAL_CODE_SIGN_IDENTITY:-}"
if [[ -z "${identity}" ]]; then
    identity="$({ security find-identity -v -p codesigning 2>/dev/null || true; } \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
        | head -n 1)"
fi

if [[ -z "${identity}" ]]; then
    echo "no Apple Development signing identity found; install one or set LOCAL_CODE_SIGN_IDENTITY" >&2
    exit 3
fi

codesign \
    --force \
    --options runtime \
    --timestamp=none \
    --entitlements "${ROOT_DIR}/Packaging/CodexChineseVoice.entitlements" \
    --sign "${identity}" \
    "${APP_PATH}"

codesign --verify --deep --strict "${APP_PATH}"
