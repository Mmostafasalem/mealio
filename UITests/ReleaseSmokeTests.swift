import XCTest

@MainActor
final class ReleaseSmokeTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func tap(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let control = app.buttons[id].firstMatch
        for _ in 0..<10 {
            if control.waitForExistence(timeout: 2) && control.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(control.exists, id, file: file, line: line)
        XCTAssertTrue(control.isHittable, "Unreachable control: \(id)", file: file, line: line)
        XCTAssertTrue(control.isEnabled, "Disabled control: \(id)", file: file, line: line)
        // SwiftUI springs may expose a hittable destination before its frame
        // settles. Wait on geometry, rather than tapping a moving coordinate.
        let deadline = Date().addingTimeInterval(5)
        var frame = control.frame
        var stableSince = Date()
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let next = control.frame
            if next != frame || !control.isHittable { stableSince = Date(); frame = next }
            if Date().timeIntervalSince(stableSince) >= 0.8 { break }
        }
        control.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func onboard(_ app: XCUIApplication, largeText: Bool = false) {
        app.launchArguments = ["-hasSeenWelcome", "NO", "-hasCompletedOnboarding", "NO", "-aiSharingConsent_v1", "NO"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        tap("onboarding.start", in: app)
        tap("onboarding.body.continue", in: app)
        tap("onboarding.location.skip", in: app)
        tap("onboarding.goal.continue", in: app)
        tap("onboarding.diet.continue", in: app)
        tap("onboarding.notifications.skip", in: app)
        for id in ["chicken-breast", "chicken-thighs", "chicken-wings", "whole-chicken", "ground-chicken"] {
            tap("favorite.item." + id, in: app)
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.buttons["favorite.item." + id])
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        }
        tap("onboarding.favorites.finish", in: app)
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 15))
    }

    func testOnboardingAndAllTabs() {
        let app = XCUIApplication()
        onboard(app)
        for name in ["home", "meals", "shop", "map", "profile"] {
            tap("tab." + name, in: app)
            capture("light-" + name)
        }
    }

    func testPrivacyAndSupportAreReachable() {
        let app = XCUIApplication()
        onboard(app)
        tap("tab.profile", in: app)
        tap("profile.privacy", in: app)
        XCTAssertTrue(app.staticTexts["Mealio — Privacy Policy"].waitForExistence(timeout: 5))
        capture("privacy-policy")
        app.navigationBars.buttons.firstMatch.tap()
        tap("profile.support", in: app)
        XCTAssertTrue(app.staticTexts["Mealio — Support"].waitForExistence(timeout: 5))
        capture("help-support")
    }

    func testOnboardingAndTabsAtLargestText() {
        let app = XCUIApplication()
        onboard(app, largeText: true)
        for name in ["home", "meals", "shop", "map", "profile"] {
            tap("tab." + name, in: app)
            capture("largest-text-" + name)
        }
    }
}
