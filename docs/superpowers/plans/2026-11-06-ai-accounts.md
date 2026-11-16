# Personal AI Allowance Implementation Plan

> Execute inline, using existing iOS/backend architecture. User selected Sign in with Apple.

Goal: one server-enforced daily AI allowance per Apple user across devices. Basic local
features require no account. Provider quotas remain shared; do not claim extra free capacity.

- [x] Implement Apple identity verification using fixed Apple JWKS, RS256, issuer/audience,
  expiry and a short-lived server challenge consumed atomically once. Exchange authorization
  code server-side; encrypt refresh tokens and store only hashes of opaque app sessions.
- [x] SQLite transactional account/session/challenge/quota store on an explicitly configured
  durable path. One shared instance; document shared DB migration before horizontal scaling.
  Fail closed when unconfigured. No health/profile/chat bodies persisted.
- [x] Reserve per-user daily credits atomically before AI work; configurable default 30/day,
  plan cost 5, other requests 1. Refund failed/cached requests; expire abandoned reservations.
  Keep a separate app-wide attempt ceiling, returning clear shared-capacity errors.
- [x] Account/config/challenge/login/usage/logout/deletion endpoints. Apple refresh verification
  for long-lived sessions; account deletion revokes Apple grant before purging account data.
  Apple signed revocation notifications invalidate sessions. No client-selected quota identity.
- [x] Keychain iOS sessions, native Apple button, allowance/reset UI, typed sign-in/quota errors,
  no account data in private shopping sync. Delete account before completing Delete All Data.
- [x] Preserve explicit AI-sharing consent, local fallbacks and palette/layout. Update privacy
  disclosure/manifest and mirrored legal documents; document setup and deployment limitations.
- [x] Security regressions: forged/expired/wrong-audience/replayed tokens, concurrent limits,
  cross-device identity, UTC reset, refund, restart persistence, logout and deletion.
- [x] Backend tests, iOS compile/smoke, Release bundle privacy/legal checks. Record actual
  verification and all external activation blockers; no deployment or secrets in conversation.

External activation: Apple Developer capability/Sign in key, server-only secrets and persistent
storage. Existing live Groq inference is failing; a model/provider check is separate from the
allowance mechanism. Web AI needs equivalent Apple auth before enforcing accounts in its deploy.

Local verification and remaining activation blockers: [verification](../../AI_ACCOUNTS_VERIFICATION.md), [setup](../../AI_ACCOUNTS_SETUP.md).
