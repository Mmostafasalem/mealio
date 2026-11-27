import XCTest

/// TestFlight B2–B7: the quick-actions button, Home's layout, Reminders off Home,
/// the guided tour and calorie insights. Screenshots are attached to the run (and,
/// with `NOURLO_SHOTS_DIR` set, written there too).
@MainActor
final class HomeLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-bowlGuideVisible_v2", "YES",
                               "-enabledFeatures_v1", "tracking,meals,groceries,workouts"] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        return app
    }

    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["NOURLO_SHOTS_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Scrolls Home until `id` is fully on screen above the tab bar.
    private func scrollTo(_ id: String, in app: XCUIApplication) {
        let target = element(id, in: app)
        let bar = app.tabBars.firstMatch
        for _ in 0..<12 {
            if target.exists, target.isHittable, target.frame.maxY < bar.frame.minY - 8, target.frame.minY > 90 { return }
            app.swipeUp(velocity: .slow)
        }
    }

    /// B2/B3(a): the bowl button beside the dock; B3(c), B4, B5: Home's hierarchy, no bell.
    func testHomeHasOneHeroColouredSectionsAndNoBell() {
        let app = launch()
        XCTAssertTrue(app.buttons["navigation.quickActions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home.reminders"].exists, "the bell is gone from Home")
        XCTAssertTrue(app.buttons["home.insights"].exists)
        XCTAssertTrue(app.buttons["home.logFood"].exists)
        XCTAssertTrue(app.buttons["home.voice"].exists, "the microphone sits beside Log food")
        XCTAssertFalse(app.staticTexts["Grocery estimates"].exists)
        capture("b4-home-1-hero")
        scrollTo("home.meals.open", in: app)
        XCTAssertTrue(app.buttons["home.meals.open"].exists)
        capture("b4-home-2-meals")
        scrollTo("home.groceries.shop", in: app)
        XCTAssertTrue(app.buttons["home.groceries.shop"].exists)
        XCTAssertTrue(app.buttons["home.stock"].exists, "My Stock sits with the groceries")
        capture("b4-home-3-groceries")
        scrollTo("home.training.open", in: app)
        XCTAssertTrue(app.buttons["home.training.open"].exists)
        capture("b4-home-4-training")
        XCTAssertFalse(app.staticTexts["Grocery estimates"].exists, "no price-card section on Home")
    }

    /// B3(b): My Stock from quick actions, Meals' header and Shop.
    func testMyStockIsReachableFromQuickActionsMealsAndShop() {
        let app = launch()
        app.buttons["navigation.quickActions"].tap()
        XCTAssertTrue(app.buttons["quickActions.stock"].waitForExistence(timeout: 5))
        capture("b3-quick-actions-grid")
        app.buttons["quickActions.done"].tap()
        app.tab("Meals").tap()
        XCTAssertTrue(app.navigationBars.buttons["My Stock"].waitForExistence(timeout: 8))
        capture("b3-meals-header-stock")
        app.tab("Shop").tap()
        let shopStock = app.descendants(matching: .any)["My Stock"].firstMatch
        for _ in 0..<6 where !(shopStock.exists && shopStock.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(shopStock.exists)
        capture("b3-shop-stock")
    }

    /// B7: Home → Calorie insights, with the chart, streak and both ranges.
    func testCalorieInsightsOpenFromHome() {
        let app = launch()
        app.buttons["home.insights"].tap()
        XCTAssertTrue(app.navigationBars["Calorie insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("insights.chart", in: app).exists)
        XCTAssertTrue(element("insights.streak", in: app).exists)
        capture("b7-insights-7-days")
        let month = app.buttons["30 days"]
        for _ in 0..<3 where !month.isSelected { month.tap(); sleep(1) }
        XCTAssertTrue(month.isSelected)
        capture("b7-insights-30-days")
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(element("insights.macros", in: app).waitForExistence(timeout: 3))
        capture("b7-insights-macros")
        app.navigationBars.buttons.firstMatch.tap()
        // The week chart on the calorie card opens the same page.
        XCTAssertTrue(app.buttons["home.weekChart"].waitForExistence(timeout: 5))
        app.buttons["home.weekChart"].tap()
        XCTAssertTrue(app.navigationBars["Calorie insights"].waitForExistence(timeout: 5))
    }

    /// B6: the tour lights up calories, Meals, quick actions, Shop and Train, then never comes back by itself.
    func testGuidedTourRunsOnceThroughTheMainParts() {
        let app = launch(["-NourloShowTour", "YES", "-guidedTourSeen_v1", "NO"])
        let title = app.staticTexts["tour.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        var titles: [String] = []
        for step in 1...5 {
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            let label = title.label
            titles.append(label)
            sleep(1)
            capture("b6-tour-step-\(step)")
            app.buttons["tour.next"].tap()
            // The next step (or the end of the tour) before reading its title.
            let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR label != %@", label), object: title)
            XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 10), .completed)
        }
        XCTAssertEqual(titles, ["Your calories today", "Meals", "Quick actions", "Shop", "Train"])
        XCTAssertFalse(title.waitForExistence(timeout: 2), "Done ends the tour")
        app.terminate()
        let again = launch(["-NourloShowTour", "YES"])
        XCTAssertFalse(again.staticTexts["tour.title"].waitForExistence(timeout: 4), "shown once")
    }
}
