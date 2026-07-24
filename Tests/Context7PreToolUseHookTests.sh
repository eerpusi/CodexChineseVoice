#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${ROOT_DIR}/Scripts/context7-pretooluse-hook.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

make_request() {
    local transcript="$1" tool_name="$2" command="${3:-printf test}"
    printf '{"session_id":"s","turn_id":"t","transcript_path":"%s","cwd":"%s","hook_event_name":"PreToolUse","model":"test","permission_mode":"default","tool_name":"%s","tool_input":{"command":"%s"},"tool_use_id":"u"}\n' \
        "$transcript" "$ROOT_DIR" "$tool_name" "$command"
}

assert_decision() {
    local expected="$1" input="$2" output
    output="$(printf '%s' "$input" | "$HOOK" 2>/dev/null || true)"
    python3 -c 'import json,sys; expected,raw=sys.argv[1:]; data=json.loads(raw); assert data["permissionDecision"] == expected, data; assert data.get("block", False) == (expected == "deny"), data' "$expected" "$output"
}

WITH_CONTEXT7="${TEMP_DIR}/with.jsonl"
printf '%s\n' '{"tool_name":"mcp__context7__query_docs","tool_input":{"query":"macOS stable bundle identifier and signing"}}' > "$WITH_CONTEXT7"
assert_decision allow "$(make_request "$WITH_CONTEXT7" apply_patch)"

CONTEXT7_AFTER_READ="${TEMP_DIR}/context7-after-read.jsonl"
printf '%s\n' '{"tool_name":"rg","tool_input":{"pattern":"Bundle"}}' '{"tool_name":"mcp__context7__query_docs","tool_input":{"query":"Codex PreToolUse hooks"}}' > "$CONTEXT7_AFTER_READ"
assert_decision allow "$(make_request "$CONTEXT7_AFTER_READ" apply_patch)"

WRONG_TURN="${TEMP_DIR}/wrong-turn.jsonl"
printf '%s\n' '{"turn_id":"other-turn","tool_name":"mcp__context7__query_docs","tool_input":{"query":"unrelated"}}' > "$WRONG_TURN"
assert_decision allow "$(make_request "$WRONG_TURN" apply_patch)"

WITHOUT_CONTEXT7="${TEMP_DIR}/without.jsonl"
printf '%s\n' '{"tool_name":"rg","tool_input":{"pattern":"Bundle"}}' > "$WITHOUT_CONTEXT7"
assert_decision deny "$(make_request "$WITHOUT_CONTEXT7" apply_patch)"
assert_decision deny "$(make_request "$WITHOUT_CONTEXT7" Bash 'swift build -c release')"
assert_decision allow "$(make_request "$WITHOUT_CONTEXT7" Bash 'rg --files')"

assert_decision deny "$(make_request "${TEMP_DIR}/missing.jsonl" apply_patch)"
assert_decision allow "$(make_request "$WITHOUT_CONTEXT7" mcp__context7__query_docs)"

echo "Context7 PreToolUse hook tests passed"
