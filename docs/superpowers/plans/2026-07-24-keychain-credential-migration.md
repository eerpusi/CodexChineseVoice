# Keychain Credential Migration Implementation Plan

> **Execution constraint:** Work only in the primary checkout. Do not create or use auxiliary worktrees. Before a release build, every source and packaging input must match the committed release state.

**Goal:** Replace plaintext API-key persistence with macOS Keychain, safely migrate legacy TOML credentials, and keep `ARK_PLAN_API_KEY` as a one-process override.

**Architecture:** `CredentialStoring` will be the small shared boundary. `KeychainCredentialStore` owns Security.framework calls; `ConfigFileStore` is legacy-only. The resolver checks environment, Keychain, then migrates TOML only after a successful Keychain write.

**Tech Stack:** Swift 6, Security.framework, Foundation, SwiftUI, XCTest.

---

### Task 1: Credential resolver boundary

**Files:**
- Modify: `Sources/CodexChineseVoiceCore/Configuration/AppConfiguration.swift`
- Modify: `Tests/CodexChineseVoiceCoreTests/ConfigurationTests.swift`

- [ ] Add failing tests for environment-over-Keychain-over-legacy resolution and no credential.
- [ ] Run `swift test --filter ConfigurationTests` and confirm failure from missing Keychain/legacy resolver inputs.
- [ ] Add this boundary and resolver behavior:

```swift
public protocol CredentialStoring: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey() throws
}

if let key = environment["ARK_PLAN_API_KEY"], !key.isEmpty {
    return AppConfiguration(apiKey: key)
}
if let key = try keychain.loadAPIKey(), !key.isEmpty {
    return AppConfiguration(apiKey: key)
}
return try migrateLegacyKey()
```

- [ ] Re-run `swift test --filter ConfigurationTests` and confirm green.

### Task 2: Keychain adapter

**Files:**
- Create: `Sources/CodexChineseVoiceCore/Configuration/KeychainCredentialStore.swift`
- Create: `Tests/CodexChineseVoiceCoreTests/KeychainCredentialStoreTests.swift`

- [ ] Add failing fake-Security-client tests for missing item, add, duplicate-item update, delete, and non-missing OSStatus failure.
- [ ] Run `swift test --filter KeychainCredentialStoreTests` and confirm missing adapter failure.
- [ ] Implement fixed generic-password matching with service/account, `SecItemCopyMatching`, `SecItemAdd`, `SecItemUpdate`, and `SecItemDelete`. Treat only `errSecItemNotFound` as absence.
- [ ] Re-run `swift test --filter KeychainCredentialStoreTests` and confirm green without touching the user's Keychain.

### Task 3: Lossless legacy migration

**Files:**
- Modify: `Sources/CodexChineseVoiceCore/Configuration/SecureFileAccess.swift`
- Modify: `Sources/CodexChineseVoiceCore/Configuration/ConfigFileStore.swift`
- Modify: `Sources/CodexChineseVoiceCore/Configuration/AppConfiguration.swift`
- Modify: `Tests/CodexChineseVoiceCoreTests/ConfigurationTests.swift`

- [ ] Add failing tests that a TOML key is saved to Keychain before deletion, and that a Keychain write failure leaves the TOML file intact.
- [ ] Run `swift test --filter ConfigurationTests/testLegacyKeyMigratesThenDeletesLegacyStorage` and confirm red.
- [ ] Add a no-follow `SecureFileAccess.remove(at:)`, `ConfigFileStore.deleteAPIKey()`, and migration in this exact order:

```swift
guard let key = try legacy.loadAPIKey(), !key.isEmpty else {
    throw ConfigurationError.missingAPIKey
}
try keychain.saveAPIKey(key)
try legacy.deleteAPIKey()
return AppConfiguration(apiKey: key)
```

- [ ] Re-run `swift test --filter ConfigurationTests` and `swift test --filter ConfigurationSecurityTests`; both must pass.

### Task 4: Settings integration

**Files:**
- Modify: `Sources/CodexChineseVoiceApp/Models/VoiceApplicationModel.swift`
- Modify: `Sources/CodexChineseVoiceApp/Views/AppSettingsView.swift`
- Modify: `Tests/CodexChineseVoiceCoreTests/ConfigurationTests.swift`

- [ ] Reuse the resolver deletion coverage from Task 1 to verify that an absent Keychain key leaves `ARK_PLAN_API_KEY` usable.
- [ ] Change settings save to `KeychainCredentialStore.default.saveAPIKey`, add `clearSavedAPIKey()`, and use Keychain plus legacy TOML in the runtime resolver.
- [ ] Change the masked label to “已配置”; add a “清除已保存的 Key” button and a non-secret failure message.
- [ ] Re-run `swift test --filter ConfigurationTests` and `swift build --product CodexChineseVoice`; both must pass, then verify the clear button in the host app without displaying a key.

### Task 5: Release verification

**Files:**
- Modify: `README.md`
- Modify: `docs/acceptance.md`

- [ ] Document Keychain storage, environment override, and successful-only legacy deletion.
- [ ] Run the full Swift suite and existing release-tool tests.
- [ ] Build and run the fresh development app, save and clear a synthetic Keychain key manually without displaying it.
- [ ] Commit only Keychain, credential UI, tests, and docs; push main; sign, notarize, publish `v0.1.2`, and verify its GitHub assets and Homebrew Cask.
