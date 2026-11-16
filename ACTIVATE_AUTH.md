# Activating API-Key Auth (all three surfaces)

Current local status (2026-11-06): a strong app key is prepared in the gitignored
iOS configuration and matching private backend .env. Values were not displayed.
Hosting activation is still pending. Do not regenerate or paste the key into chat.
Transfer it privately through the hosting dashboards, then run
scripts/verify-auth.sh (masked prompt). Older generation examples below are for
new installations, not an instruction to rotate the prepared key.

The same secret goes in **three** places and must match exactly:

| Surface | Where the value lives | How it's used |
|---|---|---|
| Backend (Render) | env var `APP_API_KEY` | server enables auth; compares incoming `X-API-Key` (timing-safe) |
| iOS app | `smartmarket/Secrets.xcconfig` → `API_KEY` | injected into Info.plist at build; sent as `X-API-Key` |
| Web app (Vercel) | env var `APP_API_KEY` (server-only) | proxy injects `X-API-Key`; browser never sees it |

> While `APP_API_KEY` is unset on the backend, auth is **disabled** (everything
> returns 200 without a key). Auth only actually turns on once the backend var is
> set. Set the backend **last** so the other two are ready when it flips on.

## 0. Generate one strong shared key (once)

```bash
openssl rand -base64 32
```

Copy this value. It's the same string for all three steps below. Keep it in a
password manager, not in shell history or a repo file.

## 1. iOS — `smartmarket/Secrets.xcconfig` (gitignored, already wired)

The file exists and is referenced as the base config on both Debug and Release;
Info.plist already reads `$(API_KEY)`. Just fill the value. **One exact line:**

```
API_KEY = PASTE_THE_KEY_HERE
```

Edit it without going through shell history:

```bash
# opens the gitignored file in your editor; paste the key after "API_KEY = "
open -a TextEdit smartmarket/Secrets.xcconfig     # or: $EDITOR smartmarket/Secrets.xcconfig
```

Confirm it's still ignored (must print the path):

```bash
git check-ignore smartmarket/Secrets.xcconfig
```

Then a clean build so the value is baked into Info.plist:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project smartmarket.xcodeproj -scheme smartmarket -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean build CODE_SIGNING_ALLOWED=NO
```

## 2. Web — Vercel env var (server-side only)

The proxy reads `process.env.APP_API_KEY`. Add it for production (the CLI prompts
for the value interactively, so it's not stored in your shell history):

```bash
cd web
vercel env add APP_API_KEY production
#   → paste the key at the prompt

# BACKEND_URL is only needed if you ever move off the default Render URL:
# vercel env add BACKEND_URL production   # value: https://mealio-backend-d7aa.onrender.com

# env vars only take effect on a new deployment:
vercel --prod --yes
```

Verify it's set (shows the var exists, not its value):

```bash
vercel env ls
```

## 3. Backend — Render env var (set this LAST)

`render.yaml` declares `APP_API_KEY` with `sync: false`, so it must be set in the
dashboard (never committed):

1. Render dashboard → service **mealio-backend** → **Environment**.
2. **Add Environment Variable** → Key `APP_API_KEY`, Value = the key from step 0.
3. Save. Render auto-redeploys. Wait for the deploy to go green.
4. (Optional, same screen) confirm `GROQ_API_KEY` is still set.

## 4. Verify — don't trust "done"

Run the checker against the live surfaces. It never stores the key — you pass it
in for this one command only:

```bash
MEALIO_API_KEY='PASTE_THE_KEY_HERE' ./scripts/verify-auth.sh
```

It checks:
- Backend **without** a key → **401** (proves auth is now enforced).
- Backend **with** the key → **200**.
- Web proxy `/api/backend/health` (no client key) → **200** (proves server-side injection).
- The web proxy response does not echo the key.

Then finish the **iOS** check by hand (can't be curled — it's a built app):
1. Run the app in the simulator (`.claude/skills/run-mealio/driver.sh run --home`).
2. Confirm the Home deals + a meal-plan generation load with **no 401** (watch the
   Xcode console / `appLog`). If the key is wrong you'll see the offline fallback
   kick in and `validateResponse` throwing 401.

All four green = auth is genuinely active on every surface.

## Rotating / revoking

Change the value in all three places (steps 1–3) and redeploy web + rebuild iOS.
Because it's one shared secret, rotating invalidates every client at once — see
`smartmarket/smartmarket-backend/SECURITY.md` for the per-device-token plan that
replaces this.
