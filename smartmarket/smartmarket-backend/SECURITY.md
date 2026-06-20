# Mealio — Security model

## What's implemented (verified)
- **Transport:** HTTPS only. iOS App Transport Security is at its default (no
  exceptions), so cleartext is blocked.
- **Auth:** shared API key in the `X-API-Key` header. The iOS app reads it from
  `Info.plist` (`API_KEY`); the backend compares it to `APP_API_KEY` using
  `hmac.compare_digest` (constant-time, no timing leak). Auth is enforced on
  every route when `APP_API_KEY` is set.
- **Abuse protection:** per-IP rate limiting (60 req/min) with stale-bucket
  eviction; 256 KB request-body cap (413); input clamps on all AI handlers
  (message/history/list sizes) to bound prompt size and Groq cost.
- **Headers:** `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
  `Referrer-Policy: no-referrer`, `Cache-Control: no-store`.
- **Secrets:** `GROQ_API_KEY` / `APP_API_KEY` from env only; `.env` gitignored;
  no secrets in source or logs; Flask debug off in production (gunicorn).

## Known limitation
The shared API key **ships inside the app binary** and can be extracted from the
IPA. It gates casual abuse but is **not** per-user identity or strong protection.

## Upgrade path to per-device tokens (requires a datastore)
The backend is currently stateless, so true per-device auth needs persistence:

1. **Add a datastore** (Postgres or Redis on Render).
2. **Device registration:** on first launch the app calls `POST /api/register`;
   the server issues a random opaque token (or registers a device-generated
   public key), stores it, and returns it. The app saves it in the **Keychain**
   (not UserDefaults) and sends it as `X-Device-Token` thereafter.
3. **Validation & revocation:** validate the token against the store on each
   request; support per-device rate limits and revocation.
4. **Optional hardening:** Apple **App Attest / DeviceCheck** to assert the
   request comes from a genuine, unmodified app instance; short-lived signed
   tokens (JWT) to avoid a DB hit per request.

Until then, keep `APP_API_KEY` set on Render and rotate it if leaked.

> Deployment gotcha: if `APP_API_KEY` is set on the server but `Info.plist`'s
> `API_KEY` is empty/mismatched, **every request returns 401**. Set them together.
