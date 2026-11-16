# Personal AI accounts — local verification, 2026-11-06

This verifies local code, not live activation or App Store readiness.

- Backend: 47 tests passed, including actual RSA signatures, nonce replay,
  concurrency, separate users/shared devices, midnight reset, restart durability,
  failed/cached refunds, valid endpoint charging, signed Apple revocation events,
  deletion/recreation abuse and disabled-service fail-closed behavior.
- The five review regression cases were reproduced failing before the fixes
  (/tmp/mealio-ai-review-red2.log), then the full suite passed after corrections
  (/tmp/mealio-ai-final-backend.log). Apple and Groq network calls were mocked;
  JWT signatures and SQLite transactions were exercised directly.
- iOS: 21 native tests and one UI test passed. The new native checks cover consent
  versus authentication, the bearer header, and deletion after sign-out. UI checks
  cover the Apple control's touch height and local navigation without an account.
  Result: /tmp/MealioAIAccountsTests3.xcresult.
- Release simulator build: succeeded with zero compiler errors/warnings in
  /tmp/MealioAIAccountsRelease.log. Earlier development iterations caught and
  corrected an async reset caller, actor isolation, and an incorrect UI target name.
- Actual Release .app passed scripts/check-ios-bundle.py: reviewed privacy manifest
  and bundled legal documents match; no backend/Python/build-secret files shipped.
- Nine release/privacy declaration tests passed. git diff --check passed.

## Review corrections
1. Deletion purges credentials and sessions but preserves today's keyed subject
   and spent-credit count independently, preventing same-day quota recreation.
   It expires at the next UTC day and is removed on subsequent service activity.
   Privacy policy now discloses this narrow anti-abuse retention.
2. A minimal Keychain marker survives sign-out, so Delete All Data requires
   reauthentication instead of silently skipping a retained online account.
3. Provider JSON must satisfy the endpoint's usable-output check before credits
   count as spent; invalid/empty plans and recipes use uncharged fallback results.

Follow-up independent review confirmed the three corrections and independently
reran all 47 backend tests with no remaining findings on those corrections.

## Not verified / not activated
Real Sign in with Apple on a provisioned device, Apple notification delivery,
live refresh/revoke, durable hosted storage, real Groq inference, deployment,
web authentication and App Store upload. No real signing keys were requested or
placed in conversation. No server secrets, paid resources or deployments changed.
Follow AI_ACCOUNTS_SETUP.md for owner activation and staging verification.
