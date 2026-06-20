# Mealio backend — deployment

The backend is a Flask/WSGI app (`server.py`) that wraps the business logic in
`app.py`. Local dev still uses the stdlib server in `app.py`; production uses
gunicorn via `server.py`.

## Run locally

```bash
cd smartmarket/smartmarket-backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export GROQ_API_KEY=gsk_...        # required
export APP_API_KEY=                # optional; blank = auth disabled (dev only)

# Option A — stdlib dev server (no gunicorn needed)
python app.py

# Option B — production server locally
gunicorn server:app --workers 1 --threads 4 --timeout 120 --bind 0.0.0.0:5000
```

Health check: `curl localhost:5000/api/health`

## Deploy to Render (recommended)

1. Push this repo to GitHub.
2. In Render → **New +** → **Blueprint** → select the repo. Render reads
   `render.yaml` and provisions the `mealio-backend` web service.
3. In the service's **Environment** tab, set the secrets (they are `sync: false`,
   so they are NOT in the repo):
   - `GROQ_API_KEY` — your Groq key.
   - `APP_API_KEY` — a random string, e.g. `openssl rand -hex 32`.
     **Strongly recommended for production** so only your app can call the API.
4. Deploy. Render gives you a URL like `https://mealio-backend.onrender.com`.
5. Verify: `curl https://<your-url>/api/health` → `{"status":"ok",...}`.

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
- **1 worker, 4 threads**: keeps the in-process scraper caches (`_RIMI_CACHE`,
  `_CATALOG_CACHE`) shared. If you scale to multiple workers/instances, move
  those caches + the rate limiter to Redis.
- **Deals data**: products come from the curated `deals_data.json` feed (edit it
  weekly — no scraping). Nutrition is enriched from **Open Food Facts** (by
  barcode, then name) with category-average fallback; results cache to
  `off_cache.json`. Prefer adding a `barcode` to curated items for exact,
  reliable nutrition (name search is fuzzier and OFF rate-limits it).
- Alternative hosts: the `Dockerfile` runs anywhere (Fly.io, Cloud Run, a VPS).
  `Procfile` works on Railway/Heroku-style platforms.
