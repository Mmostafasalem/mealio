# Nourlo AI accounts and deployment

Guest AI is active on the existing Render service with persistent Neon Postgres storage. No paid hosting upgrade or persistent Render disk was selected. Never paste credentials into chat, commit them, or include provider/Apple server keys in iOS.

## Current deployment

- Backend: https://mealio-backend-d7aa.onrender.com
- Render service: `srv-dbnh60rrjlhs738q8fn0`, Free compute, auto-deploying `codex/stock-and-goals`.
- Neon: `nourlo-accounts`, project `dawn-river-72271199`, `free_v3`, pdx1. Its Vercel connection is development-only; Render receives its private connection through server environment settings.
- Guest access is enabled. Apple access remains disabled until the Apple capabilities and server signing credentials are configured.
- Provider model: existing Groq `openai/gpt-oss-120b`; existing provider and legacy app keys were preserved.
- Default personal allowance: 30 credits/device/day. Weekly plans cost 5; chat, recipes and other suggestions cost 1. Failed/fallback responses do not spend personal credits.
- Current overall limit: 30 provider attempts/day across the service. This is a conservative request cap, not a dollar budget or a public capacity guarantee.
- Free hosting can sleep; account and AI requests allow additional wake time. Free database/provider allowances remain limited. No automatic paid upgrade was selected.

Server settings:

```text
AI_ACCOUNTS_ENABLED=1
AI_GUEST_ENABLED=1
AI_APPLE_ENABLED=0
AI_DATABASE_URL=<private Postgres connection>
AI_SUBJECT_SECRET=<stable private secret>
AI_TOKEN_ENCRYPTION_KEY=<stable private Fernet key>
AI_DAILY_CREDITS=30
AI_GLOBAL_DAILY_ATTEMPTS=30
```

The imported private settings file is `/Users/mmostafasalem/.config/nourlo/guest-free-activation.env` (0600). Do not import the older disk-based activation file. Database connections verify TLS certificates and hostnames. Quota mutations use a transaction-scoped advisory lock across workers; malformed database configuration fails closed. SQLite remains supported for a single instance with an explicitly configured persistent volume, but is not used by this deployment.

## Verified live behavior — 2026-11-08

- Public auth config reports guest enabled; guest login works without the legacy shared app key.
- Authenticated chat returns HTTP 200 with `X-AI-Result: online`; its personal allowance is charged once. Unauthenticated AI is rejected with 401.
- The existing synthetic guest session and exact credit balance survived backend redeployment.
- Deleting the synthetic account returns 204; its former session subsequently returns 401.
- Weekly planning returns 28 online meals with valid ingredient portion IDs referencing the submitted synthetic USDA foods. A separate real provider check also verified that the aggregate amounts stayed within the supplied stock. This does not guarantee every future model response or dietary suitability.
- Real Postgres integration contracts passed in an isolated disposable schema, including concurrent reservations, persistence and failure refunds/deletion.

Physical-device and App Store release verification are separate requirements. A Personal Team test installation is not production distribution.

## Account and privacy behavior

Guests use a 256-bit random device-only Keychain secret. The server stores a keyed identity hash and hashed bearer sessions, not the raw device secret. Recovery retains the same account and allowance; new guest setup is capped at five per network/UTC day. Sessions expire after 30 days.

Signing in does not enable AI sharing. The app separately requires consent before sending relevant food, goal and chat context through the backend to Groq. Account storage contains identity/session/quota records, not body measurements, food logs or chat bodies. Local tracking and offline suggestions work without an account.

Delete All Data deletes retained online accounts before clearing local data; it requires a connection and valid sign-in. Guest/Apple switching must not orphan earlier accounts. Sign-out alone keeps the online account. Today's keyed spending survives deletion until the daily reset to limit recreation abuse; expired rows are cleaned during activity. A copied offline session may remain valid until remote sign-out, expiry or deletion. Protect tokens as secrets.

## Adding Apple sign-in

1. Use an Apple Developer account that supports Sign in with Apple and the production App ID `com.mostafa.mealio`. Regenerate the appropriate provisioning profiles.
2. Create the Apple server signing key and set server-only `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` and `APPLE_APP_ID=com.mostafa.mealio`. Never put the .p8 in iOS or Git.
3. Set Apple's signed notification URL to `https://mealio-backend-d7aa.onrender.com/api/auth/apple/notifications`.
4. Enable `AI_APPLE_ENABLED=1` after verifying the configuration; guest access can remain enabled.
5. Verify real device authorization, cross-device allowance, revocation notification, grant revalidation and deletion before claiming Apple sign-in works.

## Duplicate requests and operations

Each iOS AI action has an Idempotency-Key bound to account, route and exact body. Concurrent repeats do not call the provider or reserve credits again. Changed input under the same key returns 409. Metadata contains only hashes, an HMAC fingerprint and timestamps; it is retained for 24 hours and capped at 2048 keys/person.

A bounded process-memory cache replays up to 128 small responses for three minutes. No response bodies enter the persistent account database. Account deletion clears this process's responses; every worker still authenticates before replay. After expiry/eviction/restart, an existing key returns 409 instead of repeating AI.

## Release checks still required

Verify actual device journeys and production signing, Apple-specific behavior when enabled, backup/restore and deletion procedures, service capacity and provider billing, privacy disclosures and operational monitoring. Catalogue product records do not prove current branch stock/prices. Do not call the entire app production ready based only on successful AI activation.

Live UI verification is opt-in: select `ReleaseSmokeTests/testLiveGuestSignInChatAndAccountDeletion` with `TEST_RUNNER_NOURLO_LIVE_GUEST_UI=1` only on a fresh simulator named `Nourlo Guest AI Verification`. It uses synthetic onboarding data, performs a real AI request and deletes its test account/local data.
