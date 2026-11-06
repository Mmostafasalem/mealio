# Personal AI accounts — activation checklist

Implementation is local; this document does not mean the feature is live.
Never paste secrets into chat, commit them, or include Apple server keys in iOS.

## Behavior
- Optional native Sign in with Apple in Profile, with no name/email scopes.
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
   Keep APP_API_KEY configured consistently in the backend and signed iOS build.
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
- Config endpoint returns enabled=true with the app key.
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
