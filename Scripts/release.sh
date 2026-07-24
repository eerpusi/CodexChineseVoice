#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---check-only}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "VERSION must be a semantic version such as 0.1.1" >&2
    exit 2
}

case "${MODE}" in
    --check-only)
        EXPECTED_VERSION="${VERSION}" \
        EXPECTED_BUILD_NUMBER="${BUILD_NUMBER}" \
        bash "${ROOT_DIR}/Tests/ReleaseArtifactTests.sh"
        bash "${ROOT_DIR}/Scripts/publish-release.sh" --check-only
        ;;
    --prepare|--publish)
        bash "${ROOT_DIR}/Scripts/build-app.sh"
        bash "${ROOT_DIR}/Scripts/notarize-release.sh"
        EXPECTED_VERSION="${VERSION}" \
        EXPECTED_BUILD_NUMBER="${BUILD_NUMBER}" \
        bash "${ROOT_DIR}/Tests/ReleaseArtifactTests.sh"
        if [[ "${MODE}" == "--publish" ]]; then
            bash "${ROOT_DIR}/Scripts/publish-release.sh" --publish
        fi
        ;;
    *)
        echo "usage: $0 [--check-only|--prepare|--publish]" >&2
        exit 2
        ;;
esac
