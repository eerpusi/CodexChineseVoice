#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/script/build_and_run.sh"
PRODUCTION_INFO_PLIST="${ROOT_DIR}/Packaging/Info.plist"

grep -F 'PRODUCT_NAME="CodexChineseVoice"' "${SCRIPT}" >/dev/null
grep -F 'APP_NAME="CodexChineseVoice Dev"' "${SCRIPT}" >/dev/null
grep -F 'EXECUTABLE_NAME="CodexChineseVoiceDev"' "${SCRIPT}" >/dev/null
grep -F 'BUNDLE_ID="com.lianenguang.CodexChineseVoice.dev"' "${SCRIPT}" >/dev/null
grep -F 'swift build --product "${PRODUCT_NAME}"' "${SCRIPT}" >/dev/null
grep -F 'plutil -replace CFBundleIdentifier -string "${BUNDLE_ID}" "${APP_CONTENTS}/Info.plist"' "${SCRIPT}" >/dev/null
grep -F 'for process_id in $(pgrep -x "${EXECUTABLE_NAME}"); do' "${SCRIPT}" >/dev/null
grep -F 'running_binary="$(/bin/ps -p "${process_id}" -o comm=)"' "${SCRIPT}" >/dev/null
grep -F '[[ "${running_binary}" == "${APP_BINARY}" ]]' "${SCRIPT}" >/dev/null

test "$(plutil -extract CFBundleIdentifier raw -o - "${PRODUCTION_INFO_PLIST}")" = \
    "com.lianenguang.CodexChineseVoice"
test "$(plutil -extract CFBundleExecutable raw -o - "${PRODUCTION_INFO_PLIST}")" = "CodexChineseVoice"
! grep -F 'CodexVoiceDev' "${SCRIPT}" >/dev/null

echo "local development run tests passed"
