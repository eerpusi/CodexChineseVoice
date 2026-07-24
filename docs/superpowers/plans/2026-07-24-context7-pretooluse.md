# Context7-First Development And Stable App Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a tested project hook that gates state-changing work on Context7 research and document stable bundle identity plus local app cleanup rules.

**Architecture:** A small POSIX shell hook receives Codex's `PreToolUse` JSON on stdin, reads the referenced session transcript as JSONL, and emits an allow/deny JSON response. A prior Context7 query in that session can be reused for related turns; the hook blocks only when the session has no query. Project documentation defines stable bundle identity, per-build signing/notarization, local-only cleanup, and the research-first workflow.

**Tech Stack:** Codex `PreToolUse` command hook, JSONL transcript inspection with `/usr/bin/python3`, POSIX shell tests, Markdown project documentation.

---

### Task 1: Add the failing hook contract test

**Files:**
- Create: `Tests/Context7PreToolUseHookTests.sh`
- Create: `Scripts/context7-pretooluse-hook.sh` (empty executable placeholder only after RED)

- [ ] **Step 1: Write the failing test**

Create a shell test that creates temporary transcripts and feeds the hook these cases:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${ROOT_DIR}/Scripts/context7-pretooluse-hook.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

make_request() {
    local transcript="$1" tool_name="$2"
    printf '{"session_id":"s","turn_id":"t","transcript_path":"%s","cwd":"%s","hook_event_name":"PreToolUse","model":"test","permission_mode":"default","tool_name":"%s","tool_input":{"command":"printf test"},"tool_use_id":"u"}\n' \
        "$transcript" "$ROOT_DIR" "$tool_name"
}

assert_decision() {
    local expected="$1" input="$2" output
    output="$(printf '%s' "$input" | "$HOOK")"
    python3 -c 'import json,sys; expected,raw=sys.argv[1:]; data=json.loads(raw); assert data["permissionDecision"] == expected, data; assert data.get("block", False) == (expected == "deny"), data' "$expected" "$output"
}

WITH_CONTEXT7="${TEMP_DIR}/with.jsonl"
printf '%s\n' '{"tool_name":"mcp__context7__query_docs","tool_input":{"query":"macOS stable bundle identifier and signing"}}' > "$WITH_CONTEXT7"
assert_decision allow "$(make_request "$WITH_CONTEXT7" apply_patch)"

WITHOUT_CONTEXT7="${TEMP_DIR}/without.jsonl"
printf '%s\n' '{"tool_name":"rg","tool_input":{"pattern":"Bundle"}}' > "$WITHOUT_CONTEXT7"
assert_decision deny "$(make_request "$WITHOUT_CONTEXT7" apply_patch)"

assert_decision allow "$(make_request "$WITHOUT_CONTEXT7" rg)"

echo "Context7 PreToolUse hook tests passed"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash Tests/Context7PreToolUseHookTests.sh`

Expected: FAIL because `Scripts/context7-pretooluse-hook.sh` does not exist.

### Task 2: Implement the minimum transcript-aware hook

**Files:**
- Create: `Scripts/context7-pretooluse-hook.sh`
- Modify: `Tests/Context7PreToolUseHookTests.sh`

- [ ] **Step 1: Implement protected-tool matching and transcript lookup**

The script must:

1. Parse stdin as JSON using `/usr/bin/python3`.
2. Read `tool_name` and `transcript_path`.
3. Treat `apply_patch` as protected. Treat `Bash` as protected unless its command is an explicitly
   read-only inspection command such as `pwd`, `rg`, `sed`, `cat`, `find`, `git status`, `git diff`,
   `git log`, `stat`, or `file`.
4. For protected calls, fail closed if the transcript is missing or unreadable.
5. Search the full session transcript JSONL for a tool name containing `context7` and `query_docs`;
   do not require the query to have the current turn ID so related work can reuse it.
6. Print `{"permissionDecision":"allow"}` when evidence exists.
7. Print `{"permissionDecision":"deny","block":true,"reason":"..."}` otherwise and exit 2.

Use a single Python subprocess with no API keys, credentials, or transcript contents printed in
the response. Keep the reason short and actionable.

- [ ] **Step 2: Add edge-case tests**

Extend the test with an unreadable/missing transcript (deny), a Context7 result line after a
non-query tool line (allow), a prior-turn Context7 query (allow), a read-only `rg` Bash command
(allow even without a transcript), and a state-changing `swift build` Bash command (deny without a
transcript).

- [ ] **Step 3: Run the focused test**

Run: `bash Tests/Context7PreToolUseHookTests.sh`

Expected: `Context7 PreToolUse hook tests passed`.

### Task 3: Register the project hook

**Files:**
- Create: `.codex/hooks.json`
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Add the project hook configuration**

Use the current Codex format:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^(Bash|apply_patch)$",
        "hooks": [
          {
            "type": "command",
            "command": "bash Scripts/context7-pretooluse-hook.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Document trust and scope**

Explain that Codex may require explicit trust before running a project hook, that the hook gates
state-changing calls rather than read-only inspection, and that Context7 results must be captured
in design/research notes.

- [ ] **Step 3: Run JSON and shell checks**

Run: `python3 -m json.tool .codex/hooks.json >/dev/null` and
`bash Tests/Context7PreToolUseHookTests.sh`.

Expected: both commands exit 0.

### Task 4: Document release identity and local cleanup

**Files:**
- Modify: `docs/release.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Add the stable identity rule**

State that `com.lianenguang.CodexChineseVoice` is stable across versions, while version/build
numbers change per release.

- [ ] **Step 2: Add signing/notarization language**

State that every new distributable app is signed and notarized; this is signing/trust, not
encryption, and historical release archives are not rebuilt.

- [ ] **Step 3: Add local cleanup language**

State that development replacement removes only the prior local app bundle before launching the
fresh `dist/CodexChineseVoice.app`; it must not remove source, GitHub releases, or user data.

### Task 5: Verify the integrated change

**Files:**
- Test: `Tests/Context7PreToolUseHookTests.sh`
- Test: `Tests/AppOnlyPackageTests.sh`
- Test: `Tests/ReleaseArtifactTests.sh`

- [ ] **Step 1: Run focused hook checks**

Run: `bash Tests/Context7PreToolUseHookTests.sh`.

- [ ] **Step 2: Run existing app/release checks**

Run: `bash Tests/AppOnlyPackageTests.sh` and `bash Tests/ReleaseArtifactTests.sh`.

- [ ] **Step 3: Review the diff**

Run: `git diff --check` and `git status --short`.

Confirm no API keys, transcript contents, or unrelated files were added.
