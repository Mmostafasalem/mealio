import XCTest

@MainActor
final class ReleaseSmokeTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func tap(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let control = app.buttons[id].firstMatch
        func isVisibleForTap() -> Bool {
            guard control.exists && control.isHittable else { return false }
            // The custom tab bar already reserves its bottom inset. Applying a
            // second artificial bottom margin rejects valid SE tap targets.
            var safeFrame = id.hasPrefix("tab.") ? app.frame : app.frame.insetBy(dx: 0, dy: 40)
            if id.hasPrefix("favorite.item."), app.collectionViews.firstMatch.exists {
                safeFrame = safeFrame.intersection(app.collectionViews.firstMatch.frame.insetBy(dx: 0, dy: 12))
            }
            return safeFrame.contains(CGPoint(x: control.frame.midX, y: control.frame.midY))
                && safeFrame.intersection(control.frame).height >= min(44, control.frame.height)
        }
        _ = control.waitForExistence(timeout: 2)
        for _ in 0..<30 {
            if isVisibleForTap() { break }
            // Fixed CTAs can cover the app's default swipe origin at large
            // text sizes. Scroll the actual list rather than the footer.
            if app.collectionViews.firstMatch.exists {
                let list = app.collectionViews.firstMatch
                let reverse = control.exists && control.frame.midY < list.frame.minY
                let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: reverse ? 0.4 : 0.7))
                let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: reverse ? 0.7 : 0.4))
                // A short drag with a hold avoids flinging past unmaterialized
                // large-text rows in SwiftUI's lazy list.
                start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            } else if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(control.exists, id, file: file, line: line)
        XCTAssertTrue(control.isHittable, "Unreachable control: \(id)", file: file, line: line)
        XCTAssertTrue(isVisibleForTap(), "Control outside safe tap area: \(id)", file: file, line: line)
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

    private func advance(_ source: String, to destination: String, in app: XCUIApplication) {
        // A scroll can consume the first physical tap on iOS. Retry only an
        // unchanged navigation screen, never a selection or destructive action.
        for _ in 0..<2 {
            tap(source, in: app)
            if app.buttons[destination].waitForExistence(timeout: 5) { return }
            if !app.buttons[source].exists { break }
        }
        XCTAssertTrue(app.buttons[destination].exists, "Navigation did not reach \(destination)")
    }

    private func onboard(_ app: XCUIApplication, largeText: Bool = false) {
        app.launchArguments = ["-hasSeenWelcome", "NO", "-hasCompletedOnboarding", "NO", "-aiSharingConsent_v1", "NO"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        advance("onboarding.start", to: "onboarding.body.continue", in: app)
        advance("onboarding.body.continue", to: "onboarding.location.skip", in: app)
        advance("onboarding.location.skip", to: "onboarding.goal.continue", in: app)
        advance("onboarding.goal.continue", to: "onboarding.diet.continue", in: app)
        advance("onboarding.diet.continue", to: "onboarding.notifications.skip", in: app)
        advance("onboarding.notifications.skip", to: "onboarding.favorites.finish", in: app)
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
            capture("system-" + name)
        }
    }

    func testMetricInfoHasAccessibleTouchTarget() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        app.launch()
        let info = app.buttons["More info"].firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 15))
        // Layout conversion may represent 44pt as 43.99999999999994.
        // Permit numerical roundoff, not a physically smaller touch target.
        let geometryTolerance: CGFloat = 0.001
        XCTAssertGreaterThanOrEqual(info.frame.width, 44 - geometryTolerance)
        XCTAssertGreaterThanOrEqual(info.frame.height, 44 - geometryTolerance)
    }

    func testCustomNavigationHidesSystemTabBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Only Mealio's custom tab bar should be exposed")
        // Shop provides an unobstructed header independent of transient Home banners.
        tap("tab.shop", in: app)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Best value in Lithuania"].exists)
        XCTAssertFalse(app.staticTexts["Everyday low prices"].exists)
        capture("custom-navigation")
    }

    func testOnboardingAndTabsInLandscape() {
        let app = XCUIApplication()
        onboard(app)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        tap("tab.home", in: app)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        for name in ["home", "meals", "shop", "map", "profile"] {
            tap("tab." + name, in: app)
            capture("landscape-" + name)
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
