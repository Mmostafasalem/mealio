#!/usr/bin/env bash
#
# verify-auth.sh — confirm the shared API key is actually enforced on every
# network surface AFTER you've set it (see ../ACTIVATE_AUTH.md).
#
# The key is NEVER stored by this script. Pass it in for this one run:
#
#   MEALIO_API_KEY='your-key' ./scripts/verify-auth.sh
#
# Optional overrides:
#   BACKEND_URL   (default: https://mealio-backend-17qg.onrender.com)
#   WEB_URL       (default: https://web-ecru-nu-uyk5a9nlwp.vercel.app)
#
set -u

BACKEND_URL="${BACKEND_URL:-https://mealio-backend-17qg.onrender.com}"
WEB_URL="${WEB_URL:-https://web-ecru-nu-uyk5a9nlwp.vercel.app}"
KEY="${MEALIO_API_KEY:-}"

pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
note() { printf '  \033[33m··\033[0m   %s\n' "$1"; }

# HTTP status of a GET, with optional X-API-Key header.
code() { # $1=url  $2=key(optional)
  if [ -n "${2:-}" ]; then
    curl -s -o /dev/null -w '%{http_code}' -H "X-API-Key: $2" "$1"
  else
    curl -s -o /dev/null -w '%{http_code}' "$1"
  fi
}

if [ -z "$KEY" ]; then
  echo "MEALIO_API_KEY not set. Run: MEALIO_API_KEY='your-key' $0" >&2
  exit 2
fi

echo "Backend: $BACKEND_URL"
echo "Web:     $WEB_URL"
echo

echo "1) Backend rejects requests WITHOUT a key"
c=$(code "$BACKEND_URL/api/health")
[ "$c" = "401" ] && ok "no key → 401" \
  || bad "no key → $c (expected 401; is APP_API_KEY set on Render yet?)"

echo "2) Backend accepts the correct key"
c=$(code "$BACKEND_URL/api/health" "$KEY")
[ "$c" = "200" ] && ok "correct key → 200" \
  || bad "correct key → $c (expected 200; key mismatch or backend down?)"

echo "3) Backend rejects a WRONG key"
c=$(code "$BACKEND_URL/api/health" "definitely-not-the-key")
[ "$c" = "401" ] && ok "wrong key → 401" \
  || bad "wrong key → $c (expected 401)"

echo "4) Web proxy works WITHOUT a client key (server injects it)"
c=$(code "$WEB_URL/api/backend/health")
[ "$c" = "200" ] && ok "proxy /api/backend/health → 200" \
  || bad "proxy → $c (expected 200; is APP_API_KEY set on Vercel + redeployed?)"

echo "5) Web proxy response does not leak the key"
body=$(curl -s "$WEB_URL/api/backend/health")
if printf '%s' "$body" | grep -qF "$KEY"; then
  bad "the key appears in the proxy response body!"
else
  ok "key not present in proxy response"
fi

echo
note "iOS can't be checked here — it's a built app. Finish by hand:"
note "  .claude/skills/run-mealio/driver.sh run --home"
note "  → deals + meal plan load with NO 401 in the Xcode console."
echo
printf 'Result: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
