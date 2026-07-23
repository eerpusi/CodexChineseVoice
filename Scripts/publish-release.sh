#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---check-only}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
HOMEBREW_TAP_REPOSITORY="${HOMEBREW_TAP_REPOSITORY:-}"
ARCHIVE_PATH="${ARCHIVE_PATH:-${ROOT_DIR}/.build/release-artifacts/CodexChineseVoice-macos.zip}"
CHECKSUM_PATH="${CHECKSUM_PATH:-${ROOT_DIR}/.build/release-artifacts/CodexChineseVoice-macos.sha256}"

[[ "${MODE}" == "--check-only" || "${MODE}" == "--publish" ]] || {
    echo "usage: $0 [--check-only|--publish]" >&2
    exit 2
}
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "VERSION must be a semantic version such as 0.1.0" >&2
    exit 2
}
[[ "${GITHUB_REPOSITORY}" =~ ^[^/]+/[^/]+$ ]] || {
    echo "GITHUB_REPOSITORY must use owner/repository format" >&2
    exit 2
}
[[ "${HOMEBREW_TAP_REPOSITORY}" =~ ^[^/]+/homebrew-[^/]+$ ]] || {
    echo "HOMEBREW_TAP_REPOSITORY must use owner/homebrew-tap format" >&2
    exit 2
}
[[ -f "${ARCHIVE_PATH}" ]] || { echo "missing archive: ${ARCHIVE_PATH}" >&2; exit 1; }
[[ -f "${CHECKSUM_PATH}" ]] || { echo "missing checksum: ${CHECKSUM_PATH}" >&2; exit 1; }
shasum -a 256 -c "${CHECKSUM_PATH}"

if [[ "${MODE}" == "--check-only" ]]; then
    echo "release inputs valid"
    exit 0
fi

gh auth status
TAG="v${VERSION}"
if gh release view "${TAG}" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
    gh release upload "${TAG}" "${ARCHIVE_PATH}" "${CHECKSUM_PATH}" \
        --repo "${GITHUB_REPOSITORY}" \
        --clobber
else
    gh release create "${TAG}" "${ARCHIVE_PATH}" "${CHECKSUM_PATH}" \
        --repo "${GITHUB_REPOSITORY}" \
        --title "CodexChineseVoice ${VERSION}" \
        --generate-notes
fi

TAP_PARENT="$(mktemp -d)"
trap 'rm -rf "${TAP_PARENT}"' EXIT
TAP_DIR="${TAP_PARENT}/homebrew-tap"
if ! gh repo view "${HOMEBREW_TAP_REPOSITORY}" >/dev/null 2>&1; then
    gh repo create "${HOMEBREW_TAP_REPOSITORY}" \
        --public \
        --description "Homebrew tap for CodexChineseVoice"
fi
gh repo clone "${HOMEBREW_TAP_REPOSITORY}" "${TAP_DIR}"

RELEASE_OWNER="${GITHUB_REPOSITORY%%/*}"
RELEASE_REPOSITORY="${GITHUB_REPOSITORY#*/}"
CASK_PATH="${TAP_DIR}/Casks/codex-chinese-voice.rb"
GITHUB_OWNER="${RELEASE_OWNER}" \
GITHUB_REPOSITORY="${RELEASE_REPOSITORY}" \
VERSION="${VERSION}" \
ARCHIVE="${ARCHIVE_PATH}" \
OUTPUT="${CASK_PATH}" \
bash "${ROOT_DIR}/Scripts/generate-homebrew-cask.sh"

git -C "${TAP_DIR}" add Casks/codex-chinese-voice.rb
if ! git -C "${TAP_DIR}" diff --cached --quiet; then
    git -C "${TAP_DIR}" \
        -c user.name="CodexChineseVoice Release" \
        -c user.email="release@users.noreply.github.com" \
        commit -m "chore: update CodexChineseVoice to ${VERSION}"
    git -C "${TAP_DIR}" push -u origin HEAD
fi

echo "published ${GITHUB_REPOSITORY}@${TAG}"
echo "updated ${HOMEBREW_TAP_REPOSITORY}"
