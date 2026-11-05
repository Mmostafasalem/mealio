# iOS unit tests

The shared `smartmarket` scheme now includes native `smartmarketTests` and
`smartmarketUITests` targets. Unit tests cover BMR, portion descriptions, cart
deletion sync, food-log deletion, online AI consent and map-location integrity.
UI tests cover onboarding, all tabs, largest text, landscape, navigation visibility,
44-point metric-info targets and offline in-app privacy/support access.

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
Sync model regressions also run independently:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox
python3 -m unittest discover -s scripts -p 'test_ios_*.py' -v
```

The Python checks validate release packaging and Mealio's current privacy
declarations. After building, run `python3 scripts/check-ios-bundle.py /path/to/smartmarket.app`
against the real app. Use a fresh build or clean first: removed resource inputs
can remain in an old incremental bundle. Simulator signing does not establish
Apple Developer signing or live CloudKit readiness.

Use a compile-only or archive output for the bundle guard. An XCTest host embeds
test plug-ins and their documentation and is not a distribution artifact.
