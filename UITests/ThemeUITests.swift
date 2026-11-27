import XCTest

/// Colour themes: switching in Profile › Appearance recolours the app at once, and a
/// review run (`TEST_RUNNER_NOURLO_SHOTS=/folder`) photographs Home, Meals, Shop and
/// Appearance in several themes, light and dark.
@MainActor
final class ThemeUITests: XCTestCase {
    private func launch(theme: String, appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-appearanceOverride_v1", appearance,
                               "-enabledFeatures_v1", "tracking,meals,groceries,workouts"]
        if !theme.isEmpty { app.launchArguments += ["-appTheme_v1", theme] }
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
        if let folder = ProcessInfo.processInfo.environment["NOURLO_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
    }

    private func openAppearance(_ app: XCUIApplication) {
        let profile = app.navigationBars["Profile"]
        for _ in 0..<3 where !profile.exists {
            let avatar = app.buttons["home.profile"]
            if avatar.waitForExistence(timeout: 20) { avatar.tap() }
            _ = profile.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(profile.exists, "Profile didn't open")
        let swatch = app.buttons["profile.theme.pink"]
        for _ in 0..<14 where !(swatch.exists && swatch.isHittable) { app.swipeUp() }
        XCTAssertTrue(swatch.isHittable)
        // A short drag so the second row of swatches is in view too, the first still below the bar.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220)))
    }

    /// Tapping a swatch selects it and saves it; no restart needed.
    func testSwitchingThemeIsInstantAndKept() {
        continueAfterFailure = false
        // An empty value = nothing chosen yet: Nourlo Pink.
        let app = launch(theme: "", appearance: "light")
        openAppearance(app)
        XCTAssertTrue(app.buttons["profile.theme.pink"].isSelected, "pink is the default")
        let forest = app.buttons["profile.theme.forest"]
        forest.tap()
        XCTAssertTrue(forest.waitForExistence(timeout: 2))
        XCTAssertTrue(forest.isSelected)
        XCTAssertFalse(app.buttons["profile.theme.pink"].isSelected)
        XCTAssertEqual(forest.label, "Forest Green")
        // Back to pink so later tests start from the default.
        app.buttons["profile.theme.pink"].tap()
        XCTAssertTrue(app.buttons["profile.theme.pink"].isSelected)
    }

    func testReviewScreenshots() throws {
        guard ProcessInfo.processInfo.environment["NOURLO_SHOTS"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_NOURLO_SHOTS to a folder to take the theme screenshots")
        }
        let themes = ProcessInfo.processInfo.environment["NOURLO_THEMES"]?.split(separator: ",").map(String.init)
            ?? ["ocean", "forest", "graphite"]
        for theme in themes {
            for appearance in ["light", "dark"] {
                let app = launch(theme: theme, appearance: appearance)
                let tag = "\(theme)-\(appearance)"
                XCTAssertTrue(app.buttons["home.profile"].waitForExistence(timeout: 60))
                sleep(2)
                shot("\(tag)-1-home")
                for (tab, n) in [("Meals", 2), ("Shop", 3)] {
                    let button = app.tabBars.buttons[tab]
                    XCTAssertTrue(button.waitForExistence(timeout: 30))
                    button.tap(); sleep(3)
                    shot("\(tag)-\(n)-\(tab.lowercased())")
                }
                app.tabBars.buttons["Home"].tap(); sleep(1)
                openAppearance(app); sleep(1)
                shot("\(tag)-4-appearance")
                app.terminate()
            }
        }
    }
}
