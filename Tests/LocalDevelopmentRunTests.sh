#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/script/build_and_run.sh"

grep -F 'for process_id in $(pgrep -x "${APP_NAME}"); do' "${SCRIPT}" >/dev/null
grep -F 'running_binary="$(/bin/ps -p "${process_id}" -o comm=)"' "${SCRIPT}" >/dev/null
grep -F '[[ "${running_binary}" == "${APP_BINARY}" ]]' "${SCRIPT}" >/dev/null

echo "local development run tests passed"
