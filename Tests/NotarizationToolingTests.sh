#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

MOCK_BIN="${TEMP_DIR}/bin"
MOCK_LOG="${TEMP_DIR}/calls.log"
APP="${TEMP_DIR}/CodexChineseVoice.app"
ARCHIVE="${TEMP_DIR}/CodexChineseVoice-macos.zip"
CHECKSUM="${TEMP_DIR}/CodexChineseVoice-macos.sha256"
mkdir -p "${MOCK_BIN}" "${APP}/Contents/MacOS"
touch "${APP}/Contents/MacOS/CodexChineseVoice"

cat > "${MOCK_BIN}/dispatcher" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
tool="$(basename "$0")"
printf '%s %s\n' "${tool}" "$*" >> "${MOCK_LOG}"
case "${tool}" in
    codesign)
        if [[ " $* " == *" -dvv "* ]]; then
            printf 'Authority=%s\nflags=0x10000(runtime)\n' "${CODE_SIGN_IDENTITY}" >&2
        fi
        ;;
    ditto)
        touch "${@: -1}"
        ;;
    shasum)
        printf 'abc123  %s\n' "${@: -1}"
        ;;
esac
EOF
chmod +x "${MOCK_BIN}/dispatcher"
for tool in codesign ditto shasum spctl xcrun; do
    ln -s dispatcher "${MOCK_BIN}/${tool}"
done

export MOCK_LOG
PATH="${MOCK_BIN}:${PATH}" \
CODE_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
NOTARYTOOL_PROFILE="codex-chinese-voice" \
APP_PATH="${APP}" \
ARCHIVE_PATH="${ARCHIVE}" \
CHECKSUM_PATH="${CHECKSUM}" \
bash "${ROOT_DIR}/Scripts/notarize-release.sh"

grep -F 'xcrun notarytool submit' "${MOCK_LOG}" | grep -F -- '--keychain-profile codex-chinese-voice --wait' >/dev/null
grep -F "xcrun stapler staple ${APP}" "${MOCK_LOG}" >/dev/null
grep -F "xcrun stapler validate ${APP}" "${MOCK_LOG}" >/dev/null
grep -F "spctl -a -vv --type execute ${APP}" "${MOCK_LOG}" >/dev/null
[[ -f "${ARCHIVE}" ]]
[[ -f "${CHECKSUM}" ]]

echo "notarization tooling tests passed"
