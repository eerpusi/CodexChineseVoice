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

For the July 24 settings-window density adjustment, current SwiftUI documentation
states that settings windows derive their sizing from their content. The native
window controller therefore uses the hosted view's measured content size at a
fixed usable width, rather than reserving a guessed taller blank region.

The same settings change keeps credential storage action-based: a saved key is
represented only by a fixed mask, and an explicit Save command stores the
first or replacement value. Stored credential contents are never read back
into the UI.

For the July 24 status menu adjustment, current AppKit documentation confirms
that an `NSStatusItem` supports a native attached menu. The status icon uses
that menu for the three app-level commands, while the settings window contains
only durable settings.

For the July 24 ChatGPT composer compatibility fix, current Apple Accessibility
documentation confirms that accessibility clients read and write text attributes
through the target control's accessibility interface. The app therefore keeps
its existing `AXValue` and `AXSelectedTextRange` transaction model, and accepts
an empty cursor fallback only when the same target reports an authoritative
zero character count. It never fabricates a range for nonempty or ambiguous
content.

Apple's current distribution guidance confirms that each new macOS archive distributed outside the
App Store must be notarized, and that notarized distribution requires the Hardened Runtime. The
release pipeline therefore produces a new signed archive for `v0.1.2`; it does not reuse the
signature or notarization from `v0.1.1`.
