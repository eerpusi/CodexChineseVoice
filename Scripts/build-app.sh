#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT_NAME="CodexChineseVoice"
APP_NAME="${PRODUCT_NAME}.app"
OUTPUT_DIR="${ROOT_DIR}/.build/release-artifacts"
APP_DIR="${OUTPUT_DIR}/${APP_NAME}"
APP_BINARY="${APP_DIR}/Contents/MacOS/${PRODUCT_NAME}"
APP_ICON="${APP_DIR}/Contents/Resources/AppIcon.icns"
ZIP_PATH="${OUTPUT_DIR}/${PRODUCT_NAME}-macos.zip"
CHECKSUM_PATH="${OUTPUT_DIR}/${PRODUCT_NAME}-macos.sha256"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
UNSIGNED=0
CHECK_ONLY=0

for argument in "$@"; do
    case "$argument" in
        --unsigned) UNSIGNED=1 ;;
        --check-only) CHECK_ONLY=1 ;;
        *) echo "unknown argument: ${argument}" >&2; exit 2 ;;
    esac
done

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
    [[ -d "${APP_DIR}" ]] || { echo "missing app bundle: ${APP_DIR}" >&2; exit 1; }
    [[ -f "${ZIP_PATH}" ]] || { echo "missing archive: ${ZIP_PATH}" >&2; exit 1; }
    plutil -lint "${APP_DIR}/Contents/Info.plist" >/dev/null
    test "$(plutil -extract CFBundleIdentifier raw -o - "${APP_DIR}/Contents/Info.plist")" = "com.lianenguang.CodexChineseVoice"
    if [[ -n "${VERSION}" ]]; then
        test "$(plutil -extract CFBundleShortVersionString raw -o - "${APP_DIR}/Contents/Info.plist")" = "${VERSION}"
    fi
    if [[ -n "${BUILD_NUMBER}" ]]; then
        test "$(plutil -extract CFBundleVersion raw -o - "${APP_DIR}/Contents/Info.plist")" = "${BUILD_NUMBER}"
    fi
    test -x "${APP_BINARY}"
    [[ ! -e "${APP_DIR}/Contents/Helpers" ]] || {
        echo "app bundle must not contain CLI helpers" >&2
        exit 1
    }
    test -f "${APP_ICON}"
    test "$(plutil -extract CFBundleIconFile raw -o - "${APP_DIR}/Contents/Info.plist")" = "AppIcon"
    test "$(lipo -archs "${APP_BINARY}" | tr ' ' '\n' | sort | tr '\n' ' ')" = "arm64 x86_64 "
    codesign --verify --deep --strict "${APP_DIR}"
    shasum -a 256 -c "${CHECKSUM_PATH}"
    echo "release artifact checks passed"
    exit 0
fi

if [[ "${UNSIGNED}" -eq 0 && -z "${CODE_SIGN_IDENTITY:-}" ]]; then
    echo "set CODE_SIGN_IDENTITY or pass --unsigned for local validation" >&2
    exit 2
fi

if [[ "${UNSIGNED}" -eq 0 && -z "${VERSION}" ]]; then
    echo "VERSION is required for a signed release build" >&2
    exit 2
fi

if [[ "${UNSIGNED}" -eq 0 && -z "${BUILD_NUMBER}" ]]; then
    echo "BUILD_NUMBER is required for a signed release build" >&2
    exit 2
fi

if [[ -z "${VERSION}" ]]; then
    VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "${ROOT_DIR}/Packaging/Info.plist")"
fi

if [[ -z "${BUILD_NUMBER}" ]]; then
    BUILD_NUMBER="$(plutil -extract CFBundleVersion raw -o - "${ROOT_DIR}/Packaging/Info.plist")"
fi

[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "VERSION must be a semantic version such as 0.1.1" >&2
    exit 2
}

[[ "${BUILD_NUMBER}" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || {
    echo "BUILD_NUMBER must contain one to three dot-separated integers" >&2
    exit 2
}

mkdir -p "${OUTPUT_DIR}"
rm -rf "${APP_DIR}" "${ZIP_PATH}" "${CHECKSUM_PATH}"

swift build -c release --product "${PRODUCT_NAME}" --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --show-bin-path --arch arm64 --arch x86_64)"
BUILT_APP_BINARY="${BIN_DIR}/${PRODUCT_NAME}"
[[ -x "${BUILT_APP_BINARY}" ]] || { echo "missing built executable: ${BUILT_APP_BINARY}" >&2; exit 1; }

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BUILT_APP_BINARY}" "${APP_BINARY}"
cp "${ROOT_DIR}/Packaging/AppIcon.icns" "${APP_ICON}"
cp "${ROOT_DIR}/Packaging/Info.plist" "${APP_DIR}/Contents/Info.plist"
chmod 755 "${APP_BINARY}"
plutil -lint "${APP_DIR}/Contents/Info.plist" >/dev/null
plutil -replace CFBundleShortVersionString -string "${VERSION}" "${APP_DIR}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${BUILD_NUMBER}" "${APP_DIR}/Contents/Info.plist"

if [[ "${UNSIGNED}" -eq 1 ]]; then
    codesign --force --sign - "${APP_DIR}"
else
    codesign --force --options runtime --timestamp \
        --entitlements "${ROOT_DIR}/Packaging/CodexChineseVoice.entitlements" \
        --sign "${CODE_SIGN_IDENTITY}" "${APP_DIR}"
fi

codesign --verify --deep --strict "${APP_DIR}"
ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"
shasum -a 256 "${ZIP_PATH}" > "${CHECKSUM_PATH}"
echo "created ${ZIP_PATH}"
echo "created ${CHECKSUM_PATH}"
