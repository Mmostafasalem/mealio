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
            var safeFrame = (id.hasPrefix("tab.") || id == "navigation.quickActions") ? app.frame : app.frame.insetBy(dx: 0, dy: 40)
            if id.hasPrefix("favorite.item."), app.collectionViews.firstMatch.exists {
                safeFrame = safeFrame.intersection(app.collectionViews.firstMatch.frame.insetBy(dx: 0, dy: 12))
            }
            return safeFrame.contains(CGPoint(x: control.frame.midX, y: control.frame.midY))
                && safeFrame.intersection(control.frame).height >= min(44, control.frame.height)
        }
        _ = control.waitForExistence(timeout: 2)
        if id == "navigation.quickActions" {
            XCTAssertGreaterThanOrEqual(control.frame.width, 44 - 0.001, file: file, line: line)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44 - 0.001, file: file, line: line)
        }
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

    func testAppStoreScreenshotCandidates() {
        let app = XCUIApplication()
        onboard(app)
        for name in ["home", "meals", "shop", "map", "profile"] {
            tap("tab." + name, in: app)
            capture("store-candidate-" + name)
        }
    }

    func testMascotGuideExpressionsAndLoggingShortcut() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO", "-ownerAISharingConsent_v1", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["mascot.guide"].waitForExistence(timeout: 10))
        capture("floating-bowl-home")
        tap("mascot.guide", in: app)
        XCTAssertTrue(app.buttons["guide.path.logFood"].waitForExistence(timeout: 5))
        capture("floating-bowl-pathways")
        tap("guide.path.logFood", in: app)
        XCTAssertTrue(app.textFields["Search foods"].waitForExistence(timeout: 8))
        capture("mascot-log-shortcut")
    }

    func testFloatingBowlGuideTourAndTabNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO", "-bowlGuideVisible_v2", "YES"]
        app.launch()
        tap("mascot.guide", in: app)
        tap("guide.tour", in: app)
        XCTAssertTrue(app.staticTexts["Start with one meal"].waitForExistence(timeout: 5))
        capture("floating-bowl-tour-home")
        tap("guide.next", in: app)
        XCTAssertTrue(app.staticTexts["Build your grocery list"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.shop"].isSelected)
        tap("guide.next", in: app)
        XCTAssertTrue(app.staticTexts["Make room for a plan"].waitForExistence(timeout: 5))
        tap("guide.next", in: app)
        XCTAssertFalse(app.buttons["guide.next"].exists)
        tap("tab.map", in: app)
        tap("mascot.guide", in: app)
        XCTAssertTrue(app.staticTexts["Find your way there"].waitForExistence(timeout: 5))
        tap("guide.close", in: app)
        tap("tab.profile", in: app)
        tap("mascot.guide", in: app)
        XCTAssertTrue(app.staticTexts["Make Nourlo yours"].waitForExistence(timeout: 5))
        capture("floating-bowl-profile")
        tap("guide.close", in: app)
    }

    func testFloatingBowlGuideLargeText() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO", "-bowlGuideVisible_v2", "YES", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tap("mascot.guide", in: app)
        XCTAssertTrue(app.buttons["guide.close"].waitForExistence(timeout: 5))
        capture("floating-bowl-large-text")
        tap("guide.path.logFood", in: app)
        XCTAssertTrue(app.textFields["Search foods"].waitForExistence(timeout: 8))
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
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Only Nourlo's custom tab bar should be exposed")
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

    func testOptionalAppleAccountDoesNotBlockLocalTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        app.launch()
        tap("tab.profile", in: app)
        let signIn = app.buttons["profile.appleSignIn"]
        for _ in 0..<8 {
            if signIn.exists && signIn.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(signIn.frame.height, 44)
        tap("tab.home", in: app)
        XCTAssertTrue(app.buttons["tab.home"].exists)
        XCTAssertEqual(app.tabBars.count, 0)
    }

    func testQuickActionsSearchAndCartSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        app.launch()
        tap("navigation.quickActions", in: app)
        let search = app.textFields["quickActions.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("cart")
        tap("quickActions.cart", in: app)
        XCTAssertTrue(app.buttons["quickCart.done"].waitForExistence(timeout: 5))
        capture("quick-actions-cart")
        app.navigationBars["My Cart"].swipeDown()
        if app.buttons["quickCart.done"].exists { tap("quickCart.done", in: app) }
        XCTAssertTrue(app.buttons["navigation.quickActions"].waitForExistence(timeout: 5))
        tap("navigation.quickActions", in: app)
        let again = app.textFields["quickActions.search"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap(); again.typeText("checklist")
        capture("quick-actions-search")
        tap("quickActions.groceries", in: app)
        XCTAssertTrue(app.buttons["groceries.done"].waitForExistence(timeout: 5))
        tap("groceries.done", in: app)
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 5))
    }

    func testQuickLoggerCustomServingDismissesAfterAdding() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        app.launch()
        tap("navigation.quickActions", in: app)
        let menuSearch = app.textFields["quickActions.search"]
        XCTAssertTrue(menuSearch.waitForExistence(timeout: 5))
        menuSearch.tap(); menuSearch.typeText("log food")
        tap("quickActions.logFood", in: app)
        let foodSearch = app.textFields["logFood.search"]
        XCTAssertTrue(foodSearch.waitForExistence(timeout: 5))
        foodSearch.tap(); foodSearch.typeText("bananas raw")
        let apple = app.buttons["logFood.food.usda:173944"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        apple.tap()
        XCTAssertTrue(app.staticTexts["USDA SR Legacy · April 2018"].waitForExistence(timeout: 5))
        capture("nutrition-source-detail")
        tap("logFood.addServing", in: app)
        XCTAssertTrue(app.buttons["navigation.quickActions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["logFood.addServing"].exists)
    }

    func testRestaurantMenuDishCanBeSavedAndLoggedPerServing() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        app.launch()
        tap("navigation.quickActions", in: app)
        let actionSearch = app.textFields["quickActions.search"]
        XCTAssertTrue(actionSearch.waitForExistence(timeout: 5))
        actionSearch.tap(); actionSearch.typeText("log food")
        tap("quickActions.logFood", in: app)
        tap("logFood.createDishToolbar", in: app)
        app.segmentedControls["customFood.mode"].buttons["Restaurant menu"].tap()
        for (id, value) in [("name", "QA Menu Plate"), ("restaurant", "QA Restaurant"), ("energy", "650"), ("protein", "35"), ("carbs", "80"), ("fat", "21")] {
            let field = app.textFields["customFood." + id]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(value)
            let done = app.buttons["customFood.keyboardDone"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap()
        }
        tap("customFood.save", in: app)
        XCTAssertTrue(app.staticTexts["Menu nutrition · entered by you"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["650"].exists)
        capture("restaurant-menu-serving")
        tap("logFood.addServing", in: app)
        XCTAssertTrue(app.buttons["navigation.quickActions"].waitForExistence(timeout: 5))
    }

    func testRetailerProductsSearchIsExplicitAndHasNoBranchStockClaim() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO", "-bowlGuideVisible_v2", "NO"]
        app.launch()
        tap("tab.shop", in: app)
        tap("shop.retailerProducts", in: app)
        let search = app.buttons["retailer.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertFalse(search.isEnabled)
        let retailer = app.textFields["Retailer tag, e.g. rimi"]
        retailer.tap()
        retailer.typeText("rimi")
        XCTAssertTrue(search.isEnabled)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "does not confirm stock")).firstMatch.exists)
        capture("Retailer search disclosure")
    }

    func testStockSearchAddConsumeAndHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO", "-bowlGuideVisible_v2", "NO"]
        app.launch()
        tap("home.stock", in: app)
        tap("stock.add", in: app)
        let search = app.textFields["logFood.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Bananas, raw")
        tap("logFood.food.usda:173944", in: app)
        tap("logFood.addServing", in: app)
        let item = app.buttons["stock.item.usda:173944"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        tap("stock.consume", in: app)
        XCTAssertTrue(app.staticTexts["Your stock starts here"].waitForExistence(timeout: 5))
        capture("Stock consumed")
    }

    func testRecipeBuilderUsesSourceIngredientsAndCookedYield() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        app.launch()
        tap("navigation.quickActions", in: app)
        let actionSearch = app.textFields["quickActions.search"]
        XCTAssertTrue(actionSearch.waitForExistence(timeout: 5))
        actionSearch.tap(); actionSearch.typeText("log food")
        tap("quickActions.logFood", in: app)
        tap("logFood.createDishToolbar", in: app)
        let name = app.textFields["customFood.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("QA Recipe")
        tap("customFood.addIngredient", in: app)
        let search = app.textFields["customFood.ingredientSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("bananas raw")
        tap("customFood.ingredient.usda:173944", in: app)
        let yield = app.textFields["customFood.yield"]
        XCTAssertTrue(yield.waitForExistence(timeout: 5))
        yield.tap(); yield.typeText("200")
        tap("customFood.save", in: app)
        XCTAssertTrue(app.staticTexts["Your recipe · calculated estimate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["45"].exists)
        capture("recipe-source-and-yield")
        tap("logFood.addServing", in: app)
        XCTAssertTrue(app.buttons["navigation.quickActions"].waitForExistence(timeout: 5))
    }

    func testStoreUsesNativeSwipeBackAndLargeQuantityTargets() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        app.launch()
        tap("tab.shop", in: app)
        tap("shop.store.rimi", in: app)
        let add = app.buttons["Add to cart"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(add.frame.width, 44 - 0.001)
        XCTAssertGreaterThanOrEqual(add.frame.height, 44 - 0.001)
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.navigationBars["Shop"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shop.store.rimi"].exists)
        capture("native-back-shop")
    }

    func testPrivacyAndSupportAreReachable() {
        let app = XCUIApplication()
        onboard(app)
        tap("tab.profile", in: app)
        tap("profile.privacy", in: app)
        XCTAssertTrue(app.staticTexts["Nourlo — Privacy Policy"].waitForExistence(timeout: 5))
        capture("privacy-policy")
        app.navigationBars.buttons.firstMatch.tap()
        tap("profile.support", in: app)
        XCTAssertTrue(app.staticTexts["Nourlo — Support"].waitForExistence(timeout: 5))
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
