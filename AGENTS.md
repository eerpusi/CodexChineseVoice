# Development Rules

These rules require test-driven development for every behavior change and bug fix. Work in small
RED-GREEN-REFACTOR slices, keep verification focused during iteration, and expand validation at
integration or release checkpoints.

## Scope

- This is an independent open-source macOS project.
- Build a native macOS utility. Do not use Electron or a WebView-based desktop shell.
- The shortcut is active only while the Codex desktop app is frontmost.
- Holding `Command+R` records; releasing it finalizes transcription.
- Partial transcripts update the current Codex composer; final text replaces the active partial.
- The tool sends only after a successful final transcription when the user-controlled auto-send
  setting is enabled; the setting defaults to enabled.

## Security

- Never read, print, log, commit, or bundle real API keys.
- Read provider credentials from process environment initially.
- Use `ARK_PLAN_API_KEY` for the initial Volcengine Agent Plan integration.
- Keep fixed protocol constants in code, not as misleading user configuration.
- Do not modify the user's shell profile or persist credentials without explicit authorization at
  action time.

## Release Identity And Research Gate

- Keep the production bundle identifier stable across every version:
  `com.lianenguang.CodexChineseVoice`.
- A new distributable app must be freshly code signed and notarized. Bundle identity is not
  encryption and does not allow a new binary to reuse an old binary's signature.
- When replacing a local development app, remove the previous local `.app` before launching the
  fresh `dist/CodexChineseVoice.app`. Do not remove source files, user data, or historical GitHub
  release archives.
- Before implementation, build, signing, release, deletion, or another state-changing operation,
  query current Context7 documentation and record the conclusion in a design or research note.
  A prior query in the same Codex session may be reused for related work; query again when the
  framework, API, release concern, or other subject changes.
- The project `.codex/hooks.json` installs a `PreToolUse` gate for `apply_patch` and mutating Bash
  commands. Read-only inspection and Context7 queries remain available before the gate is satisfied.
- If Codex asks to trust the project hook, inspect the hook and approve it before making changes.

## Architecture

- Keep microphone capture, hotkey handling, ASR transport, transcript editing, and app lifecycle in
  separate modules.
- Define a provider protocol so additional ASR services can be added without changing input logic.
- The initial provider uses Volcengine Doubao streaming ASR 2.0 with incremental and final events.
- Restrict accessibility writes to the focused Codex composer and preserve unrelated text.
- Keep source files below 300 lines; split responsibilities before files approach 250 lines.

## Fast Delivery Workflow

- Git worktrees are prohibited. Work only in the primary repository checkout; do not create, enter,
  read from, write to, build in, test in, or run Git commands against any auxiliary worktree.
- If an auxiliary worktree already exists, report it and stop before interacting with it. Remove it
  only after receiving explicit user authorization and preserving any user-owned changes.
- Before editing, define the observable result, allowed scope, relevant acceptance check, and any
  condition that requires stopping for user input. A simple task may express this in one sentence.
- Load only the project rules, files, adjacent interfaces, examples, and failure output needed for
  the current result.
- Work in vertical slices. Each slice must produce one observable user result.
- Start each behavior-changing slice with the smallest automated test that expresses its acceptance
  condition. Run it and confirm that it fails for the expected reason before writing implementation
  code.
- Write only enough implementation to make the failing test pass. Refactor only after the relevant
  tests are green.
- Do not keep production behavior written before its test. Exploratory spikes must be explicitly
  disposable and reimplemented through tests before they become part of the product.
- For macOS permissions, microphone, accessibility, and other manual-only behavior, first isolate
  and test every deterministic boundary that can be automated, then wire the real system path and
  complete the required manual verification.
- Use a short design for multi-module, permission-sensitive, destructive, externally constrained,
  or protocol-heavy work before beginning its first RED step.
- Keep each change focused and reversible. Avoid speculative abstractions, unrelated refactors,
  and dependency additions that are not required for the slice.
- After each slice, run the narrowest relevant test and use its actual output to guide the next
  edit. Do not spend a long cycle on unrelated documentation or broad tests.
- Keep each working slice as a reviewable diff with its verification result. Create a Git commit
  only when explicitly requested or at an agreed integration checkpoint.
- After every behavior fix, terminate all existing `CodexChineseVoice` processes before manual
  verification. Build exactly one fresh app bundle at `dist/CodexChineseVoice.app` from the primary
  checkout and launch it by absolute path.
- Before claiming manual verification, confirm the running process executable resolves to the new
  `dist/CodexChineseVoice.app`, and verify its build timestamp or hash matches the fresh build.
  Never validate a fix against an older, diagnostic, cached, or differently located app bundle.
- If the same assumption or approach fails repeatedly, stop retrying it, inspect the evidence, and
  change the assumption, choose another approach, or report the blocker.
- Parallelize only tasks with separate files or interfaces, independent verification, and low merge
  cost. Do not let multiple agents edit the same file in the shared primary checkout.
- Long-running commands must remain observable and cancellable. There is no universal fixed timeout;
  use a budget appropriate to the command and do not restart a healthy process merely because it is
  slow.
- Stop the slice when its acceptance condition passes. Report remaining limitations instead of
  adding unrequested polish, abstractions, dependencies, documentation, refactors, or tests.

## Verification and Tests

- Use strict RED-GREEN-REFACTOR for all behavior-changing code:
  - RED: write one focused test, run it, and confirm the expected failure.
  - GREEN: implement the minimum behavior needed for that test to pass.
  - REFACTOR: improve structure without changing behavior while keeping the tests green.
- Bug fixes must begin with a reproducible failing regression test whenever the failure can be
  automated.
- Pure documentation, comments, formatting, generated artifacts, and configuration changes with no
  executable behavior do not require a new test. Existing relevant checks must still pass.
- A manual macOS workflow is additional evidence, not a substitute for automated coverage of its
  testable logic and boundaries.
- Prefer one targeted test or smoke check over an unrelated full-suite run during iteration. Run a
  broader suite at a release or integration checkpoint.
- Before release, maintain focused automated coverage for hotkey gating, audio framing, protocol
  parsing, partial replacement, finalization, cancellation, and missing configuration.
- A test passing is evidence for that behavior only; do not claim end-to-end usability without the
  required manual workflow verification.
- Run a real-provider test only when explicitly authorized and use synthetic, non-user audio.
- Verify the built app manually against Codex on a supported macOS version before claiming the
  workflow works end to end.

## Quality

- For multi-module or high-risk changes, record a short design and the major decision in repository
  documentation. Small, local changes do not require a separate design document.
- Keep acceptance criteria and known limitations visible in the task or change notes.
- Fix the root cause of failures, but do not broaden the change to unrelated cleanup.
