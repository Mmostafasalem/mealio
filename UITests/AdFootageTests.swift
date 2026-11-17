import XCTest

/// Walks the real app slowly so the simulator's screen can be recorded for the
/// advert (see `video/`). Opt-in: runs only with `TEST_RUNNER_NOURLO_AD_FOOTAGE=1`.
@MainActor
final class AdFootageTests: XCTestCase {

    private func hold(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    private func mark(_ name: String, since start: Date) {
        print("AD-MARK \(name) \(String(format: "%.2f", Date().timeIntervalSince(start))) epoch \(String(format: "%.3f", Date().timeIntervalSince1970))")
    }

    private func drift(_ app: XCUIApplication, from: CGFloat, to: CGFloat) {
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: 260, thenHoldForDuration: 0.1)
    }

    func testWalkTheAppForTheAdvert() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NOURLO_AD_FOOTAGE"] == "1", "Only for recording advert footage")
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-NourloVoiceTestPhrase", "log two eggs and a banana for breakfast", "-NourloEmptyKitchen"]
        app.launch()
        let start = Date()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
        hold(3)
        mark("home", since: start)
        hold(2.5)

        mark("voice-open", since: start)
        app.buttons["home.voice"].firstMatch.tap()
        XCTAssertTrue(app.buttons["voice.confirm"].waitForExistence(timeout: 15))
        hold(2.2)
        mark("voice-confirm", since: start)
        app.buttons["voice.confirm"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["voice.result"].waitForExistence(timeout: 5))
        hold(1.8)
        app.buttons["Done"].firstMatch.tap()
        hold(1.2)
        mark("home-logged", since: start)
        hold(3)
        drift(app, from: 0.75, to: 0.3)
        hold(1.5)
        drift(app, from: 0.75, to: 0.3)
        hold(1.5)

        // Meals: the plan marks what isn't in the kitchen; one tap adds it, then cook from stock.
        app.tabBars.buttons["Meals"].tap()
        hold(1)
        mark("meals-missing", since: start)
        hold(2.5)
        if app.buttons["meals.addMissing"].waitForExistence(timeout: 5) {
            app.buttons["meals.addMissing"].tap()
            hold(2.5)
            mark("meals-owned", since: start)
            hold(1.5)
        }
        app.navigationBars.buttons["My Stock"].tap()
        hold(2)
        mark("stock", since: start)
        if app.buttons["stock.cook"].waitForExistence(timeout: 5) {
            app.buttons["stock.cook"].tap()
            hold(2.5)
            mark("cook", since: start)
            hold(1.5)
            let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cookbook.recipe.'")).firstMatch
            if first.waitForExistence(timeout: 10) { first.tap() }
            hold(2)
            mark("recipe", since: start)
            hold(1.5)
            drift(app, from: 0.8, to: 0.3)
            hold(2)
        }
        app.tabBars.buttons["Home"].tap()
        hold(1)

        for tab in ["Meals", "Shop", "Train"] {
            app.tabBars.buttons[tab].tap()
            hold(1)
            mark(tab.lowercased(), since: start)
            hold(2.5)
            drift(app, from: 0.75, to: 0.35)
            hold(2)
        }
        mark("end", since: start)
    }
}
