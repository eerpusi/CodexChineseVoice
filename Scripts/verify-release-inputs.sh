#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_INPUTS=(Package.swift Sources Packaging Scripts)

fail() {
    echo "release inputs must be committed before building: $*" >&2
    exit 1
}

git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null || fail "not a Git checkout"

if ! git -C "${ROOT_DIR}" diff --quiet -- "${RELEASE_INPUTS[@]}"; then
    fail "unstaged changes detected"
fi

if ! git -C "${ROOT_DIR}" diff --cached --quiet -- "${RELEASE_INPUTS[@]}"; then
    fail "staged changes detected"
fi

untracked="$(git -C "${ROOT_DIR}" ls-files --others --exclude-standard -- "${RELEASE_INPUTS[@]}")"
if [[ -n "${untracked}" ]]; then
    fail "untracked files detected: ${untracked//$'\n'/, }"
fi

ignored="$(git -C "${ROOT_DIR}" ls-files --others --ignored --exclude-standard -- "${RELEASE_INPUTS[@]}")"
if [[ -n "${ignored}" ]]; then
    fail "ignored files detected: ${ignored//$'\n'/, }"
fi

echo "release inputs are committed"
