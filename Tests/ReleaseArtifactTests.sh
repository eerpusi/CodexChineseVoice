#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${ARCHIVE:-${ROOT_DIR}/.build/release-artifacts/CodexChineseVoice-macos.zip}"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

[[ -f "${ARCHIVE}" ]] || { echo "missing archive: ${ARCHIVE}" >&2; exit 1; }
ditto -x -k "${ARCHIVE}" "${TEMP_DIR}"

APP="${TEMP_DIR}/CodexChineseVoice.app"
APP_BINARY="${APP}/Contents/MacOS/CodexChineseVoice"
CLI_BINARY="${APP}/Contents/Helpers/codex-chinese-voice"
APP_ICON="${APP}/Contents/Resources/AppIcon.icns"

[[ -x "${APP_BINARY}" ]] || { echo "missing app executable" >&2; exit 1; }
[[ -x "${CLI_BINARY}" ]] || { echo "missing bundled CLI executable" >&2; exit 1; }
[[ -f "${APP_ICON}" ]] || { echo "missing app icon" >&2; exit 1; }

test "$(lipo -archs "${APP_BINARY}" | tr ' ' '\n' | sort | tr '\n' ' ')" = "arm64 x86_64 "
test "$(lipo -archs "${CLI_BINARY}" | tr ' ' '\n' | sort | tr '\n' ' ')" = "arm64 x86_64 "
test "$(plutil -extract CFBundleIdentifier raw -o - "${APP}/Contents/Info.plist")" = "com.lianenguang.CodexChineseVoice"
test "$(plutil -extract CFBundleIconFile raw -o - "${APP}/Contents/Info.plist")" = "AppIcon"
plutil -extract NSMicrophoneUsageDescription raw -o - "${APP}/Contents/Info.plist" >/dev/null

codesign --verify --deep --strict "${APP}"
if find "${APP}" -name config.toml -print -quit | grep -q .; then
    echo "configuration file must not be bundled" >&2
    exit 1
fi
if rg -a -F "ARK_PLAN_API_KEY=" "${APP}" >/dev/null; then
    echo "credential assignment found in app bundle" >&2
    exit 1
fi

"${CLI_BINARY}" --help >/dev/null
echo "release artifact tests passed"
