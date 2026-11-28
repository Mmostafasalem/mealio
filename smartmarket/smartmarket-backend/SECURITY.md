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
  explicitly `0` or `1`, `TRUSTED_PROXY_COUNT` is set (1 to 10), and, when AI is
  enabled, `GROQ_API_KEY` and durable account storage are valid. Without `MEALIO_ENV=production` (local dev,
  tests) a missing `APP_API_KEY` disables the key check and logs a warning.
- **Online AI accounts** (only when `AI_ACCOUNTS_ENABLED=1`): the AI routes the
  app calls (`/api/agent-chat`, `/api/recipe`) need a Bearer session from Sign in
  with Apple or opt-in guest access (`AI_GUEST_ENABLED=1`, 5 new guests per
  network per day; an IPv6 network is its /64). Each account has a daily credit
  allowance (1 per request) plus a shared daily attempt ceiling
  (`AI_GLOBAL_DAILY_ATTEMPTS`). Guest requests also count against a smaller
  guest pool inside that ceiling (`AI_GUEST_GLOBAL_DAILY_ATTEMPTS`, default a
  quarter of it), so guests cannot use up the capacity signed-in people rely on.
  - **Retired AI routes:** `/api/meal-plan`, `/api/gap-fillers`,
    `/api/shopping-advice` and `/api/workout` are no longer called by the app
    (it builds these on the phone). They answer `410 Gone` before any session or
    credit check unless `LEGACY_AI_ROUTES=1` is set.
  - Transport or provider errors are refunded in full. If the provider answered
    but its output failed validation, 1 credit is kept (the provider call was
    paid for), so one account cannot drain the shared ceiling for free.
  - **No AI response is stored.** For an `Idempotency-Key` request the account
    database keeps only a hash of the key and a keyed fingerprint of the input,
    for 24 h (deleted earlier with the account). A repeat of a finished key gets
    `409 ai_request_repeated` ("already processed"): it is not rerun, not charged
    and not replayed. A repeat while the first is still running gets the same
    code with a "still being processed" message. A failed request releases its
    key so the client can retry with it, and so does a request whose worker died
    before finishing (once its 3-minute reservation has expired and been
    refunded). On startup the service erases any response body an older version
    stored.
  - Response headers say which case happened: `X-AI-Result` is `online`,
    `fallback`, `cached` or `cached-online`. A `fallback` also has
    `X-AI-Fallback: unusable-output` (the provider answered but its output
    failed validation: a 200 with the on-device-style fallback body, 1 credit
    kept) or `provider-error` (nothing kept). `X-AI-Request-Key: released` means
    the key was released: a retry with it is a new request that calls the
    provider again and, if the output is unusable again, keeps another credit.
    Clients should not retry an `unusable-output` fallback automatically.
  - **Recipe cache:** the only AI output held anywhere. It is in process memory
    only, keyed by (account, meal name) so one account never receives another's
    recipe, capped at 500 entries, cleared for an account when it is deleted and
    lost on restart. A request without a known account is never cached.
  - **Apple re-check:** an Apple account is checked with Apple once a day. Only
    Apple's `invalid_grant` answer deletes the account and its sessions. Any
    other answer (another 400 error, a 5xx, a network failure) is a 503 and
    deletes nothing; in that case the session keeps working until 72 h after its
    last successful check, and Apple is asked again at most every 5 minutes.
    If Apple sign-in is switched off (`AI_APPLE_ENABLED=0`) while Apple accounts
    exist, their AI requests get a 503 once the daily check is due. Sign-out and
    account deletion need only a valid session, so they work during an Apple
    outage; with Apple sign-in off, deletion erases the account without revoking
    the grant at Apple.
  - **Sign-in challenges** (unauthenticated): at most 10 live per client network
    (a newer one replaces that network's oldest) and 10,000 in total, each for
    5 minutes. The network is stored as a keyed hash, never the address.
  - Apple server-to-server deletion/revocation notifications are signature
    checked; `event_time` is accepted in seconds or milliseconds.
- **Abuse protection:** rate limiting of 60 req/min per network (one IPv4
  address or one IPv6 /64), `OPTIONS` requests included, with stale-bucket
  eviction; 256 KB request-body cap (413). The client IP comes from
  `X-Forwarded-For` counted from the right by `TRUSTED_PROXY_COUNT`, which
  `render.yaml` sets to 1 and production requires to be set. That value still
  has to be confirmed once against a live request; see DEPLOY.md.
- **Input clamps** (bound prompt size and Groq cost; client fields are data,
  never instructions):
  - chat: message and history turns are capped at 2000 chars, history at 6 turns,
    and goal at 20 chars.
  - the next three apply only with `LEGACY_AI_ROUTES=1`.
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
  `Referrer-Policy: no-referrer`, `Cache-Control: no-store`. No CORS headers are
  sent: the only client is the iOS app, so no web page is allowed to read
  responses.
- **Status routes:** `/api/health` and `/api/readiness` answer with booleans and
  counts only. They do not name the AI model or the settings that are missing;
  those names go to the server log and to `python release_config.py`.
- **Container:** the Docker image runs as an unprivileged user (uid 10001) and
  leaves the tests out.
- **Open Food Facts:** the server looks products up by barcode only, never by
  name, and identifies itself as `Nourlo/1.0 (nourlo.app.support@gmail.com)`.
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
