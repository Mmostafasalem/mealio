# iOS unit tests

The shared `smartmarket` scheme now includes native `smartmarketTests` and
`smartmarketUITests` targets. Unit tests cover BMR, portion descriptions, cart
deletion sync, food-log deletion and the online AI consent boundary. UI tests
cover onboarding, tab navigation and offline in-app privacy/support access.

## Run
Open the project in Xcode, select `smartmarket`, choose a simulator and press
**⌘U**, or run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project smartmarket.xcodeproj -scheme smartmarket \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

Use a dedicated test simulator: onboarding tests overwrite its app profile with
synthetic inputs. They do not require Apple login, iCloud or live Groq access.
Local ad-hoc simulator signing supplies the simulated application entitlements
needed to exercise Keychain persistence; compile-only checks can remain unsigned.
Sync model regressions also run independently with `swift test --disable-sandbox`.
