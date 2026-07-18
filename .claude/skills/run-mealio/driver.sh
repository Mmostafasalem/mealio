#!/usr/bin/env bash
#
# driver.sh — build / launch / drive Mealio (the `smartmarket` iOS target)
# and its Flask backend, from a clean checkout on macOS.
#
# Everything here was run on the machine that produced this skill. iOS apps
# build/run ONLY on macOS with Xcode — there is no Linux path.
#
# The one non-negotiable: xcode-select points at the Command Line Tools, so
# every xcodebuild / xcrun simctl call MUST run under DEVELOPER_DIR pointing at
# the full Xcode, or it fails with "unable to find utility simctl" / xcodebuild
# errors. This script sets it for you.
#
# Usage:
#   ./driver.sh build            # compile for the simulator (0 errors/0 warnings expected)
#   ./driver.sh run [--home]     # build, boot sim, install, launch, screenshot
#                                #   --home seeds onboarding-complete so it lands on the dashboard
#   ./driver.sh shot [name]      # screenshot the current simulator screen
#   ./driver.sh backend          # start the Flask backend (stub keys) and curl /api/health
#   ./driver.sh test             # run the backend pytest suite
#
# Screenshots land in:  $SHOTS  (printed on every shot)

set -uo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# --- resolve repo root (two levels up from this skill dir) -------------------
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SKILL_DIR/../../.." && pwd)"

PROJECT="$REPO/smartmarket.xcodeproj"
SCHEME="smartmarket"
SIM="${MEALIO_SIM:-iPhone 17}"           # override with MEALIO_SIM=... if this name is gone
BUNDLE="com.mostafa.mealio"
BACKEND="$REPO/smartmarket/smartmarket-backend"
SHOTS="${MEALIO_SHOTS:-/tmp/mealio-run}"
mkdir -p "$SHOTS"

# in-simulator sleep — the host `sleep` can be blocked/awkward in agent shells,
# and it doubles as a "wait for the guest to settle" that a host sleep can't.
_settle() { xcrun simctl spawn "$SIM" sleep "${1:-3}" 2>/dev/null || true; }

_boot() {
  xcrun simctl boot "$SIM" 2>/dev/null || true   # error 405 == already booted, harmless
  open -a Simulator
  xcrun simctl bootstatus "$SIM" >/dev/null 2>&1 || true
}

_app_path() {
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$SIM" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{d=$2} / FULL_PRODUCT_NAME/{n=$2} END{print d"/"n}'
}

cmd_build() {
  echo "▸ building $SCHEME for $SIM …"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$SIM" build CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED" \
  | grep -v "AppIntents.framework"   # this one line is Xcode toolchain noise, not a code warning
  return "${PIPESTATUS[0]}"
}

cmd_shot() {
  local name="${1:-shot}"
  local out="$SHOTS/${name}.png"
  xcrun simctl io "$SIM" screenshot "$out" >/dev/null 2>&1
  echo "📸 $out"
}

cmd_run() {
  local home=0; [ "${1:-}" = "--home" ] && home=1
  cmd_build || { echo "build failed — not launching"; return 1; }
  _boot
  local app; app="$(_app_path)"
  echo "▸ installing $app"
  xcrun simctl install "$SIM" "$app" || return 1
  # Pre-grant location so the CLLocationManager prompt doesn't cover the UI.
  # (You CANNOT script-tap the system dialog: osascript has no assistive access.)
  xcrun simctl privacy "$SIM" grant location "$BUNDLE" 2>/dev/null || true
  if [ "$home" = 1 ]; then
    # Skip onboarding so we land on the dashboard. Writing via `simctl spawn
    # defaults` reaches the app's domain; the app reads these at launch.
    xcrun simctl spawn "$SIM" defaults write "$BUNDLE" hasCompletedOnboarding -bool YES 2>/dev/null || true
    xcrun simctl spawn "$SIM" defaults write "$BUNDLE" hasSeenWelcome         -bool YES 2>/dev/null || true
  fi
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  echo "▸ launching $BUNDLE"
  xcrun simctl launch "$SIM" "$BUNDLE"
  _settle 4          # the FIRST frame after launch is black — always settle before the shot
  cmd_shot "run"
}

cmd_backend() {
  echo "▸ backend smoke (stub keys, no network) …"
  # `python3 app.py` runs the same Flask app gunicorn serves in prod (see app.py
  # __main__). Uses flask (already a dep); no gunicorn needed for a local smoke.
  ( cd "$BACKEND" && GROQ_API_KEY=test APP_API_KEY=testkey PORT=5055 \
      python3 app.py >/tmp/mealio-backend.log 2>&1 & echo $! >/tmp/mealio-backend.pid )
  # Flask's dev server takes a couple seconds to bind — poll instead of guessing.
  for _ in $(seq 1 15); do
    curl -sf -o /dev/null -H "X-API-Key: testkey" http://127.0.0.1:5055/api/health && break
    _settle 1
  done
  echo "— GET /api/health (no key → expect 401):"
  curl -s -o /dev/null -w "  %{http_code}\n" http://127.0.0.1:5055/api/health
  echo "— GET /api/health (with key → expect 200):"
  curl -s -H "X-API-Key: testkey" http://127.0.0.1:5055/api/health
  echo
  kill "$(cat /tmp/mealio-backend.pid 2>/dev/null)" 2>/dev/null || true
  pkill -f "python3 app.py" 2>/dev/null || true
}

cmd_test() {
  ( cd "$BACKEND" && GROQ_API_KEY=test APP_API_KEY=testkey python3 -m pytest -q )
}

case "${1:-}" in
  build)   shift; cmd_build "$@" ;;
  run)     shift; cmd_run "$@" ;;
  shot)    shift; cmd_shot "$@" ;;
  backend) shift; cmd_backend "$@" ;;
  test)    shift; cmd_test "$@" ;;
  *) echo "usage: $0 {build|run [--home]|shot [name]|backend|test}"; exit 2 ;;
esac
