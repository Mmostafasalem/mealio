# Private iCloud Sync Implementation Plan

**Goal:** No Mealio login; offline local storage with optional private iCloud sync and propagated deletion.

**Architecture:** A Foundation-only merge model tracks item mutations and tombstones. A private CloudKit record uses conditional saves to merge concurrent changes. An explicit reset changes the generation; clients discard edits from older generations. Local state and pending resets persist in a protected file. Existing stores remain in place.

**Constraints:** iOS 17+, Apple frameworks only, no persistence-key renames, no Core Data/SwiftData migration, no secrets in source, no automatic upload before consent. CloudKit activation and production provisioning must be independently verified.

**Policy correction:** App Review 5.1.3(ii) prohibits personal health information in iCloud. Only shopping cart, shopping list, budget, price corrections and language sync. Profile, BMR, food log, dietary restrictions and nutrition plans remain local. This supersedes the original all-data sync proposal.

**Review focus:** Offline deletion must not resurrect data; account changes must not upload another account's data; failed sync must retain changes; concurrent list additions must survive; UI must reload after remote data.

1. Write and run merge regression tests (first failing, then passing): concurrent additions, deletion, generation reset, deterministic conflict resolution, Codable restoration.
2. Implement protected local journal, storage adapter, private CloudKit transport, explicit enable/disable, retry on foreground, account binding, bounded payload and errors. Test adapter extraction/reassembly with real fixtures.
3. Wire launch/foreground sync, Keychain/local change notifications, Profile controls, deletion reset and runtime reload. Invalidate stale async requests.
4. Add iCloud entitlements and optional tracked build configuration; update privacy and activation documentation.
5. Run Swift package tests, backend suite and simulator Debug/Release builds. Review the diff. Record actual Apple provisioning/device verification limits.
