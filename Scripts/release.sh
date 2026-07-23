#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---check-only}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "${MODE}" in
    --check-only)
        bash "${ROOT_DIR}/Tests/ReleaseArtifactTests.sh"
        bash "${ROOT_DIR}/Scripts/publish-release.sh" --check-only
        ;;
    --prepare|--publish)
        bash "${ROOT_DIR}/Scripts/build-app.sh"
        bash "${ROOT_DIR}/Scripts/notarize-release.sh"
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
