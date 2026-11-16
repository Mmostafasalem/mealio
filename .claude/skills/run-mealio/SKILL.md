---
name: run-mealio
description: Build, launch, screenshot, and drive Mealio — the SwiftUI iOS app (the `smartmarket` Xcode target) and its Flask backend. Use when asked to run, start, build, test, launch, or screenshot Mealio / the smartmarket app, or to confirm an iOS change works in the running simulator.
---

# Run Mealio

Mealio is a **SwiftUI iOS app** (Xcode target/folder `smartmarket`, product name Mealio)
plus a **Flask backend** in `smartmarket/smartmarket-backend`. It runs **only on macOS with
Xcode** — there is no Linux path for the iOS side.

You drive it with **`xcrun simctl`** (the iOS simulator is the "button-clicker" — the iOS
analogue of `chromium-cli`) wrapped by the committed driver. All paths below are relative to
the repo root.

**Everything goes through the driver:** `.claude/skills/run-mealio/driver.sh`. It sets the
one thing that trips everyone up (`DEVELOPER_DIR`) for you.

## Prerequisites
- **Full Xcode** at `/Applications/Xcode.app` (not just Command Line Tools) and an **iPhone 17**
  simulator (any recent iPhone; override with `MEALIO_SIM="iPhone 17 Pro"` if that exact name is gone).
- Backend deps (idempotent — usually already present):
  ```bash
  python3 -m pip install -q -r smartmarket/smartmarket-backend/requirements.txt pytest
  ```

## Run (agent path — start here)

```bash
# compile for the simulator — expect: ** BUILD SUCCEEDED **, 0 errors / 0 warnings
.claude/skills/run-mealio/driver.sh build

# build → boot sim → install → launch → screenshot. --home skips onboarding so it
# lands on the dashboard (omit --home to see the first-run Welcome flow instead).
.claude/skills/run-mealio/driver.sh run --home
#   → prints:  📸 /tmp/mealio-run/run.png   ← open/read this to see the app

# grab another screenshot of whatever's on screen right now
.claude/skills/run-mealio/driver.sh shot verify      # → /tmp/mealio-run/verify.png
```

After `run`, **read the PNG it prints** — the first frame after launch is black, so the driver
already waits before shooting. If it still looks black, run `shot` again (see Gotchas).

## Backend (agent path)

```bash
# starts the Flask app (stub keys, no network), polls until ready, curls health, stops it
.claude/skills/run-mealio/driver.sh backend
#   → 401 without X-API-Key, then 200 + {"status":"ok",...} with it

# backend unit tests
.claude/skills/run-mealio/driver.sh test             # → 12 passed
```

## Run (human path)
Open `smartmarket.xcodeproj` in Xcode, pick an iPhone simulator, press ▶. Useless for
headless/agent work — it just opens a window and waits.

## Gotchas (the battle scars)
- **`DEVELOPER_DIR` is mandatory.** `xcode-select` points at the Command Line Tools, so a bare
  `xcodebuild` or `xcrun simctl` fails with *"unable to find utility simctl"* / build errors.
  The driver exports `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; do the same for
  any ad-hoc `xcrun`/`xcodebuild` you run outside it.
- **Inline SourceKit errors are noise.** "Cannot find type 'Deal'/'Constants'/'Spacing'" from
  single-file indexing are NOT real — they resolve at whole-module compile. Trust `driver.sh build`.
- **The `AppIntents.framework` "warning" is toolchain noise**, not a code warning — the driver
  filters it so `build` output is clean when the code is clean.
- **You cannot script-tap the iOS system dialogs.** `osascript` has no assistive access here, and
  `simctl` has no tap command. So the location-permission prompt would sit on top of the UI —
  the driver pre-grants it (`simctl privacy … grant location`) before launching. For the same
  reason you can't click through onboarding; use `run --home` to seed it complete instead.
- **First frame after launch is black.** Screenshotting immediately gives an all-black PNG. The
  driver settles with `xcrun simctl spawn "$SIM" sleep 4` first — a *guest* sleep, because a bare
  host `sleep` can be blocked in agent shells and doesn't actually wait for the app to render.
- **`--home` onboarding skip** works by `simctl spawn "$SIM" defaults write com.mostafa.mealio
  hasCompletedOnboarding -bool YES` (+ `hasSeenWelcome`); the app reads these at launch. On a
  truly fresh install without `--home` you'll land on the Welcome screen, not the dashboard.
- **Backend startup races curl.** Flask's dev server needs a second or two to bind — the driver
  polls `/api/health` up to 15× instead of a fixed sleep (a fixed 2s sleep returned `000`).
- **Working directory drifts between separate shell calls** in this environment — the driver
  resolves the repo root from its own location, so invoke it by path from anywhere.

## Troubleshooting
| Symptom | Fix |
|---|---|
| `xcodebuild: unable to find utility "simctl"` | You dropped `DEVELOPER_DIR`. Use the driver, or export it. |
| `run.png` is solid black | Launch frame; `driver.sh shot again` after a moment. |
| `backend` prints `000` then empty | Server hadn't bound yet — the driver's poll handles this; if it persists, check `/tmp/mealio-backend.log`. |
| `Unable to boot device … Shutdown` / `code 405` | Harmless (already booted) OR the sim was shut down — the driver re-boots + `open -a Simulator`. |
| Build fails on a renamed simulator | `MEALIO_SIM="iPhone 17 Pro" .claude/skills/run-mealio/driver.sh run` |

## Facts
- Project `smartmarket.xcodeproj` · scheme `smartmarket` · bundle id `com.mostafa.mealio`
- Backend: `smartmarket/smartmarket-backend` (`python3 app.py` runs the same Flask app gunicorn serves in prod)
- Screenshots land in `/tmp/mealio-run/` (override with `MEALIO_SHOTS`).
