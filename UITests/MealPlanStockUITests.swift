import XCTest

/// With an empty kitchen the plan marks catalogue foods; one tap adds them, and the banner goes.
@MainActor
final class MealPlanStockUITests: XCTestCase {
    func testMissingFoodsCanBeAddedFromTheMealPlan() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-NourloEmptyKitchen"]
        app.launch()
        app.tab("Meals").tap()
        let addMissing = app.buttons["meals.addMissing"]
        XCTAssertTrue(addMissing.waitForExistence(timeout: 15))
        let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); before.name = "meals-missing"; before.lifetime = .keepAlways; add(before)
        addMissing.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: addMissing)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 15), .completed, "the plan is rebuilt from the cart and the banner goes")
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); after.name = "meals-owned"; after.lifetime = .keepAlways; add(after)
    }
}
