import XCTest

/// A planned meal has one button, "Review recipe and log", that opens the recipe and
/// the review in one sheet; and a food on the voice review card takes a typed amount
/// and the person's own calories.
@MainActor
final class MealsReviewUITests: XCTestCase {
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    /// Taps a segment of the sheet's switch until it is selected (a tap during the sheet's
    /// own animation can be lost).
    private func select(_ name: String, in app: XCUIApplication) {
        let segment = app.segmentedControls["mealReview.tabs"].buttons[name]
        XCTAssertTrue(segment.waitForExistence(timeout: 10))
        for _ in 0..<4 where !segment.isSelected {
            segment.tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: segment)], timeout: 3)
        }
        XCTAssertTrue(segment.isSelected, "\(name) is shown")
    }

    func testOneButtonOpensTheRecipeAndTheReview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES"]
        app.launch()
        app.tab("Meals").tap()

        let meal = app.buttons.matching(identifier: "mealPlan.meal").firstMatch
        if !meal.waitForExistence(timeout: 15) { app.tab("Meals").tap() }   // a lost first tap
        XCTAssertTrue(meal.waitForExistence(timeout: 20))
        let review = app.buttons["mealPlan.reviewRecipeLog"]
        // A tap while the plan is still settling can be lost: tap again while the card is shut.
        for _ in 0..<3 where !review.exists {
            meal.tap()
            if review.waitForExistence(timeout: 10) { break }
        }
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertEqual(review.label, "Review recipe and log")
        XCTAssertFalse(app.buttons["Recipe"].exists, "no separate Recipe button")
        XCTAssertFalse(app.buttons["Review and log"].exists, "no separate Review and log button")
        // Let the card finish opening, then keep a copy for review (tester feedback C3).
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: review)], timeout: 5)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        shot("meal-expanded")
        let dir = URL(fileURLWithPath: "/tmp/r2-onb")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("meal-expanded.png"))
        for _ in 0..<4 where !review.isHittable { app.swipeUp() }
        // The card may still be expanding when the button is tapped: tap until the sheet opens.
        let tabs = app.segmentedControls["mealReview.tabs"]
        for _ in 0..<3 where !tabs.exists {
            if review.isHittable { review.tap() }
            if tabs.waitForExistence(timeout: 6) { break }
        }

        // The review and log part (the log button is at the end of the form).
        XCTAssertTrue(tabs.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Planned portions"].waitForExistence(timeout: 10))
        shot("meal-review")
        let log = app.buttons["plannedMeal.logStock"]
        for _ in 0..<5 where !log.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(log.exists, "Log meal from stock is in the same sheet")
        // No swipe down here: at the top of the list it closes the whole sheet.
        // The recipe part, in the same sheet (Wikibooks recipes while online AI is off).
        select("Recipe", in: app)
        let recipe = app.descendants(matching: .any)["recipe.cookbook"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 30))
        shot("meal-recipe")
        select("Review and log", in: app)
        XCTAssertTrue(app.staticTexts["Planned portions"].waitForExistence(timeout: 5))
    }

    func testTheVoiceCardTakesATypedAmountAndOwnCalories() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-voiceLanguage_v1", "en", "-NourloVoiceTestPhrase", "log two eggs for breakfast"]
        app.launch()
        let mic = app.buttons["home.voice"]
        XCTAssertTrue(mic.waitForExistence(timeout: 60))
        mic.tap()
        XCTAssertTrue(app.buttons["voice.confirm"].waitForExistence(timeout: 60))

        let amount = app.buttons["voice.food.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        let field = app.alerts.firstMatch.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("150")
        app.buttons["voice.food.amount.set"].firstMatch.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.alerts.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 15), .completed)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS '150'"), object: amount)], timeout: 15), .completed)

        let kcal = app.buttons["voice.food.kcal"]
        let kcalField = app.alerts.firstMatch.textFields.firstMatch
        // The amount dialog may still be closing; tap until the calories dialog opens.
        for _ in 0..<4 where !kcalField.exists {
            kcal.tap()
            _ = kcalField.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(kcalField.waitForExistence(timeout: 5))
        kcalField.tap(); kcalField.typeText("250")
        app.buttons["voice.food.kcal.set"].firstMatch.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS 'your value'"), object: kcal)], timeout: 15), .completed)
        shot("voice-typed")

        app.buttons["voice.confirm"].tap()
        let result = app.staticTexts["voice.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("250 kcal"), result.label)
    }
}
