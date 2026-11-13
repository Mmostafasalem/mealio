# Nourlo — release status, 2026-11-13

**Full-stack review pass applied and verified locally. Public release is still
blocked by the same external items as 2026-11-06 (Apple membership, support
contact, AI activation, device sign-off).**

This record supersedes `RELEASE_STATUS_2026-11-06.md` for code state; that
file remains the record for hosting activation history.

## What changed in this pass

Three independent code reviews (iOS, backend, web/release) were run, verified
against the code, and every code-fixable finding was applied in three commits
on `codex/stock-and-goals`:

### iOS (`a1fed64`)
- **Safety:** the offline / no-consent meal plan now excludes foods that
  conflict with every dietary preference and allergy. Rules are deliberately
  cautious (halal drops unlabelled meat; nut allergy also drops snacks and
  bakery). `DietaryFallbackTests` covers each preference alone and combined.
- Profile body-stat edits now update `AppState`, recompute BMR and refresh the
  Home ring and macro targets immediately.
- Cart edits rebuild a **local** plan only; online AI never fires from cart
  changes. The daily-refresh date is stamped only after a plan is saved. A
  guard prevents concurrent online regenerations.
- Remote iCloud sync applies in place; it no longer rebuilds the root view, so
  open sheets and in-flight chat replies survive.
- `ResilientStorage` decodes arrays element by element and copies the raw blob
  to `<key>.corrupt` before anything can overwrite a failed decode.
- `planned_` grocery rows stay out of the CloudKit snapshot (and inbound apply
  cannot delete them).
- No coordinates are sent to `/api/deals` any more; distance filtering was
  already on-device. (The old call also sent km where the backend read metres,
  so it never returned live nearby deals.)
- Macros display "not available" instead of 0 g when ingredients are missing.
- Chat keeps typed text when sign-in/consent is required; history sent is
  capped at 20 messages.
- Single shared `MealPlanRequest.current(profile:bmr:)` builder.
- Delete All Data offers a local-only erase when the server AI account cannot
  be deleted, with instructions for deleting it later.
- Dead networking removed: `fetchBMR`, `calculateBMR`, `BMRRequest`,
  gap-filler models/endpoint, and the consent exemption for `/api/bmr`.
  Every POST now requires AI-sharing consent.
- Default base URL → `mealio-backend-d7aa`; privacy manifest adds DeviceID and
  SearchHistory; location usage string reworded to "nearby stores and
  estimated deals"; `PRIVACY.md`, `DATA_HANDLING.md` and bundled/web mirrors
  regenerated via `scripts/sync-legal-docs.py`.

### Backend (`cc266eb`)
- `/api/bmr` accepts iOS activity keys (`lightly_active` … `super_active`).
- Unusable AI output keeps a 1-credit non-refundable charge so refunds cannot
  drain the shared daily ceiling for free.
- Input clamps on gap-fillers, shopping-advice and meal-plan `goal`.
- Apple server-to-server `event_time` accepted in milliseconds.
- Failed AI requests release their idempotency key so retries work.
- `MEALIO_ENV=production` defaulted in Dockerfile/Procfile (fail-closed).
- Account cleanup throttled to once per minute; expiry enforced inline.
- `OverflowError` handled in numeric parsing; 4xx HTTP errors keep their real
  status instead of becoming 500.
- `SECURITY.md` / `DEPLOY.md` rewritten to match behaviour; Dockerfile now
  installs `requirements.lock` (same as Render).

### Web (`79ba80c`)
- Proxy allowlist: `products` GET, `bmr` / `meal-plan` / `agent-chat` POST.
  Everything else 404s before reaching the backend. Path traversal rejected,
  64 KB body cap, JSON content type required, per-IP rate limit, upstream 5xx
  bodies hidden.
- `BACKEND_URL` is required and must be `https://`; no fallback host.
- Security headers (CSP, HSTS, frame-ancestors, nosniff, referrer,
  permissions) on every route.
- Chat and meal-plan pages gated behind `NOURLO_WEB_AI_ENABLED=true`
  (default off: "coming soon" card, nav links hidden, proxy returns 503).

## Verification evidence (local, 2026-11-13, Xcode 26.5)
- iOS debug build: **0 errors / 0 warnings**.
- iOS native unit tests: **83 executed, 1 skipped (live owner-AI), 0 failures**,
  including 7 new tests.
- Swift sync regressions (`swift test`): **17 passed**.
- Release/privacy/bundle script regressions: **17 passed**.
- Backend: **116 passed, 3 skipped** (was 87 before this pass).
- Web: lint, `tsc --noEmit`, `npm test` (1 passed) and production build all
  pass; proxy rejection rules smoke-tested against `next start`.
- Full CI-equivalent iOS run (unit + UI tests, Release compile, bundle
  boundary check): see the commit that lands this file for the result.

## Deployment settings that must change
- **Vercel:** set `BACKEND_URL=https://mealio-backend-d7aa.onrender.com`
  (required; the site returns 503 without it). Set
  `NOURLO_WEB_AI_ENABLED=true` and redeploy only once backend AI is live.
- **Render:** no change required. Verify `TRUSTED_PROXY_COUNT` against a real
  request (see `DEPLOY.md`); if wrong, all users share one rate-limit bucket.
- **Local Docker:** pass `-e MEALIO_ENV=development`; the image now fails
  closed by default.

## External blockers — still open
1. **Apple Developer membership** → signing profile, TestFlight, submission.
2. **Support contact: done** — nourlo.app.support@gmail.com is in
   `SUPPORT.md`, `PRIVACY.md` and the bundled copies. Still open: EU trader
   information in App Store Connect if selling in the EU.
3. **AI activation:** real Groq + Apple credentials on Render, durable
   allowance storage, live inference / auth / revocation checks.
4. **CloudKit production schema**, two-device sync/deletion, Sign in with
   Apple on a provisioned build, physical-device VoiceOver / Reduce Motion,
   TestFlight acceptance.
5. **Remote CI:** the last three runs on this branch were cancelled
   (superseded) and never completed. The earlier Xcode 16.4
   `MapContentBuilder` failure was addressed by
   `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`; confirm on the
   next green run.
6. **Phone-test profile** `com.mostafa.mealio.phonetest` expired 2026-11-13;
   re-provision before the next device test.
7. **App icon: done.** New flat bowl mascot on navy, drawn in code
   (`docs/brand/app-icon.swift`); previous clay render kept in `docs/brand/`.

No merge to main, paid subscription, Apple agreement or App Store submission
is authorized by this status record.
