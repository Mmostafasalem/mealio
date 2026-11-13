# Nourlo — Security model

## What's implemented (verified)
- **Transport:** HTTPS only. iOS App Transport Security is at its default (no
  exceptions), so cleartext is blocked.
- **App key:** shared API key in the `X-API-Key` header for catalog/utility
  routes (`/api/health`, `/api/products`, `/api/deals`, `/api/bmr`,
  `/api/readiness`). The backend compares it to `APP_API_KEY` with
  `hmac.compare_digest` (constant time). `/healthz` is public liveness only and
  returns no data.
- **Auth and environment:** the key check runs only when `APP_API_KEY` is set.
  Deployed servers fail closed: the `Dockerfile`, `Procfile` and `render.yaml`
  all set `MEALIO_ENV=production`, and in that mode `server.py` refuses to start
  unless `APP_API_KEY` is a real key (32+ chars), `AI_ACCOUNTS_ENABLED` is
  explicitly `0` or `1`, and, when AI is enabled, `GROQ_API_KEY` and durable
  account storage are valid. Without `MEALIO_ENV=production` (local dev,
  tests) a missing `APP_API_KEY` disables the key check and logs a warning.
- **Online AI accounts** (only when `AI_ACCOUNTS_ENABLED=1`): AI routes
  (`/api/meal-plan`, `/api/agent-chat`, `/api/recipe`, `/api/gap-fillers`,
  `/api/shopping-advice`) need a Bearer session from Sign in with Apple or
  opt-in guest access (`AI_GUEST_ENABLED=1`, 5 new guests per network per day).
  Each account has a daily credit allowance (meal plan 5, other requests 1) plus
  a shared daily attempt ceiling (`AI_GLOBAL_DAILY_ATTEMPTS`).
  - Transport or provider errors are refunded in full. If the provider answered
    but its output failed validation, 1 credit is kept (the provider call was
    paid for), so one account cannot drain the shared ceiling for free.
  - `Idempotency-Key` requests are not rerun or charged twice. A failed request
    releases its key so the client can retry with it.
  - Apple server-to-server deletion/revocation notifications are signature
    checked; `event_time` is accepted in seconds or milliseconds.
- **Abuse protection:** per-IP rate limiting (60 req/min) with stale-bucket
  eviction; 256 KB request-body cap (413). The client IP comes from
  `X-Forwarded-For` counted from the right (`TRUSTED_PROXY_COUNT`, default 1);
  see DEPLOY.md.
- **Input clamps** (bound prompt size and Groq cost; client fields are data,
  never instructions):
  - chat: message and history turns are capped at 2000 chars, history at 6 turns,
    and goal at 20 chars.
  - meal plan: `goal` is allowlisted (`lose`/`maintain`/`gain`, anything else
    becomes `maintain`); favourite foods ≤50, dietary/allergy entries ≤30,
    grocery names ≤100 items × 160 chars, stock ≤100 validated items.
  - gap fillers: calories are coerced to integers in 0–10000 and macro gaps to
    finite numbers in −1000–1000.
  - shopping advice: budget is a finite number in 0–10000; the grocery list
    is reduced to ≤100 item names × 160 chars.
  - recipe name ≤120 chars. Non-numeric or overflowing numbers (`1e999`) give
    a 400 or a default value, never a 500.
- **Errors:** HTTP errors keep their status in the JSON `{"error": ...}` shape
  (for example, 404 and 405 with `Allow`). Only unexpected crashes become a
  generic 500, and their details stay in the server logs.
- **Headers:** `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
  `Referrer-Policy: no-referrer`, `Cache-Control: no-store`.
- **Secrets:** `GROQ_API_KEY` / `APP_API_KEY` / Apple and account secrets come
  from the environment only; `.env` is gitignored. No secrets or request bodies
  are logged, and Flask debug is off in production (gunicorn).

## Known limitation
The shared API key **ships inside the app binary** and can be extracted from the
IPA. It gates casual abuse of the catalog routes. It is **not** per-user
identity. Per-user limits for AI come from the account sessions above.

> Deployment gotcha: if `APP_API_KEY` is set on the server but `Info.plist`'s
> `API_KEY` is empty or mismatched, every key-protected request returns 401. Set them
> together and rotate both if the key leaks.
