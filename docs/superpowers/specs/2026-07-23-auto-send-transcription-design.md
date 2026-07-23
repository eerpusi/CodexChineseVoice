# Automatic Transcript Submission Design

Date: 2026-07-23

## Goal

Add a user-configurable option that submits the active Codex composer after a successful voice
transcription. The option is enabled by default. This requirement supersedes the earlier product
rule that the utility must never send messages automatically.

## User Experience

- Settings contains a toggle named `转写完成后自动发送`.
- The toggle is enabled when no preference has been saved yet.
- Changing the toggle takes effect for the next completed recording without restarting the app.
- When enabled, releasing `Command+R` eventually writes the final transcript and sends the complete
  composer contents, including valid text that existed before recording.
- When disabled, the final transcript remains in the composer and is not sent.
- Existing placeholder normalization remains unchanged, so placeholder text such as
  `Work with ChatGPT` is never treated as message content.

## Architecture

### Preference

`AppPresentationPreferences` owns an `autoSendsTranscription` Boolean and its UserDefaults key.
Loading an absent value returns `true`; saving and the SwiftUI `@AppStorage` binding use the same
key. `VoiceApplicationModel` supplies the coordinator with a closure that reads the current
preference when a session completes, so settings changes do not require a runtime restart.

### Session Completion

`VoiceInputCoordinator` keeps partial and final provider events inside the current session. It only
completes the composer after both conditions are true:

1. The user has released `Command+R`.
2. The provider stream has finished.

The coordinator completes a non-empty session exactly once and passes the current auto-send
preference to the composer. Empty, cancelled, failed, stale, or superseded sessions never request
submission.

### Composer Transaction

`VoiceInputComposer` exposes one completion operation that receives the final text and whether it
should submit. `CodexComposerEditor` performs these steps:

1. Confirm Codex is still frontmost and the captured process is unchanged.
2. Confirm the captured composer is still focused and its owned text range is still valid.
3. Replace the owned partial range with the final transcript while preserving unrelated text.
4. Clear the composition transaction so a later failure cannot roll back submitted content.
5. If submission is enabled, revalidate the captured composer and post an unmodified Return key
   event to Codex.

The Return event mirrors the user's normal Codex send action. It is emitted only from the validated
composer transaction, never as an independent global action.

## Failure Handling

- A final text write failure cancels the transaction and reports the existing composer error.
- If Return event creation or posting cannot be initiated, the final text remains in the composer
  and the app reports that automatic sending failed.
- Losing focus, switching applications, changing the captured text inside the owned range, an empty
  result, provider cancellation, or provider failure prevents submission.
- Partial transcripts never trigger submission.

## Testing

Focused automated coverage will verify:

- Auto-send defaults to enabled and both preference values persist.
- Enabled sessions complete and request one submission.
- Disabled sessions complete without requesting submission.
- A provider final received before key release does not submit early.
- Empty, cancelled, failed, stale, and focus-invalid sessions do not submit.
- Composer completion preserves existing text and invokes the Return event only after a successful
  final write.
- Submission failure leaves final text intact and surfaces an error.

The full Swift test suite and release tooling tests run after the focused tests. Manual validation
uses the final signed app against Codex and confirms the enabled and disabled settings, preservation
of existing text, placeholder exclusion, one submission per recording, and no submission on
failure or cancellation.

## Acceptance Criteria

- A fresh installation automatically sends a successful non-empty transcription once.
- Turning the setting off leaves the final message in the composer.
- Existing valid composer text is included in the sent message; placeholder text is excluded.
- No unsafe path can send a partial, empty, cancelled, failed, stale, or unfocused composition.
- The final signed and notarized build passes the real Codex workflow before publication.
