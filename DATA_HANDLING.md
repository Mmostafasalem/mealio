# Mealio data handling

Mealio requires no account. Existing local data is read in place; no Core Data
or SwiftData migration is introduced. iCloud shopping sync is optional and off
by default. No existing data is uploaded just by installing this version.

## Local data

The profile and BMR remain in the app's Keychain service. New Keychain writes
use WhenUnlockedThisDeviceOnly. The current food log, preferences and nutrition
plans remain in existing local stores. This change does not integrate HealthKit
or provide health-data transfer to another device. App-managed CloudKit sync
is distinct from the user's system backup configuration.

## Cloud eligibility

Only `lang`, `weeklyBudget`, `priceOverrides_v1`, shopping cart rows and grocery
rows are allowed. No profile, BMR, dietary restriction, food-intake or nutrition
plan payload may enter the cloud document. `SyncDataPolicy` enforces this on
incoming and outgoing documents; regression tests verify excluded fields.

## Storage and retry

`PrivateSyncService` persists a protected, backup-excluded journal in Application
Support. The journal contains shopping mutations, deletion markers, an opaque
device identifier and the bound CloudKit account record name, not an API key.
The transport uses the user's private custom CloudKit zone and an encrypted
payload field. It checks the encoded size before upload. Unavailable service,
conflicts, quota or provisioning failures leave local data available. Sync occurs
on foreground/launch, debounced local shopping edits and manual retry.

## Conflicts and deletion

Lists merge by item identity. Same-item edits use logical-counter/device-ID
ordering; concurrent quantities are not summed. Conditional CloudKit saves retry
conflicts up to four attempts. In-flight local edits are retained for another
pass. A reset changes generation: older device changes are discarded when that
device next reconnects. Erasure intent is persisted before local deletion, and
retry survives restarting the app or turning ordinary sync off.

Delete All Data clears the app's own preferences domain, Keychain records,
runtime cart/profile/log state and pending/delivered local notifications. Active
agent/manual meal-plan responses are invalidated. Cloud reset erases shopping
content while retaining an empty generation marker to reject old device state.
Health data on other devices is local and must be deleted on each device.

## Providers

AI requests continue to use the backend and Groq; Open Food Facts supplies
nutrition data. This implementation does not verify provider retention, live
backend auth, hosted privacy/support URLs or App Store privacy questionnaire.
These remain separate publication checks.

## Verification limits

The Swift package exercises production merge, privacy filtering, list codec and
local preferences erasure. Unsigned simulator builds verify compilation only.
Private CloudKit must still be activated/provisioned in the Apple Developer
account, its schema deployed to Production, and the live two-device scenarios in
`ICLOUD_SETUP.md` executed before release.
