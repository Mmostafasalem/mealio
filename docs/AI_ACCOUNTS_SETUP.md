# Guest and Apple AI accounts — activation checklist

Implementation is local; this document does not mean the feature is live.
Never paste secrets into chat, commit them, or include Apple server keys in iOS.

## Behavior
- Guest access and optional native Sign in with Apple in Profile, with no name/email scopes.
- Guests use a 256-bit random device-only Keychain secret and hashed bearer sessions. Guest recovery keeps the same account/allowance; new-account setup is capped at five per network/day, with separate global provider limits.
- Local shopping, tracking and offline plans need no account.
- Online AI separately requires sharing consent and a verified session.
- Default 30 credits/person/day: meal plans cost 5, other AI requests cost 1.
  Automatic online plan updates count. Reset is midnight UTC, displayed locally.
- Failed provider requests and cached responses refund personal credits.
- Personal allowances still share provider capacity and a global attempt ceiling.
- State survives app devices and server restarts on durable storage.
- Delete All Data revokes the Apple grant and purges the account before clearing
  local data. It requires a connection and valid sign-in. Sign-out is not deletion.
  A device marker makes deletion require sign-in even after sign-out. A keyed
  subject hash and today's spending survive account deletion until the daily
  reset to prevent recreation abuse; expired rows are cleaned on service activity.

## Owner setup before real-device testing
1. Enable Sign in with Apple for explicit App ID `com.mostafa.mealio` in Apple
   Developer. Select the correct primary/group configuration and regenerate
   development/distribution profiles. The entitlement is already in the project;
   simulator compilation does not activate Apple sign-in.
2. Create a Sign in with Apple server key for this App ID. Keep the .p8 private.
   Set server-only `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (PEM;
   escaped newlines are accepted) and `APPLE_APP_ID=com.mostafa.mealio`.
3. Provision durable storage. Render's free ephemeral filesystem does not qualify.
   Use ONE service instance with a shared writable SQLite volume mounted at
   `/var/data`. Set `AI_STATE_DB=/var/data/mealio-ai.sqlite` and
   `AI_STATE_PERSISTENT=1`. No paid resources have been provisioned automatically.
   Migrate to a shared transactional database before horizontal scaling.
4. Generate stable `AI_SUBJECT_SECRET` (at least 32 random bytes encoded as text)
   and `AI_TOKEN_ENCRYPTION_KEY` (Fernet key) locally. Put them only in server
   secret settings. Losing or rotating them requires deliberate account migration.
5. Optional limits: `AI_DAILY_CREDITS=30`, `AI_GLOBAL_DAILY_ATTEMPTS=900`.
   Tune the global limit to actual provider capacity, not the number of users.
   APP_API_KEY remains required for legacy catalog/BMR routes, but is not needed for public auth bootstrap or bearer-protected AI/account routes.
6. Set Apple's server notification URL to
   `https://YOUR_BACKEND/api/auth/apple/notifications`. This route accepts signed
   Apple payloads without Mealio's shared key; forged notifications are rejected.
7. Enable `AI_ACCOUNTS_ENABLED=1` only after the prerequisites are ready. Missing
   account configuration fails closed for AI; catalog and BMR remain available.
8. Verify the provider model independently. The earlier live Groq test returned
   fallback text. This change does not change the model or certify live inference.
9. Do not deploy enforcement to the public web client yet. It needs equivalent
   Apple authentication and bearer forwarding; the shared-key proxy is insufficient.

## Staging verification
- Public config endpoint returns enabled=true plus guestEnabled/appleEnabled flags without an app key.
- AI with only the shared key returns 401 without calling the provider.
- On a provisioned device, sign in, enable AI sharing separately, and generate
  one real response. Check remaining credits and the local reset time.
- A second device with the same Apple account sees the same allowance; a second
  person has a separate allowance.
- Exhaust the allowance: 429 includes the reset and Retry-After.
- Simulate provider failure: fallback consumes no personal credits.
- Restart/redeploy: personal allowance is retained.
- Sign out on one device: that session is rejected while other sessions work.
- Delete All Data: revoke Apple grant, reject other sessions, erase local profile
  and log, request private shopping deletion.
- Revoke Apple access and verify the signed notification invalidates sessions.
- Offline account deletion reports failure rather than claiming completion.
- Logs contain no JWTs, authorization codes, sessions, keys, refresh grants or
  health/chat bodies. App Privacy includes linked User ID and Product Interaction
  for functionality, with no tracking.
