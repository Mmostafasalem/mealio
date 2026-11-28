import XCTest

/// Screenshots of Nourlo as the quick-actions button, its pills, the tab headers and
/// the guided tour (opt-in: TEST_RUNNER_NOURLO_SHOTS=1; TEST_RUNNER_NOURLO_SHOTS_DIR
/// also writes them to that folder).
@MainActor
final class QuickActionsMenuShotTests: XCTestCase {
    private let looks = [("pink", "light"), ("pink", "dark"), ("ocean", "light"), ("ocean", "dark")]

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NOURLO_SHOTS"] == "1", "screenshots only")
        continueAfterFailure = false
    }

    private func launch(theme: String, style: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-NourloUITesting", "YES",
                               "-aiSharingConsent_v1", "NO", "-onlineAIOffered_v1", "YES", "-appTheme_v1", theme,
                               "-appearanceOverride_v1", style,
                               "-enabledFeatures_v1", "tracking,meals,groceries,workouts"] + extra
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        if let dir = ProcessInfo.processInfo.environment["NOURLO_SHOTS_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    private func settle(_ seconds: TimeInterval = 1.2) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    func testMenuScreens() throws {
        for (theme, style) in looks {
            let app = launch(theme: theme, style: style)
            let look = "\(theme)-\(style)"
            let nourlo = app.buttons["navigation.quickActions"].firstMatch
            XCTAssertTrue(nourlo.waitForExistence(timeout: 20))
            settle(1.5)
            capture("home-\(look)")
            nourlo.tap()
            XCTAssertTrue(app.buttons["quickActions.done"].waitForExistence(timeout: 5))
            settle(0.2)
            capture("menu-opening-\(look)")
            settle(1.0)
            capture("menu-\(look)")
            let more = app.buttons["quickActions.more"]
            if more.exists {
                more.tap()
                settle(1.0)
                capture("menu-more-\(look)")
            }
            app.buttons["quickActions.done"].tap()
            settle(0.8)
            for tab in ["Meals", "Shop", "Train"] {
                app.tab(tab).tap()
                settle(1.5)
                capture("\(tab.lowercased())-\(look)")
            }
            app.tab("Shop").tap()
            app.buttons["navigation.quickActions"].firstMatch.tap()
            XCTAssertTrue(app.buttons["quickActions.done"].waitForExistence(timeout: 5))
            settle(1.0)
            capture("shop-menu-\(look)")
            app.terminate()
        }
    }

    func testTourScreens() throws {
        for (theme, style) in [("pink", "light"), ("ocean", "dark")] {
            let app = launch(theme: theme, style: style, ["-NourloShowTour", "YES", "-guidedTourSeen_v1", "NO"])
            let title = app.staticTexts["tour.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 15))
            var step = 1
            while title.waitForExistence(timeout: 5), step < 40 {
                settle(1.8)
                let label = title.label
                capture(String(format: "tour-%@-%@-%02d-%@", theme, style, step, label.replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "/", with: "_")))
                app.buttons["tour.next"].tap()
                let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR label != %@", label), object: title)
                _ = XCTWaiter.wait(for: [moved], timeout: 6)
                step += 1
            }
            app.terminate()
        }
    }
}
