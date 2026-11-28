import XCTest

/// The Shop tab suggests a week of groceries within the budget, and Add all fills the cart.
@MainActor
final class WeeklyGroceryUITests: XCTestCase {
    func testWeeklyGroceriesAddToCart() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-NourloEmptyKitchen", "-weeklyBudget", "40"]
        app.launch()
        app.tab("Shop").tap()
        let addAll = app.buttons["shop.weeklyPlan.addAll"]
        XCTAssertTrue(addAll.waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "weekly-groceries"; shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<4 where !addAll.isHittable { app.swipeUp() }
        addAll.tap()
        XCTAssertTrue(app.staticTexts["In Cart"].waitForExistence(timeout: 5))
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); after.name = "weekly-groceries-added"; after.lifetime = .keepAlways; add(after)
    }
}
