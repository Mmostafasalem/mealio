# Mealio — external activation needed before public release

The owner confirmed on 2026-11-06 that a public support email and Apple Developer
membership are not set up yet. Code preparation does not replace these steps.
No purchase, enrollment, legal agreement, credential creation or submission has
been completed on the owner's behalf.

## What is prepared
- Correct bundle ID/team configuration, optional Apple AI accounts, per-person
  daily quotas, account deletion/revocation and retry safeguards.
- Supported GPT-OSS provider default and a gated synthetic inference check.
- Store-specific user price corrections; all other grocery prices remain estimates.
- Public /privacy and /support page source, canonical iOS/web legal mirrors.
- App Store copy/review notes updated for sign-in, consent, credits and deletion.
- Pinned production dependencies, vulnerability audit, native/backend/web checks.
  Render is prepared for Python 3.11.18; CI selects the latest 3.11 patch.
  Local backend tests used Python 3.11.4, so hosted-runtime validation remains required.
- Render core-only configuration with explicit AI off; no provider key needed for
  catalog-only mode. AI activation still needs Apple keys and durable storage.

## Owner-only prerequisites
1. Enroll/activate Apple Developer membership, accept Apple's terms personally,
   and configure the App ID/capabilities/profiles. A local Apple Development
   identity exists, but the matching provisioning profile is missing. The signed
   archive failed; an unsigned archive cannot be uploaded to TestFlight.
2. The existing public GitHub issue tracker is linked for pre-release technical
   issues. Create a support mailbox (or another compliant private contact) the owner controls.
   Supply the public contact plus any operator/trader details Apple requires for
   the intended storefronts. Do not invent these from a personal username.
3. Restore GitHub login (push was rejected), reauthenticate Vercel (existing token is invalid), and connect Render. Browser
   automation could not open account pages in this session; the Mac was locked.
   No hosting configuration or production deployment has been changed.
4. The app key, subject hash secret and token-encryption key are now generated
   locally in gitignored, owner-readable files; their values were not displayed.
   Deploy the matching values and supply real provider/Apple credentials in hosting settings,
   never in chat or source. AI accounts require durable storage; free ephemeral
   Render storage does not provide persistent allowances. Provisioning a paid
   plan or accepting a subscription requires the owner's decision.
5. Activate CloudKit Production and execute the two-device shopping/deletion
   checks in ICLOUD_SETUP.md. Sign in with Apple and revocation delivery require
   a provisioned real-device check, not mocked JWT tests alone.
6. Validate the signed build on physical devices with VoiceOver and Reduce Motion,
   upload to TestFlight, review the selected screenshot candidates and final
   privacy answers, then submit to Apple. No App Store approval is implied.

## Operator checks when access is available
- In the backend folder, install requirements.lock. Set MEALIO_ENV=production,
  a strong APP_API_KEY and explicit AI_ACCOUNTS_ENABLED=0 for catalog-only mode,
  or follow AI_ACCOUNTS_SETUP.md completely before setting the flag to 1.
- Run python release_config.py. It reports missing field names, never secrets.
- Render's health check is /healthz (minimal public liveness). /api/health and
  /api/readiness remain protected by the app key. Readiness is configuration/
  storage validation, not proof of working provider inference.
- With the real GROQ_API_KEY set locally/on the server, run
  python provider_smoke.py --live. It makes one synthetic request and prints only
  ONLINE versus FAILED/FALLBACK, never credentials or generated health content.
- Run scripts/verify-auth.sh using a locally supplied key after deployment; then
  complete the iOS/Apple/device checks. Deployment does not automatically turn a
  previously built app's empty key into the correct key.
- Deploy the prepared /privacy and /support routes after adding the contact. Check
  both public URLs and enter them in App Store Connect. Local builds are not URLs.
- Keep web personal-AI authentication as a separate compatibility gate before
  enabling AI accounts on a backend shared with the current web proxy.

## Pricing scope
Launch with clearly labelled curated estimates and store-specific user-entered
prices. There is no verified retailer price feed or stock integration. Live
prices/promotions cannot be promised through scraping assumptions or invented
comparisons. A verified data source would be a separate feature, not a release
checkbox that can be marked complete today.
