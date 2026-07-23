#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-${ROOT_DIR}/.build/release-artifacts/CodexChineseVoice.app}"
ARCHIVE_PATH="${ARCHIVE_PATH:-${ROOT_DIR}/.build/release-artifacts/CodexChineseVoice-macos.zip}"
CHECKSUM_PATH="${CHECKSUM_PATH:-${ROOT_DIR}/.build/release-artifacts/CodexChineseVoice-macos.sha256}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"

[[ -n "${CODE_SIGN_IDENTITY}" ]] || { echo "CODE_SIGN_IDENTITY is required" >&2; exit 2; }
[[ -n "${NOTARYTOOL_PROFILE}" ]] || { echo "NOTARYTOOL_PROFILE is required" >&2; exit 2; }
[[ -d "${APP_PATH}" ]] || { echo "missing app bundle: ${APP_PATH}" >&2; exit 1; }

SIGNING_DETAILS="$(codesign -dvv "${APP_PATH}" 2>&1)"
grep -F "Authority=${CODE_SIGN_IDENTITY}" <<< "${SIGNING_DETAILS}" >/dev/null || {
    echo "app is not signed with CODE_SIGN_IDENTITY" >&2
    exit 1
}
grep -F "runtime" <<< "${SIGNING_DETAILS}" >/dev/null || {
    echo "app is not signed with hardened runtime" >&2
    exit 1
}

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
rm -f "${ARCHIVE_PATH}" "${CHECKSUM_PATH}"
ditto -c -k --keepParent "${APP_PATH}" "${ARCHIVE_PATH}"

xcrun notarytool submit "${ARCHIVE_PATH}" \
    --keychain-profile "${NOTARYTOOL_PROFILE}" \
    --wait
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
spctl -a -vv --type execute "${APP_PATH}"

rm -f "${ARCHIVE_PATH}" "${CHECKSUM_PATH}"
ditto -c -k --keepParent "${APP_PATH}" "${ARCHIVE_PATH}"
shasum -a 256 "${ARCHIVE_PATH}" > "${CHECKSUM_PATH}"

echo "notarized ${APP_PATH}"
echo "created ${ARCHIVE_PATH}"
echo "created ${CHECKSUM_PATH}"