- Document secure volume access, backups, deletion handling and retention before
  launch. The account database is private data despite containing no health bodies.

Sessions expire after 30 days. Apple grants are revalidated after 24 hours of
account activity. Remote sign-out is best effort if offline: a copied session
may remain valid until expiry/revocation. Protect tokens as secrets. The app has
no offline-only erasure override for a saved AI account; reconnect/sign in to
complete Delete All Data. Routine cleanup is activity-driven.


## Duplicate-request safeguards
The iOS app gives each AI request an Idempotency-Key. The authenticated person,
request path and exact body are bound to the key. Concurrent repeats do not call
the provider or reserve credits again; changed input with the same key returns
409. Metadata is retained 24 hours, capped at 2048 keys/person, and purged with
the account. It contains only hashes, an HMAC fingerprint and creation time.
A bounded per-process in-memory cache replays up to 128 small responses for a
three-minute window. Expired entries are cleared on replay activity or eviction;
no response bodies go into SQLite/backups. Account deletion clears this process's
replays. Other processes still authenticate before any replay. After expiry,
eviction or restart, an existing key returns 409 rather than rerunning AI.
This protects transport retries carrying the same key; a deliberately new action
has a new key and may use credits. There is no payment/checkout flow in Mealio.

## Guest-first activation on the existing Render service

No paid resource or production flag has been changed by this implementation.
The existing Free service cannot provide the durable SQLite volume this account
implementation requires. Prepare the existing service with a paid compute plan
and a 1 GB persistent disk mounted at `/var/data`; verify the current price in
Render before purchase. Current published base pricing is $7/month compute plus
$0.25/GB/month disk, excluding taxes, network overages and provider usage.

Use these settings after code deployment and disk verification:

```text
AI_ACCOUNTS_ENABLED=1
AI_GUEST_ENABLED=1
AI_APPLE_ENABLED=0
AI_STATE_DB=/var/data/nourlo-ai.sqlite
AI_STATE_PERSISTENT=1
AI_DAILY_CREDITS=30
AI_GLOBAL_DAILY_ATTEMPTS=30
```

Generate and securely store stable server-only `AI_SUBJECT_SECRET` and
`AI_TOKEN_ENCRYPTION_KEY` before enabling accounts. Retain the existing Groq
provider key and model configuration. The global attempt ceiling is a request
limit, not a dollar budget; confirm provider billing separately. Keep one worker
with threads and one attached disk; multiple independent copies cannot share this
SQLite allowance store. Configure disk backups and restore/deletion procedures.

Guest-first activation does not remove Apple support. Set `AI_APPLE_ENABLED=1`
only after the Apple server signing keys, bundle capability and callback are ready.
Both guest and Apple accounts then remain supported. To switch methods and delete
all data, all accounts previously used on the device must be reauthenticated and
deleted; local erasure waits until these retained accounts are handled.

Required live proof: config shows guest enabled, guest login succeeds without an
app key, unauthenticated AI remains rejected, one real provider response consumes
the expected allowance, restart preserves that allowance, and deletion invalidates
its sessions. No production-readiness claim is justified before these checks pass.

## Current free hosting path

The paid Render disk approach above is superseded for the current deployment.
A Neon Free database `nourlo-accounts` is provisioned via Vercel in pdx1 on
billing plan free_v3. No paid Render change was made. AccountService now supports
`AI_DATABASE_URL` for Postgres. When it is present, no local SQLite disk or
`AI_STATE_PERSISTENT` flag is needed. Malformed URLs fail closed; the driver
always verifies TLS certificates and hostnames, regardless of URL sslmode.
Postgres quota changes use a transaction-wide advisory lock across all workers.

The private current activation file is
`/Users/mmostafasalem/.config/nourlo/guest-free-activation.env` (0600).
It reuses stable subject/encryption secrets and retains the existing provider
settings. It contains the database connection and guest-first flags, with
30 credits/device/day and 30 global attempts/day. Never commit or paste this file
into chat. Do not import the older disk-based activation file.

The database's Free allowances are limited; cold starts and capacity limits still
apply. No auto-upgrade or paid plan was selected. The iPhone requests allow extra
wake time instead of failing after 30 seconds. Verify current provider limits and
billing independently before public launch.
