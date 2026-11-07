# Mealio iOS — release status, 2026-11-06

**Local candidate prepared; public release is blocked by account activation.**
This record distinguishes simulator/automated evidence from real-device and live-service verification.

## Completed in this release pass
- Fixed store-specific user price overrides, including undo, legacy values and sync compatibility. Other prices remain curated estimates; no retailer feed, promotion or inventory claim was added.
- Updated the default AI provider model and model-specific completion handling; truncated output cannot be recorded as successful inference. Real provider access is still unverified.
- Added fail-closed production checks, protected readiness, minimal public `/healthz`, and an explicit catalog-only configuration with AI disabled until account/storage activation.
- Pinned 27 production Python packages and audited the lockfile. Added backend, privacy/bundle, browser and native regression coverage to CI.
- Prepared public `/privacy` and `/support` pages from the same canonical documents bundled in iOS. Corrected Apple sign-in, consent, daily credit and deletion copy.
- Generated the local app key and account encryption/hash secrets in ignored, owner-readable files. No values were printed, committed or sent to hosting. Real Groq and Apple credentials are still absent.
- Prepared an unsigned device archive and ten actual simulator screenshot candidates in ignored `release-artifacts/`. No signed or uploadable build is claimed.

## Verification evidence
- Backend: **63 passed**, pinned production dependency environment; `/tmp/MealioReleaseFinalBackend.log`.
- Native unit tests: **31 passed**; `/tmp/mealio-price-green-native.xcresult`.
- Swift sync regressions: **16 passed**; `/tmp/MealioReleaseSyncTests-20261106.log`.
- Release/privacy/auth-script regressions: **14 passed**; `/tmp/MealioReleaseScriptTests.log`. Auth tests use local synthetic services and verify keys are not printed.
- Production package audit: no known vulnerabilities reported for the lockfile; `/tmp/mealio-production-audit.log`. This is a point-in-time dependency check, not a guarantee of security.
- Final device archive: `/tmp/MealioPrelaunchFinal-20261106.xcarchive`, copied to `release-artifacts/Mealio-Unsigned.xcarchive`; **0 errors / 0 warnings**. Strict bundle check confirms a configured key and HTTPS endpoint, required privacy/legal resources, and absence of backend/secret files. It does not certify signing.
- Five iPhone 6.9-inch PNGs (1320×2868) and five iPad 13-inch PNGs (2064×2752). The initial parallel screenshot run passed on iPad but failed one iPhone onboarding assertion. An unchanged separate iPhone rerun passed; `/tmp/MealioStoreScreenshotIPhoneVerified.xcresult`. Candidates need owner review before upload.
- Web browser regression: **1 passed**, covering hydration, functional updates, shared hooks and storage failures. Lint and production build passed; `/tmp/MealioFinalWebBuild.log` records the build.
- Candidate source saved locally in commit `e3838fa`. Attempted push to isolated `release/prelaunch-2026-11-06` failed: GitHub rejected the saved username/token. No branch was pushed, no merge occurred, and remote CI did not run. GitHub login must be restored before that independent check.
- Local backend runtime was Python 3.11.4. Render is configured for 3.11.18; hosted-runtime verification remains open.

## External blockers — not completed
1. **Apple Developer membership:** owner says not yet available. A development signing identity exists, but the signed archive attempt failed because the matching provisioning profile is absent. No TestFlight upload or submission is possible yet.
2. **Support contact:** the existing public repository issue tracker is linked for pre-release technical reports, with privacy cautions. A suitable private support contact and required operator/trader information are still needed for the intended storefronts.
3. **Hosting access:** Vercel token is invalid; Render is not connected. No external deployment or environment setting was changed. Public probes found the old backend, unauthenticated `/api/health`, missing `/api/auth/config`, and 404 policy/support routes. Do not publish the iOS candidate against that state.
4. **AI activation:** real provider and Apple credentials, matching app key on hosting, durable account/allowance storage, and successful live inference/auth/revocation checks are required. The prepared default has online AI off. Existing web personal-AI authentication compatibility is a separate gate before enabling accounts on the shared backend.
5. **CloudKit and device signoff:** Production schema, two-device sync/deletion, provisioned Sign in with Apple/revocation, physical-device VoiceOver/Reduce Motion and TestFlight testing remain unverified.

Follow `docs/PRELAUNCH_ACTIVATION.md`, `AI_ACCOUNTS_SETUP.md`, `ICLOUD_SETUP.md` and `ACTIVATE_AUTH.md` when access is available. Do not paste secrets into chat. No merge to main, paid subscription, Apple agreement, or App Store submission is authorized by this status record.

## Branding follow-up — 2026-11-06

The owner selected the complete bowl mascot, including arms, feet and breakfast
food, for the app icon. Applied a 1024×1024 opaque RGB icon and a companion
welcome-screen logo. Release simulator build and refreshed unsigned device
archive both passed with **0 errors / 0 warnings**, and strict bundle checks
passed. The final welcome screen was visually inspected on the dedicated iPhone
simulator. The archive currently at `release-artifacts/Mealio-Unsigned.xcarchive`
now includes this branding; the previous archive is preserved separately.
Logs: `/tmp/MealioFullMascotLogoBuild.log`, `/tmp/MealioFullMascotArchive.log`.
This presentation-only change did not rerun the previous full test suite or
resolve any external activation blocker.

## Physical-phone testing — 2026-11-06

The owner signed in to Xcode, enabled Developer Mode, approved development
provisioning and confirmed the installed app works on their iPhone 15 Pro. A
separate Debug-only Personal Team build is installed as
`com.mostafa.mealio.phonetest`; iCloud and Apple AI sign-in are unavailable in
that copy. Its verified profile expires on 2026-11-13. Normal production
entitlements remain intact, and the production Release build still passes with
zero warnings/errors. See `docs/PHONE_TESTING.md` for scope and evidence.
This establishes a working local device test, not paid membership, production
signing, full device acceptance or online service activation.


## Hosted backend activation — 2026-11-07

The owner restored GitHub login and entered the provider/app settings directly
in Render. The prepared branch `release/production-ai-2026-11-07` was pushed
without merging main. Render Blueprint now tracks that branch. Commit `37c2022`
is live at `https://mealio-backend-d7aa.onrender.com` with locked dependencies,
production configuration checks and `/healthz` liveness.

Verified against the live service: public liveness 200; health without key 401;
matching app key accepted; protected readiness 200 with no missing configuration;
synthetic BMR 200. AI config reports disabled and an AI request correctly returns
503. This proves secured catalog-only hosting, NOT live AI inference. Production
Apple account credentials/capabilities and durable allowance storage remain
required before enabling AI. No paid plan or Apple membership was purchased.

GitHub run 42371210970 passed backend and web checks. The iOS job failed under
Xcode 16.4 on four list `ForEach` expressions with `MapContentBuilder` overload
errors. Local Xcode builds passing do not override this independent failure;
resolve compiler compatibility before release signoff.

The iOS endpoint now targets the new secured backend. A fresh private phone
build uses ordinary Info.plist with no OWNER_AI_* fields, replacing the previous
Mac-specific configuration. Mac relay was stopped. Its test tooling remains
separate from production; archived testing notes are not an active AI solution.
