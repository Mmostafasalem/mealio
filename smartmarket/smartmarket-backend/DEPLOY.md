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
- When `AI_ACCOUNTS_ENABLED=1`: `GROQ_API_KEY` is a real Groq key (`gsk_...`)
  and durable account storage is configured and reachable (`AI_DATABASE_URL`
  Postgres, or `AI_STATE_DB` + `AI_STATE_PERSISTENT=1` on a persistent volume),
  plus the Apple and account secrets listed in `.env.example`.

`GROQ_API_KEY` is **not** required while `AI_ACCOUNTS_ENABLED=0`.

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
4. Deploy. Render gives you a URL like `https://mealio-backend.onrender.com`.
5. Verify: `curl https://<your-url>/healthz` → `{"status":"ok"}`, then
   `curl -H "X-API-Key: <key>" https://<your-url>/api/readiness`.

### Verify TRUSTED_PROXY_COUNT (do this once)

Per-IP rate limiting reads the client IP from `X-Forwarded-For`, counting
`TRUSTED_PROXY_COUNT` entries from the right (default `1`, assumed for Render).
If the value is wrong, clients can spoof their IP (too low) or everyone shares
one proxy IP (too high). Check it against a real Render request: temporarily log
`request.headers.get("X-Forwarded-For")` and `request.remote_addr`, call the
service from a network whose public IP you know, and confirm that your IP is
the entry at position `len - TRUSTED_PROXY_COUNT`. Set `TRUSTED_PROXY_COUNT` if
it differs, then remove the log line.

### Point the iOS app at it

In `smartmarket/Info.plist`:
- `API_BASE_URL` → your Render URL (already defaulted to
  `https://mealio-backend.onrender.com` — update if your service name differs).
- `API_KEY` → the same value you set for `APP_API_KEY` on Render.

> For real releases, inject `API_KEY` via a **gitignored xcconfig** instead of
> committing it to `Info.plist`.

## Notes / caveats

- **Free tier sleeps** after inactivity; the first request after idle takes
  ~30–60s to cold-start. The app's 60s meal-plan timeout covers this, but
  consider a paid instance or a cron ping for production.
- **1 worker, 4 threads**: keeps the in-process caches (catalog, recipe LRU,
  idempotent-response replay) and the per-IP rate limiter shared. If you scale
  to multiple workers or instances, move the rate limiter to shared storage. AI
  quotas already live in the account database.
- **Deals data**: products come from the curated `deals_data.json` feed (edit it
  weekly; there is no scraping and no scraper cache). Nutrition is enriched from
  **Open Food Facts** (by barcode, then name) with category-average fallback;
  results cache to `off_cache.json`. Prefer adding a `barcode` to curated items
  for exact, reliable nutrition (name search is fuzzier and OFF rate-limits it).
- Alternative hosts: the `Dockerfile` runs anywhere (Fly.io, Cloud Run, a VPS).
  `Procfile` works on Railway/Heroku-style platforms. Both default to
  `MEALIO_ENV=production`.
