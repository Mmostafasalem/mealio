import XCTest

/// Food in stock shows the recipes it can make; a recipe opens with its credit, and "I cooked this" logs it.
@MainActor
final class CookbookUITests: XCTestCase {
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testCookWithWhatIHave() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-NourloEmptyKitchen"]
        app.launch()

        // Fill the kitchen: the plan's missing foods go to the cart, and the cart fills My Stock.
        app.tabBars.buttons["Meals"].tap()
        let addMissing = app.buttons["meals.addMissing"]
        XCTAssertTrue(addMissing.waitForExistence(timeout: 15))
        addMissing.tap()

        app.navigationBars.buttons["My Stock"].tap()
        let cook = app.buttons["stock.cook"]
        XCTAssertTrue(cook.waitForExistence(timeout: 10))
        cook.tap()

        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cookbook.recipe.'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), "food in stock suggests recipes")
        shot("cookbook-list")
        first.tap()

        let cooked = app.buttons["cookbook.cooked"]
        XCTAssertTrue(app.staticTexts["Ingredients"].waitForExistence(timeout: 10) || cooked.waitForExistence(timeout: 1))
        shot("cookbook-recipe")
        for _ in 0..<8 where !cooked.isHittable { app.swipeUp() }
        XCTAssertTrue(app.descendants(matching: .any)["cookbook.credit"].exists, "the Wikibooks credit stays under every recipe")
        shot("cookbook-method")
        cooked.tap()

        let log = app.buttons["cookbook.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        shot("cookbook-cooked")
        log.tap()
        XCTAssertFalse(log.waitForExistence(timeout: 2))
    }
}
