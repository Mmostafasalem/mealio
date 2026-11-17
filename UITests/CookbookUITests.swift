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

    /// Add Food finds Wikibooks recipes by name and logs a serving; the browse list opens recipes.
    func testAddFoodOffersWikibooksRecipes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES"]
        app.launch()
        let plus = app.tabBars.buttons["Quick actions"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        let logFood = app.buttons["quickActions.logFood"].firstMatch
        for _ in 0..<3 where !logFood.exists { plus.tap(); _ = logFood.waitForExistence(timeout: 3) }
        logFood.tap()

        let browse = app.buttons["logFood.browseRecipes"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10))
        shot("logfood-recipes-entry")

        let search = app.textFields["logFood.search"]
        search.tap()
        search.typeText("omelette")
        let recipe = app.buttons["logFood.food.cookbook:cheese-omelette"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10), "recipes show up in the food search")
        shot("logfood-recipe-search")
        recipe.tap()
        let add = app.buttons["logFood.addServing"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        shot("logfood-recipe-serving")
        add.tap()
        // The button shows "Added" for a moment, then the sheet closes.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: add)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 30), .completed, "the serving is logged and the sheet closes")
    }
}
