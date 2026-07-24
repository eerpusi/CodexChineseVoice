#!/usr/bin/env bash
set -euo pipefail

OWNER="${GITHUB_OWNER:-}"
REPOSITORY="${GITHUB_REPOSITORY:-}"
VERSION="${VERSION:-0.1.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${ARCHIVE:-${ROOT_DIR}/.build/release-artifacts/CodexChineseVoice-macos.zip}"
OUTPUT="${OUTPUT:-${ROOT_DIR}/Packaging/Homebrew/Casks/codex-chinese-voice.rb}"

[[ -n "${OWNER}" ]] || { echo "GITHUB_OWNER is required" >&2; exit 2; }
[[ -n "${REPOSITORY}" ]] || { echo "GITHUB_REPOSITORY is required" >&2; exit 2; }
[[ -f "${ARCHIVE}" ]] || { echo "missing archive: ${ARCHIVE}" >&2; exit 1; }

SHA256="$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}')"
mkdir -p "$(dirname "${OUTPUT}")"

{
    printf 'cask "codex-chinese-voice" do\n'
    printf '  version "%s"\n' "${VERSION}"
    printf '  sha256 "%s"\n' "${SHA256}"
    printf '  url "https://github.com/%s/%s/releases/download/v#{version}/CodexChineseVoice-macos.zip"\n' "${OWNER}" "${REPOSITORY}"
    printf '  name "CodexChineseVoice"\n'
    printf '  desc "Chinese voice input for the Codex macOS app"\n'
    printf '  homepage "https://github.com/%s/%s"\n' "${OWNER}" "${REPOSITORY}"
    printf '  app "CodexChineseVoice.app"\n'
    printf 'end\n'
} > "${OUTPUT}"

echo "created ${OUTPUT}"
