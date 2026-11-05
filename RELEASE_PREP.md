# Mealio iOS release preparation

This is a preparation record, not an assertion of App Store readiness.

## Changes prepared

- Removed the map's promotion-category badges and made the legacy category label
  neutral. Curated prices are estimates, not verified promotions or availability.
- Added native `smartmarketTests` and `smartmarketUITests` targets to the shared
  scheme. CI runs the tests and preserves the result bundle/screenshots.
- Added cart-clear regression coverage, food-log deletion checks and explicit AI
  consent boundary tests using an isolated transport (no Groq calls).
- Online AI is off by default. Profile explains what goes through the backend to
  Groq and lets users grant/revoke permission. Local meal suggestions remain.
- Removed names from meal-plan requests. Corrected the onboarding claim that
  location never leaves the device. Location requests do reach the backend.
- Removed the unsupported free-text allergy field and the allergy-safety promise.
  Preferences guide suggestions; ingredients and allergens still need checking.
- Offline onboarding initializes and persists the planner's calorie targets.
- Welcome/permission screens support scrolling at large text sizes. Profile
  metrics stack at accessibility sizes; skip actions have 44-point minimum height.
- Bundled the reviewed privacy/support documents for offline access from Profile.
  Build-secret files are excluded from the app's resource bundle. A follow-up
  check found flattened backend source/bytecode in the existing bundle despite
  excluding the parent folder. Explicit file/pattern exclusions and
  `scripts/check-ios-bundle.py` now guard this boundary in CI. Fresh simulator
  Release and unsigned device archives pass this check as of 2026-11-05.
- Prepared `APPSTORE_COPY.md`, with a 6-character name, 27-character subtitle,
  157-character promotional text and 68-character keyword draft.

## Before submission

- Sign in to Xcode Accounts, verify developer membership, signing and a real
  device archive. No successful signed device archive has been produced yet.
- Activate CloudKit and its Production schema, then execute all two-device
  cases in `ICLOUD_SETUP.md`. Simulator tests do not verify Apple's live service.
- Activate the deferred backend key without putting it in chat/history, then
  verify authenticated production calls and operational cost controls.
- Provide a verified support contact and hosted privacy/support URLs. Bundled
  documents do not replace App Store Connect's URL fields.
- Approve final app-icon artwork; the existing pink monogram was reviewed but
  has not been replaced or approved as final branding.
- Select final screenshots from a signed build with realistic synthetic content.
  Automated screenshots are QA evidence and may show offline/local states.
- Verify store addresses/catalog estimates before making public location claims.
- Finish real-device, VoiceOver, reduced-motion and smaller-device review.
  Navigation smoke tests are not a full accessibility certification.

## Reproducing local checks

Latest build verification (2026-11-05): Xcode initialization is working again.
The fresh simulator Release build at `/tmp/MealioReleaseClean-20261105` succeeds
and passes `scripts/check-ios-bundle.py`. The unsigned iPhone archive at
`/tmp/MealioDevice-20261105.xcarchive` also succeeds and passes the same guard.
Both contain the offline privacy/support documents and exclude backend source,
test caches, local tool settings and build-secret files. The first build exposed
previously missed `.pytest_cache` files and `.claude/settings.local.json`; explicit
membership exclusions and recursive guard coverage now cover these. Four guard
tests, 16 Swift sync tests, 13 backend tests and 16 native iOS tests pass.

The first builds emitted Xcode's App Intents metadata warning. Mealio has no App
Intents declarations, so project configurations now set
`LM_SKIP_METADATA_EXTRACTION = YES` (remove the opt-out when adding App Intents).
The [official build-system task producer](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBApplePlatform/AppIntentsMetadataTaskProducer.swift)
guards extraction with this setting. The fresh build at
`/tmp/MealioWarningFree-20261105` succeeds with zero warning/error diagnostics and
passes the real-bundle guard. Compiler warning settings remain enabled.
Signed archiving was
retried with provisioning updates on 2026-11-05 and still fails with `No Accounts`
and no provisioning profile for `com.mostafa.mealio`. The unsigned archive cannot
be uploaded to TestFlight. UI verification is recorded separately below; the
first renewed run reproduced an onboarding automation failure and was interrupted.

Live backend check (2026-11-05): `/api/health` returned HTTP 200 without an API
key. Production authentication has not passed the deferred activation checklist.
No paid AI call or personal-data request was made for this check.

## Historical checks (2026-10-30)

Verification record (2026-10-30): 16 native iOS unit tests passed in
`/tmp/Mealio-Verified-20261030.xcresult`, including offline onboarding persistence
and both AI-consent cases. The same run failed to launch the UI test runner:
SpringBoard returned `Busy / Application failed preflight checks` and the
instruments lockdown service timed out. This is a failed overall test run, not
an all-green suite. Separately, 16 Swift sync regressions and 13 backend tests
passed. An earlier standard-size onboarding/all-tabs UI test passed, but is not
a complete final UI signoff. Final privacy/support navigation, dark mode,
largest-text and VoiceOver verification remain outstanding. Direct computer-use
fallback also failed to start its service. Preserve these limitations when
handing the project to another developer or preparing a submission.

Final named/generic Release compile attempts stalled in Xcode services and were
interrupted; they are not successful Release verification. The generic Debug
rebuild after the packaging correction also stalled. The bundle checker correctly
fails the old app bundle for backend source/bytecode; do not submit that bundle.
No `.env` or `Secrets.xcconfig` was found in the inspected app. Restore
Xcode/Simulator services, clean-build, rerun the bundle checker and complete the
remaining UI checks before TestFlight.

Follow-up verification (2026-10-30): the dedicated simulator is booted and a
fresh screenshot succeeds when Simulator is accessed outside the sandbox.
The fresh Release build at `/tmp/MealioReleaseVerified-20261030` still stalled
before creating DerivedData or producing compiler output and was terminated.
A process sample at `/tmp/Mealio-xcodebuild-sample.txt` places the main thread
in Xcode's DVT plug-in/class loading during project initialization. This narrows
the current blocker to build-tool initialization; it does not certify the code
or the corrected package. Do not describe the simulator as universally unavailable.

The bundle guard now also rejects arbitrary `.env.*` variants. Four fixture-based
regression tests pass, including nested backend/build files, missing offline
policy documents and environment-file variants; these run in CI. The existing
Debug bundle still fails the guard for backend resources and is unsuitable for
submission. A successful fresh build and real-bundle check remain required.

Run the commands in `smartmarketTests/README.md` on a dedicated simulator. Runtime
tests use local ad-hoc signing; unsigned builds are compile-only evidence. Swift
sync tests also run through `swift test --disable-sandbox`. Result bundles retain
failed checks as well as passing screenshots; do not report interrupted or
failed runs as successful verification.
