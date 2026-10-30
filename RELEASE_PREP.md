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
  Backend source/build-secret files are excluded from the app's resource bundle.
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

Run the commands in `smartmarketTests/README.md` on a dedicated simulator. Runtime
tests use local ad-hoc signing; unsigned builds are compile-only evidence. Swift
sync tests also run through `swift test --disable-sandbox`. Result bundles retain
failed checks as well as passing screenshots; do not report interrupted or
failed runs as successful verification.
