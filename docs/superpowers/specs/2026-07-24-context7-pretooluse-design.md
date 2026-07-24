# Context7-First Development And Stable App Identity

## Goal

Make the project's macOS release identity stable and make implementation-affecting Codex tool
calls require current Context7 research before they run.

## Confirmed Requirements

- Keep one production bundle identifier across all versions:
  `com.lianenguang.CodexChineseVoice`.
- A new app binary is signed and notarized for each release. A stable bundle identifier does not
  reuse a previous binary's signature and is not encryption.
- When replacing a local development app, remove the previous local `.app` before launching the
  new one so LaunchServices cannot select a stale duplicate.
- Preserve historical GitHub release archives. Local cleanup must not delete published artifacts.
- Keep the product as a native menu bar app with no CLI executable.
- Before implementation, build, signing, release, deletion, or other state-changing operations,
  perform a current Context7 documentation query and record the relevant result in the design or
  research notes.

## Hook Design

The project adds a project-scoped Codex `PreToolUse` hook. The hook is intentionally limited to
state-changing `Bash` and `apply_patch` calls. Read-only inspection and Context7 queries remain
available so the agent can gather context before making changes.

The hook reads the JSON request supplied by Codex, including `transcript_path`, `tool_name`, and
`tool_input`. It allows a state-changing call when the session transcript contains a prior
Context7 query, so research can be reused across related turns. When the transcript is missing,
unreadable, or has no Context7 query at all, the hook returns a blocking decision with an actionable
reason. It fails closed for the protected tools.

This is a session-level reuse decision rather than a semantic relevance proof. If the subject
changes to a different framework, API, or release concern, the maintainer should run a new Context7
query even though the gate can reuse an earlier one.

The hook does not attempt to judge the quality of the query. The project workflow requires the
query's conclusion to be recorded in the design or research note, and code review remains the
final quality check.

## Release Identity And Cleanup

`Packaging/Info.plist` remains the single source of the production bundle identifier. Release
version and build numbers are independent of the bundle identifier. Release scripts sign and
notarize the newly generated archive only. Local build workflows clean the prior local app bundle
before copying the fresh bundle to `dist/CodexChineseVoice.app`.

## Testing

- Unit-style shell tests feed representative PreToolUse JSON to the hook.
- Tests cover: Context7 present (allow), Context7 absent (block), unreadable transcript (block),
  read-only tool (allow), and protected tool matching.
- Release checks continue to assert the stable bundle identifier, app-only bundle, universal
  architectures, signing, notarization inputs, and absence of CLI helpers.

## Context7 Evidence

The design was checked against current Context7 documentation for OpenAI Codex CLI and Apple
Developer distribution guidance. Codex documents `PreToolUse` command hooks with `transcript_path`,
`tool_name`, and `tool_input`; a blocking response uses `permissionDecision: "deny"` with `block:
true`. See the [Codex hook runtime](https://github.com/openai/codex/blob/main/codex-rs/core/src/hook_runtime.rs)
and [hook schema](https://github.com/openai/codex/blob/main/codex/codex-rs/hooks/src/schema.rs).
Apple guidance treats the bundle identifier as the app identity while requiring each distributable
build to be signed and macOS software to be notarized; see [Preparing Your App for
Distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution).

## 2026-07-24 Local Run Workflow Evidence

Context7's current Swift Package Manager documentation confirms that `swift build --show-bin-path`
prints the build-products directory and may be used with the same relevant build arguments. The
local run script therefore builds the named product first, obtains its binary from that directory,
and stages exactly one development app at `dist/CodexChineseVoice Dev.app`. Its `--verify` mode also compares the
running process executable path to the binary inside that fresh bundle, rather than accepting any
same-named process.

Context7's current Apple Developer guidance describes `CFBundleIdentifier` as the system-wide app
identifier. The local run script therefore stages a development-only app with a separate bundle
identifier and executable name, while the source `Packaging/Info.plist` continues to define the
unchanged production identifier for signed and notarized releases. This permits local and
production installs to coexist without process or LaunchServices collisions.
