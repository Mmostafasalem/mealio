#!/bin/bash
# Build the phone-test copy (com.mostafa.mealio.phonetest), sign it with the
# local development certificate and the existing phone-test provisioning
# profile, then install and launch it on the connected iPhone.
#
# Why not plain xcodebuild signing: when no Apple account is signed in to
# Xcode, automatic signing fails ("No Accounts") and Xcode refuses to use its
# own managed profile manually. Building unsigned and signing by hand works as
# long as the profile is still valid. See docs/PHONE_TESTING.md.
#
# Usage: scripts/install-phone-test.sh        (run from anywhere)
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE=com.mostafa.mealio.phonetest
OUT="${MEALIO_PHONE_BUILD:-/tmp/MealioPhoneTestBuild}"
cd "$ROOT"

# The connected phone, as devicectl and xcodebuild each know it.
DEVICE=$(xcrun devicectl list devices 2>/dev/null | grep -E ' connected ' | grep -i iphone \
  | grep -Eo '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
[ -n "$DEVICE" ] || { echo "No connected iPhone (unlock it and check the cable)."; exit 1; }
UDID=$(xcodebuild -project smartmarket.xcodeproj -scheme smartmarket -showdestinations 2>/dev/null | sed -n 's/.*platform:iOS, arch:arm64, id:\([^,]*\),.*/\1/p' | head -1)
[ -n "$UDID" ] || { echo "xcodebuild does not see the phone."; exit 1; }

# The phone-test profile and the signing identity.
PROFILE=""
for candidate in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision; do
  [ -f "$candidate" ] || continue
  if security cms -D -i "$candidate" 2>/dev/null | grep -q "\.$BUNDLE<"; then PROFILE="$candidate"; fi
done
[ -n "$PROFILE" ] || { echo "No provisioning profile for $BUNDLE. Sign in to Xcode and follow docs/PHONE_TESTING.md."; exit 1; }
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*) \([0-9A-F]\{40\}\) "Apple Development.*/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "No Apple Development signing certificate in the keychain."; exit 1; }

xcodebuild -project smartmarket.xcodeproj -scheme smartmarket -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$OUT" CODE_SIGNING_ALLOWED=NO \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG MEALIO_LOCAL_PHONE_TEST' \
  PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u

APP="$OUT/Build/Products/Debug-iphoneos/smartmarket.app"
security cms -D -i "$PROFILE" > "$OUT/profile.plist"
/usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$OUT/profile.plist" > "$OUT/sign.entitlements"
cp "$PROFILE" "$APP/embedded.mobileprovision"
for lib in "$APP"/*.dylib; do [ -f "$lib" ] && codesign -f -s "$IDENTITY" "$lib" >/dev/null 2>&1; done
codesign -f -s "$IDENTITY" --entitlements "$OUT/sign.entitlements" "$APP" >/dev/null 2>&1
codesign --verify --deep --strict "$APP" && echo "Signature verified"

xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 | grep -i -E "error|installationURL" | head -3
xcrun devicectl device process launch --terminate-existing --device "$DEVICE" $BUNDLE 2>&1 | tail -1
