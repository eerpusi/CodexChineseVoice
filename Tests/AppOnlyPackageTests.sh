#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_JSON="$(mktemp)"
trap 'rm -f "${MANIFEST_JSON}"' EXIT

cd "${ROOT_DIR}"
swift package dump-package > "${MANIFEST_JSON}"

test "$(plutil -extract products raw -o - "${MANIFEST_JSON}")" = "2"
test "$(plutil -extract products.0.name raw -o - "${MANIFEST_JSON}")" = "CodexChineseVoiceCore"
test "$(plutil -extract products.1.name raw -o - "${MANIFEST_JSON}")" = "CodexChineseVoice"
test "$(plutil -extract targets raw -o - "${MANIFEST_JSON}")" = "3"
test "$(plutil -extract targets.0.name raw -o - "${MANIFEST_JSON}")" = "CodexChineseVoiceCore"
test "$(plutil -extract targets.1.name raw -o - "${MANIFEST_JSON}")" = "CodexChineseVoiceApp"
test "$(plutil -extract targets.2.name raw -o - "${MANIFEST_JSON}")" = "CodexChineseVoiceCoreTests"
[[ ! -d "${ROOT_DIR}/Sources/CodexChineseVoiceCLI" ]] || {
    echo "CLI source target must be removed" >&2
    exit 1
}

CLI_ONLY_PATHS=(
    Sources/CodexChineseVoiceCore/Lifecycle/AgentProcessState.swift
    Sources/CodexChineseVoiceCore/Lifecycle/BackgroundProcessController.swift
    Sources/CodexChineseVoiceCore/Lifecycle/DetachedAgentProcessLauncher.swift
    Sources/CodexChineseVoiceCore/Lifecycle/LifecycleCommand.swift
    Sources/CodexChineseVoiceCore/Lifecycle/LifecycleCommandRouter.swift
    Sources/CodexChineseVoiceCore/Lifecycle/POSIXSpawnExecutor.swift
    Sources/CodexChineseVoiceCore/Lifecycle/SystemAgentProcessInspector.swift
    Sources/CodexChineseVoiceCore/Lifecycle/SystemAgentProcessSignaler.swift
)
for path in "${CLI_ONLY_PATHS[@]}"; do
    [[ ! -e "${ROOT_DIR}/${path}" ]] || {
        echo "CLI-only source must be removed: ${path}" >&2
        exit 1
    }
done

echo "app-only package tests passed"
