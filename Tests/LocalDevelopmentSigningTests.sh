#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

MOCK_BIN="${TEMP_DIR}/bin"
MOCK_LOG="${TEMP_DIR}/calls.log"
APP="${TEMP_DIR}/CodexChineseVoice.app"
mkdir -p "${MOCK_BIN}" "${APP}/Contents/MacOS"
touch "${APP}/Contents/MacOS/CodexChineseVoice"

cat > "${MOCK_BIN}/security" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' \
    '  1) ABCDEF "Apple Development: Local Developer (TEAM123456)"' \
    '     1 valid identities found'
EOF

cat > "${MOCK_BIN}/codesign" <<'EOF'
#!/usr/bin/env bash
printf 'codesign %s\n' "$*" >> "${MOCK_LOG}"
EOF

chmod +x "${MOCK_BIN}/security" "${MOCK_BIN}/codesign"
export MOCK_LOG

PATH="${MOCK_BIN}:${PATH}" \
    bash "${ROOT_DIR}/Scripts/sign-local-app.sh" "${APP}"

grep -F 'codesign --force --options runtime --timestamp=none' "${MOCK_LOG}" \
    | grep -F -- '--entitlements' \
    | grep -F -- '--sign Apple Development: Local Developer (TEAM123456)' \
    | grep -F -- "${APP}" >/dev/null
grep -F "codesign --verify --deep --strict ${APP}" "${MOCK_LOG}" >/dev/null

echo "local development signing tests passed"
