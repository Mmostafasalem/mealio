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
# "connected" is a cabled phone; "available (paired)" is one reachable over Wi-Fi.
# (|| true: with pipefail a non-matching grep would end the script before the message below.)
DEVICE=$(xcrun devicectl list devices 2>/dev/null | grep -E ' (connected|available \(paired\)) ' | grep -i iphone \
  | grep -Eo '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1 || true)
[ -n "$DEVICE" ] || { echo "No connected iPhone (unlock it and check the cable)."; exit 1; }
UDID=$(xcodebuild -project smartmarket.xcodeproj -scheme smartmarket -showdestinations 2>/dev/null | sed -n 's/.*platform:iOS, arch:arm64, id:\([^,]*\),.*/\1/p' | head -1 || true)
[ -n "$UDID" ] || { echo "xcodebuild does not see the phone."; exit 1; }

# The phone-test profile and the signing identity.
COND='SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG MEALIO_LOCAL_PHONE_TEST'
SIGNED="$OUT/Build/Products/Debug-iphoneos/smartmarket.app"

# 1. Full build: Xcode signs the app and its widget extension with profiles that
#    include Apple Health and the shared App Group. Needs an Apple account in
#    Xcode > Settings > Accounts (the free Personal Team is enough).
if xcodebuild -project smartmarket.xcodeproj -scheme smartmarket -configuration Debug \
     -destination "id=$UDID" -derivedDataPath "$OUT" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
     MEALIO_BUNDLE_ID=$BUNDLE MEALIO_APP_ENTITLEMENTS=smartmarket/PhoneTest.entitlements "$COND" \
     build > "$OUT.log" 2>&1; then
  echo "** BUILD SUCCEEDED ** (signed by Xcode: Apple Health and widgets included)"
  APP="$SIGNED"
else
  grep -E "error:" "$OUT.log" | sort -u | head -5
  echo "Falling back to the existing profile: no widgets and no Apple Health on this install."
  echo "To include them, sign in at Xcode > Settings > Accounts, then run this again."

  # 2. Fallback: the existing phone-test profile (no Health / App Group), signed by hand.
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
    "$COND" MEALIO_BUNDLE_ID=$BUNDLE build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u

  APP="$SIGNED"
  # The widget needs its own profile and the App Group; leave it out of this install.
  rm -rf "$APP/PlugIns/NourloWidgets.appex"
  security cms -D -i "$PROFILE" > "$OUT/profile.plist"
  /usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$OUT/profile.plist" > "$OUT/sign.entitlements"
  cp "$PROFILE" "$APP/embedded.mobileprovision"
  for lib in "$APP"/*.dylib; do [ -f "$lib" ] && codesign -f -s "$IDENTITY" "$lib" >/dev/null 2>&1; done
  codesign -f -s "$IDENTITY" --entitlements "$OUT/sign.entitlements" "$APP" >/dev/null 2>&1
fi
codesign --verify --deep --strict "$APP" && echo "Signature verified"

xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 | grep -i -E "error|installationURL" | head -3
xcrun devicectl device process launch --terminate-existing --device "$DEVICE" $BUNDLE 2>&1 | tail -1
