# Keychain Credential Design

## Goal

Replace plaintext API-key persistence with macOS Keychain storage while preserving explicit
per-process configuration and safely migrating existing users.

## Credential Resolution

The resolver uses this order:

1. A nonempty `ARK_PLAN_API_KEY` environment variable for the current process.
2. The application's Keychain generic-password item.
3. A legacy `~/.config/codex-chinese-voice/config.toml` value, migrated once.

The environment is an explicit, nonpersistent runtime override for development and automation.
The Keychain item is the normal user-facing application setting.

## Keychain Item

`KeychainCredentialStore` uses Security.framework generic-password APIs with a fixed service and
account owned by `com.lianenguang.CodexChineseVoice`. It supports load, upsert, and delete.
`errSecItemNotFound` means no saved key; every other OSStatus becomes a typed credential error.
The value is stored as `kSecValueData`; the query matches the fixed service/account attributes.

## Legacy Migration

Only when neither an environment override nor a Keychain key is available, the resolver reads the
legacy TOML key. It writes that key to Keychain and deletes the legacy plaintext file only after a
successful Keychain write. A failed Keychain write leaves the legacy file untouched and surfaces an
actionable error. New installs never create the TOML file.

## Settings And Errors

The settings page saves directly to Keychain and provides a clear-saved-key action. Clearing a
missing key succeeds. The UI never displays the secret; its configured state remains masked.

## Verification

Deterministic tests cover environment override, Keychain read/upsert/delete, missing-item handling,
legacy migration success, and migration failure without legacy deletion. Existing packaging checks
continue to assert that no configuration file or credential is bundled. The release includes the
three permission-settings actions and this credential migration in `v0.1.2`.

## Context7 Evidence

Context7's current Apple Security sources show generic-password items identified by service and
account attributes. Updates match those attributes and set `kSecValueData`, while the value data is
not a matching predicate. The implementation therefore issues an attribute-only query for lookup,
update, and delete, and treats an absent item separately from all other Keychain failures.
