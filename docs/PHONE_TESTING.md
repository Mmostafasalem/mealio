# Testing on a free Apple Personal Team

## Verified 2026-11-06

- iPhone 15 Pro, iOS 26.6.1: paired over USB, Developer Mode enabled.
- The owner signed in to Xcode and explicitly approved device registration and
  development provisioning updates.
- The production entitlement set could not be provisioned: Apple's Personal
  Team does not support this app's iCloud and Sign in with Apple capabilities.
- A separate **Debug-only** copy, `com.mostafa.mealio.phonetest`, was signed and
  installed. The signature verified and its profile includes the connected phone.
- The first launch was blocked by the device's trust requirement; after the owner
  trusted the developer, they confirmed the app was working.
- This profile expires **2026-11-13 at 16:48 UTC**. Rebuild/reinstall to renew it.

## Scope

This copy supports testing the full mascot icon, onboarding, navigation, local
food tracking, shopping/cart flows, maps, settings and local meal suggestions.
iCloud sync and Apple AI sign-in are unavailable. The sync toggle is disabled,
service calls stop before using CloudKit or starting Apple authentication, and
the profile explains the limitation. No production personal AI quota is claimed.
The separate app identifier isolates its data from the production app.

Production `Mealio.entitlements`, bundle identifier and normal build settings are
retained. Only the test build invocation supplies the alternate entitlement file,
identifier and compile condition. A compiler error prevents a Release build from
using `MEALIO_LOCAL_PHONE_TEST`.

## Reproduce after connecting and unlocking the phone

Use the current phone identifiers from `xcrun devicectl list devices` and
`xcrun xctrace list devices`. Prefix these tools with the DEVELOPER_DIR below.
Sign in through Xcode Settings, never through a chat or a committed credential.

```bash
MEALIO_PHONE_UDID='the UDID from xctrace'
MEALIO_DEVICE_ID='the identifier from devicectl'
python3 -c 'import plistlib; plistlib.dump({}, open("/tmp/MealioPersonalTeam.entitlements", "wb"))'

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project smartmarket.xcodeproj -scheme smartmarket -configuration Debug \
  -destination "id=$MEALIO_PHONE_UDID" \
  -derivedDataPath /tmp/MealioLocalPhoneBuild \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  CODE_SIGN_ENTITLEMENTS=/tmp/MealioPersonalTeam.entitlements \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG MEALIO_LOCAL_PHONE_TEST' \
  PRODUCT_BUNDLE_IDENTIFIER=com.mostafa.mealio.phonetest build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl \
  device install app --device "$MEALIO_DEVICE_ID" \
  /tmp/MealioLocalPhoneBuild/Build/Products/Debug-iphoneos/smartmarket.app

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl \
  device process launch --device "$MEALIO_DEVICE_ID" com.mostafa.mealio.phonetest
```

The provisioning flags change Apple developer-account resources and are included
here because the owner explicitly approved them for this phone-testing setup.
On first launch, trust the developer in the phone's General → VPN & Device
Management settings if iOS requests it.

## Evidence

- Signed build: `/tmp/MealioLocalPhoneBuild.log` — succeeded without warnings/errors.
- Installation result: `/tmp/MealioPhoneInstall.json` — installed successfully.
- Local-only guard regression: `/tmp/MealioLocalPhoneGuardTests.xcresult` — 1 passed.
- Ordinary production Release build: `/tmp/MealioProductionAfterPhoneTest.log` —
  succeeded without warnings/errors; strict bundle/configuration check passed.
- Real-device launch confirmation is from the owner; full physical-device,
  VoiceOver, sync, Apple authentication and release signoff are not implied.

Apple's free-team testing limits:
https://developer.apple.com/help/account/basics/about-your-developer-account
