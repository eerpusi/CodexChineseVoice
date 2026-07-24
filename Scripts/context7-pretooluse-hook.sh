#!/usr/bin/env bash
set -euo pipefail

INPUT_FILE="$(mktemp -t codex-context7-hook.XXXXXX)"
trap 'rm -f "${INPUT_FILE}"' EXIT
cat > "${INPUT_FILE}"

INPUT_FILE="${INPUT_FILE}" /usr/bin/python3 <<'PY'
import json
import os
import re
import sys


def response(decision, reason=None):
    payload = {"permissionDecision": decision}
    if decision == "deny":
        payload["block"] = True
        payload["hookSpecificOutput"] = {
            "reason": reason or "Context7 research is required before this operation."
        }
    print(json.dumps(payload, ensure_ascii=True))


def read_only_bash(command):
    if not isinstance(command, str) or not command.strip():
        return False
    if re.search(r"[;&|<>`$()]", command):
        return False
    return bool(re.match(
        r"^\s*(pwd|rg|sed|cat|find|stat|file|which|type|command\s+-v|"
        r"git\s+(status|diff|log|show|branch|rev-parse)|"
        r"plutil\s+-lint|codesign\s+--verify|spctl\s+--assess|"
        r"swift\s+--version|xcrun\s+--version)\b",
        command,
    ))


def protected_tool(data):
    tool_name = data.get("tool_name")
    if tool_name == "apply_patch":
        return True
    if tool_name != "Bash":
        return False
    tool_input = data.get("tool_input")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    return not read_only_bash(command)


def contains_context7_query(value):
    if isinstance(value, dict):
        for key in ("tool_name", "name", "recipient"):
            candidate = value.get(key)
            if isinstance(candidate, str):
                normalized = candidate.lower()
                if "context7" in normalized and "query_docs" in normalized:
                    return True
        return any(contains_context7_query(item) for item in value.values())
    if isinstance(value, list):
        return any(contains_context7_query(item) for item in value)
    return False


def transcript_has_context7(path):
    if not isinstance(path, str) or not path or not os.path.isfile(path):
        return False
    try:
        with open(path, "r", encoding="utf-8") as transcript:
            for line in transcript:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if contains_context7_query(event):
                    return True
    except (OSError, UnicodeError):
        return False
    return False


try:
    with open(os.environ["INPUT_FILE"], "r", encoding="utf-8") as request_file:
        request = json.load(request_file)
except (KeyError, OSError, UnicodeError, json.JSONDecodeError):
    response("deny", "The PreToolUse request could not be read; Context7 research is required.")
    sys.exit(2)

if not protected_tool(request):
    response("allow")
    sys.exit(0)

if transcript_has_context7(request.get("transcript_path")):
    response("allow")
    sys.exit(0)

response("deny", "Run a relevant Context7 query in this Codex session before this operation.")
sys.exit(2)
PY
