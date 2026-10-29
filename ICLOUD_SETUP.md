# Mealio private shopping sync

## Implemented scope

No Mealio account. Local storage works offline. Shopping sync is off by default
and can be enabled in Profile → Data & iCloud. Only cart/list items, budget,
price corrections and language are eligible. App Review 5.1.3(ii) prohibits
personal health information in iCloud: profile, BMR, food intake, diets/allergies
and nutrition plans are excluded by the production payload allowlist.

The private `MealioPrivate` zone contains one `MealioPersonalData` record named
`personal-data-v1`. Its encrypted `payload` Bytes field holds the merge document.
The 750 KB encoded limit is checked before upload. Errors retain local changes;
the UI reports an unavailable/limit/pending-deletion state. Sync runs on launch,
foreground, local changes (debounced), and Sync Now. It is not continuous
background sync. No remote notification entitlement is requested.

Lists merge by stable item identity; cart lines use catalog + store, not random
UUID. Same-item conflicts use logical counters, then device ID as a tie-break.
Deletion tombstones remain until reset; an erasure changes the generation and
replaces old content with an empty document. Offline erasure persists and retries.
Account changes pause sync; return to the original account to finish deletion.
Signing into a different Apple Account does not upload the previous account's data.

## Apple configuration (must be verified in the owner's account)

Local archive verification on 2026-10-29 failed with `No Accounts` and no
provisioning profile for `com.mostafa.mealio`, including when automatic provisioning
updates were allowed. Sign in through Xcode Settings → Accounts before proceeding.
No archive has been uploaded or submitted. The built app's API key is also empty;
backend authentication activation remains a separate deferred release task.

1. Open `smartmarket.xcodeproj` with the Apple Developer account/team signed in.
2. In Signing & Capabilities, enable iCloud → CloudKit and select/create
   `iCloud.com.mostafa.mealio`. The entitlement is already wired in both configs.
3. Refresh development/distribution provisioning profiles. Confirm they include
   the iCloud container; an unsigned simulator build does not prove this.
4. Run a signed development build, enable shopping sync, and create shopping data.
   In CloudKit Console, inspect the development schema for `MealioPersonalData`
   with encrypted `payload` of type Bytes. The app's private data is not exposed
   as public records. Do not create a public mirror.
5. Deploy that schema to Production before distributing through TestFlight.
   Do not add public read/write security roles for this private data.

## Required live acceptance checks

- Two devices, same Apple Account: enable sync, add distinct cart items offline
  on each, reconnect and use Sync Now on each. Both items should remain.
- Add the same product/store independently: one line remains (same-item conflict
  resolution, not arithmetic quantity addition).
- Change budget, correct a price, mark a grocery row bought and delete it; verify
  both directions after each sync.
- Keep device B offline, delete all data on A, reconnect B: pre-deletion shopping
  items must disappear. Body stats and intake on B remain local to B.
- Delete while offline, restart the app, reconnect: pending cloud deletion must
  complete and stay empty when an older device returns.
- Terminate the process during deletion and relaunch: interrupted local erasure
  must finish before sync can capture old shopping rows.
- Sign out/switch Apple Account: sync pauses and the prior data must not upload
  to the new account. Return to the original account to resume/delete.
- Deny/unavailable iCloud or insufficient quota: offline editing must still work.
- Confirm body stats, food log, dietary restrictions and meal plans never appear
  in the decoded cloud payload, including tombstones and the local sync journal.
- Verify a signed Release build and repeat the smoke tests via TestFlight.

## Local verification

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox`

Build Debug and Release for the simulator. Test results cover merge, payload
filtering and serialization, not Apple's live service or signed provisioning.
