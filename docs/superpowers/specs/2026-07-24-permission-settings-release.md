# Permission Settings Release

## Goal

Ship `v0.1.2` so every missing permission state in the menu bar offers a direct System Settings
action: Microphone, Accessibility, or Input Monitoring.

## Scope

- Keep permission pane URLs in `SystemPermissionProvider`.
- Map each missing `VoiceApplicationState` to one message, button label, and settings URL.
- Render that presentation in the menu bar without changing the existing retry flow.
- Exclude unrelated configuration precedence and local-development bundle workflow changes.

## Verification

- Deterministic tests cover the three URLs and all four presentation states.
- A local host check must show the corresponding action for a missing permission before release.
- The distributable archive is rebuilt, Developer ID signed with Hardened Runtime, notarized, and
  stapled before the GitHub Release and Homebrew Cask are updated.

## Context7 Evidence

Apple's current distribution guidance confirms that each new macOS archive distributed outside the
App Store must be notarized, and that notarized distribution requires the Hardened Runtime. The
release pipeline therefore produces a new signed archive for `v0.1.2`; it does not reuse the
signature or notarization from `v0.1.1`.
