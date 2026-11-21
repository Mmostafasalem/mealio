# Nourlo backend — deployment

The backend is a Flask/WSGI app (`server.py`) that wraps the business logic in
`app.py`. `python app.py` runs the same Flask app with Flask's dev server, and
production runs it with gunicorn.

## Run locally

```bash
cd smartmarket/smartmarket-backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export APP_API_KEY=                # optional locally; blank = key check disabled (dev only)
export GROQ_API_KEY=gsk_...        # only needed to exercise online AI locally

# Option A — Flask dev server
python app.py

# Option B — production server locally (leave MEALIO_ENV unset for dev)
gunicorn server:app --workers 1 --threads 4 --timeout 120 --bind 0.0.0.0:5000
```

Health check: `curl localhost:5000/healthz`

Tests: `python -m pytest -q` (no network, Groq or Apple credentials needed).

## Environment and fail-closed startup

`MEALIO_ENV=production` is set by `render.yaml`, the `Dockerfile` and the
`Procfile`. In that mode, `server.py` refuses to start (and `/api/readiness`
returns 503) unless:

- `APP_API_KEY` is a real random key (32+ chars, e.g. `openssl rand -hex 32`).
- `AI_ACCOUNTS_ENABLED` is explicitly `0` (catalog only) or `1`.
- `TRUSTED_PROXY_COUNT` is set to a whole number from 1 to 10. `render.yaml`
  sets it to `1`. On any other host (the `Dockerfile` or `Procfile`), set it
  yourself to the number of proxies in front of the app.
- When `AI_ACCOUNTS_ENABLED=1`: `GROQ_API_KEY` is a real Groq key (`gsk_...`)
  and durable account storage is configured and reachable (`AI_DATABASE_URL`
  Postgres, or `AI_STATE_DB` + `AI_STATE_PERSISTENT=1` on a persistent volume),
  plus the Apple and account secrets listed in `.env.example`.

`GROQ_API_KEY` is **not** required while `AI_ACCOUNTS_ENABLED=0`.

`/api/readiness` answers only `ready` and `onlineAIEnabled` (true or false). To
see which setting is missing, read the server log or run
`python release_config.py` with the same environment; both give names, never
values.

Optional settings:

| Variable | Default | What it does |
|---|---|---|
| `AI_GLOBAL_DAILY_ATTEMPTS` | `900` | Shared daily ceiling on AI provider calls. |
| `AI_GUEST_GLOBAL_DAILY_ATTEMPTS` | a quarter of the ceiling (`225`) | Part of that ceiling guests may use in a day. Must be between 1 and the ceiling. |
| `AI_GUEST_ENABLED` | off | `1` offers guest access. |
| `LEGACY_AI_ROUTES` | off | `1` brings back `/api/meal-plan`, `/api/gap-fillers`, `/api/shopping-advice` and `/api/workout`. Leave it off: the app builds these on the phone, and the routes answer `410 Gone`. |

Without `MEALIO_ENV=production` the server starts with whatever is set. If
`APP_API_KEY` is blank, the key check is disabled and a warning is logged. Use
that only for local development. To run the Docker image locally without
production checks, pass `-e MEALIO_ENV=development`.

## Deploy to Render (recommended)

1. Push this repo to GitHub.
2. In Render → **New +** → **Blueprint** → select the repo. Render reads
   `render.yaml` and provisions the `mealio-backend` web service.
3. In the service's **Environment** tab, set the secrets (they are `sync: false`,
   so they are NOT in the repo):
   - `APP_API_KEY` — required in production, e.g. `openssl rand -hex 32`.
   - `GROQ_API_KEY` — only when you enable online AI (`AI_ACCOUNTS_ENABLED=1`).
4. Deploy. Render gives you a URL like `https://mealio-backend-d7aa.onrender.com`
   (the address the app is built with; see "Point the iOS app at it").
5. Verify: `curl https://<your-url>/healthz` → `{"status":"ok"}`, then
   `curl -H "X-API-Key: <key>" https://<your-url>/api/readiness` →
   `{"ready":true,"onlineAIEnabled":false}`.

### Verify TRUSTED_PROXY_COUNT (do this once)

> **NOT YET DONE — a manual step on the live service.** `render.yaml` sets
> `TRUSTED_PROXY_COUNT=1`, which is an assumption about Render's proxy chain
> that nobody has checked against a real request. Until someone does the check
> below, per-IP limits (rate limiting, the guest sign-up limit, the sign-in
> challenge limit) may be counting the wrong address.

Per-IP rate limiting reads the client IP from `X-Forwarded-For`, counting
`TRUSTED_PROXY_COUNT` entries from the right (`1` in `render.yaml`; production
will not start without a value).
If the value is wrong, clients can spoof their IP (too low) or everyone shares
one proxy IP (too high). Check it against a real Render request: temporarily log
`request.headers.get("X-Forwarded-For")` and `request.remote_addr`, call the
service from a network whose public IP you know, and confirm that your IP is
the entry at position `len - TRUSTED_PROXY_COUNT`. Set `TRUSTED_PROXY_COUNT` if
it differs, then remove the log line.

This only holds while every request reaches the app through those proxies. The
app trusts the hop the last proxy appended; if clients can reach gunicorn
directly (an exposed port, a second host without the proxy), they control the
whole header and can pick any IP, which defeats the per-IP limit. Keep the
service reachable only through the platform proxy.

### Point the iOS app at it

In `smartmarket/Info.plist`:
- `API_BASE_URL` → your Render URL (currently
  `https://mealio-backend-d7aa.onrender.com` — update if your service address differs).
- `API_KEY` → the same value you set for `APP_API_KEY` on Render.

> For real releases, inject `API_KEY` via a **gitignored xcconfig** instead of
> committing it to `Info.plist`.

## Notes / caveats

- **Free tier sleeps** after inactivity; the first request after idle takes
  ~30–60s to cold-start. The app waits long enough for chat and recipes to
  cover this, but consider a paid instance or a cron ping for production.
- **1 worker, 4 threads**: keeps the in-process caches (catalog, recipe LRU)
  and the per-IP rate limiter shared. If you scale to multiple workers or
  instances, move the rate limiter to shared storage (the recipe cache would
  simply be per worker). AI quotas and the no-rerun markers for request keys
  already live in the account database; AI responses are not stored.
- **Deals data**: products come from the curated `deals_data.json` feed (edit it
  weekly; there is no scraping and no scraper cache). Give every item its own
  `nutrition` values. An item without them is looked up on **Open Food Facts**
  by `barcode` only (there is no name search: it returned whatever product
  ranked first), and without a barcode it gets a rough category average.
  Barcode results cache to `off_cache.json`.
- Alternative hosts: the `Dockerfile` runs anywhere (Fly.io, Cloud Run, a VPS).
  `Procfile` works on Railway/Heroku-style platforms. Both default to
  `MEALIO_ENV=production`, so both need `TRUSTED_PROXY_COUNT` set. The image
  runs as an unprivileged user (uid 10001) and does not contain the tests; a
  volume for `AI_STATE_DB` must be writable by that user.
