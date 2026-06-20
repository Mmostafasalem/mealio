# iOS unit tests

These are ready-to-run `XCTest` files. They aren't wired into the Xcode project
yet because adding a **test target** safely requires the Xcode UI (hand-editing
`project.pbxproj` risks corrupting it).

## Add the test target (one time, ~1 min in Xcode)
1. Open `smartmarket.xcodeproj` in Xcode.
2. **File ▸ New ▸ Target… ▸ Unit Testing Bundle** → name it `smartmarketTests`.
3. In the new target's **Build Phases ▸ Compile Sources**, add the files in this
   folder (`BMRCalculatorTests.swift`, `PortionTests.swift`).
4. Run with **⌘U**.

CI already compiles the app on every push (`.github/workflows/ci.yml`); once the
target exists you can add `test` to the `xcodebuild` step to run these too.
