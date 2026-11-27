import XCTest

@MainActor
final class ReleaseSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // An interrupted landscape run leaves the simulator rotated; start upright.
        XCUIDevice.shared.orientation = .portrait
    }

    /// The system tab bar's buttons carry their names, not identifiers: "tab.home"
    /// → "Home", …. Quick actions ("navigation.quickActions") is the bowl button
    /// beside the bar, an ordinary button with that identifier.
    private static let tabNames = ["tab.home": "Home", "tab.meals": "Meals", "tab.shop": "Shop",
                                   "tab.train": "Train"]

    private func control(_ id: String, in app: XCUIApplication) -> XCUIElement {
        if let name = Self.tabNames[id] { return app.tab(name) }
        return app.buttons[id].firstMatch
    }

    private func tap(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let control = self.control(id, in: app)
        func isVisibleForTap() -> Bool {
            guard control.exists && control.isHittable else { return false }
            // The custom tab bar already reserves its bottom inset. Applying a
            // second artificial bottom margin rejects valid SE tap targets.
            // The Home avatar and bowl are header controls right under the status bar,
            // so the bottom-reach margin does not apply to it either.
            var safeFrame = (id.hasPrefix("tab.") || id == "navigation.quickActions" || id == "home.profile" || id == "mascot.guide") ? app.frame : app.frame.insetBy(dx: 0, dy: 40)
            if id.hasPrefix("favorite.item."), app.scrollViews["favorites.list"].exists {
                safeFrame = safeFrame.intersection(app.scrollViews["favorites.list"].frame.insetBy(dx: 0, dy: 4))
            } else if id.hasPrefix("favorite.item."), app.collectionViews.firstMatch.exists {
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
            if app.scrollViews["favorites.list"].exists {
                // The favourites chips scroll vertically; the first scroll view
                // on that screen is the sideways category strip. A short, slow
                // drag (either way) keeps a chip from flying past the viewport.
                let list = app.scrollViews["favorites.list"]
                let reverse = control.exists && control.frame.midY < list.frame.minY
                let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: reverse ? 0.35 : 0.65))
                let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: reverse ? 0.65 : 0.35))
                start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            } else if app.collectionViews.firstMatch.exists {
                let list = app.collectionViews.firstMatch
                let reverse = control.exists && control.frame.midY < list.frame.minY
                // Near the right edge: the middle of a list can hold its own drag
                // controls (Profile's appearance cord), which would swallow the scroll.
                let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: reverse ? 0.4 : 0.7))
                let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: reverse ? 0.7 : 0.4))
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

    /// Profile opens from the avatar at the top of Home.
    /// Opens Profile from Home's avatar and confirms it opened. Right after
    /// onboarding or a tab switch the tap can land mid-transition and be lost,
    /// so the avatar is tapped again (up to three times) until Profile shows.
    private func openProfile(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        tap("tab.home", in: app, file: file, line: line)
        let profile = app.navigationBars["Profile"]
        for _ in 0..<3 {
            tap("home.profile", in: app, file: file, line: line)
            if profile.waitForExistence(timeout: 3) { return }
            // Already off Home: the push is still running, so don't tap again.
            if !app.buttons["home.profile"].exists, profile.waitForExistence(timeout: 5) { return }
        }
        XCTFail("Profile didn't open", file: file, line: line)
    }

    /// Waits until an element is gone (a sheet finished dismissing).
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5,
                               file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed,
                       "\(element) is still on screen", file: file, line: line)
    }

    /// Opens the quick-actions sheet from the tab bar's "+" and picks a row. A tap
    /// on "+" can be swallowed while another sheet is still animating away, so
    /// this re-taps "+" if the sheet didn't open, and waits for the row to take a tap.
    private func chooseQuickAction(_ action: String, in app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let plus = control("navigation.quickActions", in: app)
        let row = app.buttons["quickActions." + action].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<3 {
            if !row.exists { tap("navigation.quickActions", in: app, file: file, line: line) }
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                if row.exists && row.isHittable {
                    row.tap()
                    return
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
        XCTFail("Quick action \(action) never appeared", file: file, line: line)
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
        // "Chat with Nourlo?" shows only while the server offers online AI: go on without an account.
        let skip = app.buttons["onboarding.account.skip"]
        if !app.buttons[destination].exists, skip.exists {
            skip.tap()
            _ = app.buttons[destination].waitForExistence(timeout: 5)
        }
        XCTAssertTrue(app.buttons[destination].exists, "Navigation did not reach \(destination)")
    }

    /// Every launch goes through here so TipKit tips never cover controls under test.
    private func launchForTesting(_ app: XCUIApplication) {
        if !app.launchArguments.contains("-NourloUITesting") {
            app.launchArguments += ["-NourloUITesting", "YES"]
        }
        // Every feature at launch, whatever an earlier test chose in onboarding
        // (the choice it saved stays on the simulator).
        if !app.launchArguments.contains("-enabledFeatures_v1") {
            app.launchArguments += ["-enabledFeatures_v1", "tracking,meals,groceries,workouts"]
        }
        app.launch()
    }

    /// Onboarding with only Workouts chosen: no diet or favourite-food screens,
    /// and the tab bar holds Home, Train and quick actions only.
    func testOnboardingWithOnlyWorkoutsShowsHomeAndTrain() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "NO", "-hasCompletedOnboarding", "NO", "-aiSharingConsent_v1", "NO"]
        launchForTesting(app)
        advance("onboarding.start", to: "onboarding.name.continue", in: app)
        advance("onboarding.name.continue", to: "onboarding.features.continue", in: app)
        XCTAssertTrue(app.staticTexts["What do you want Nourlo for?"].exists)
        // 10 screens, 11 when the server offers online AI (the account step).
        XCTAssertTrue(app.staticTexts["2 / 10"].exists || app.staticTexts["2 / 11"].exists)
        capture("onboarding-features-all")
        for feature in ["tracking", "meals", "groceries"] {
            let row = app.buttons["onboarding.feature." + feature]
            // A busy simulator can drop a tap; tap again only while the row is still on.
            for _ in 0..<2 where row.isSelected {
                tap("onboarding.feature." + feature, in: app)
                let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == false"), object: row)
                _ = XCTWaiter.wait(for: [off], timeout: 5)
            }
            XCTAssertFalse(row.isSelected, feature)
        }
        XCTAssertTrue(app.buttons["onboarding.feature.workouts"].isSelected)
        XCTAssertTrue(app.staticTexts["2 / 7"].waitForExistence(timeout: 3) || app.staticTexts["2 / 8"].exists)
        capture("onboarding-features-workouts")
        advance("onboarding.features.continue", to: "onboarding.height.continue", in: app)
        advance("onboarding.height.continue", to: "onboarding.weight.continue", in: app)
        advance("onboarding.weight.continue", to: "onboarding.activity.continue", in: app)
        advance("onboarding.activity.continue", to: "onboarding.goal.continue", in: app)
        // No diet, favourite-food or week screens for workouts: the goal leads to reminders and Health.
        advance("onboarding.goal.continue", to: "onboarding.alerts.finish", in: app)
        XCTAssertTrue(app.staticTexts["7 / 7"].exists || app.staticTexts["8 / 8"].exists, "7 screens, 8 with the AI account step")
        // Only the workout reminder is offered.
        XCTAssertTrue(app.buttons["onboarding.alerts.workout"].exists)
        XCTAssertFalse(app.buttons["onboarding.alerts.breakfast"].exists)
        capture("onboarding-alerts-workouts")
        // Like `advance`: a tap right after a push can be lost, so retry while the screen is unchanged.
        for _ in 0..<3 {
            tap("onboarding.alerts.finish", in: app)
            if control("tab.home", in: app).waitForExistence(timeout: 10) { break }
            if !app.buttons["onboarding.alerts.finish"].exists { break }
        }

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(control("tab.home", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(control("tab.train", in: app).exists)
        XCTAssertTrue(control("navigation.quickActions", in: app).exists)
        XCTAssertFalse(tabBar.buttons["Meals"].exists)
        XCTAssertFalse(tabBar.buttons["Shop"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.workoutSummary"].firstMatch.waitForExistence(timeout: 5))
        capture("home-workouts-only")
        tap("tab.train", in: app)
        capture("train-workouts-only")
        // Profile › Features shows the same choice; Workouts is the last one on, so it can't be turned off.
        openProfile(in: app)
        let workouts = app.descendants(matching: .any)["profile.feature.workouts"].firstMatch
        for _ in 0..<8 where !(workouts.exists && workouts.isHittable) { app.swipeUp() }
        XCTAssertTrue(workouts.isHittable)
        XCTAssertFalse(workouts.isEnabled)
        capture("profile-features-workouts-only")
    }

    private func onboard(_ app: XCUIApplication, largeText: Bool = false) {
        app.launchArguments = ["-hasSeenWelcome", "NO", "-hasCompletedOnboarding", "NO", "-aiSharingConsent_v1", "NO"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        launchForTesting(app)
        advance("onboarding.start", to: "onboarding.name.continue", in: app)
        // Name, age and gender share the first page; age is a number with minus and plus.
        XCTAssertTrue(app.textFields["onboarding.age"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["One year older"].exists)
        // What Nourlo is for: every feature starts on, so the full app (and every other test) stays the same.
        advance("onboarding.name.continue", to: "onboarding.features.continue", in: app)
        for feature in ["tracking", "meals", "groceries", "workouts"] {
            XCTAssertTrue(app.buttons["onboarding.feature." + feature].isSelected, feature)
        }
        advance("onboarding.features.continue", to: "onboarding.height.continue", in: app)
        advance("onboarding.height.continue", to: "onboarding.weight.continue", in: app)
        advance("onboarding.weight.continue", to: "onboarding.activity.continue", in: app)
        advance("onboarding.activity.continue", to: "onboarding.goal.continue", in: app)
        advance("onboarding.goal.continue", to: "onboarding.diet.continue", in: app)
        advance("onboarding.diet.continue", to: "onboarding.favorites.finish", in: app)
        // Narrow the ~340 chips to a handful first: on a slow machine, reading the
        // whole chip grid for every query can time out.
        let search = app.textFields.element(matching: NSPredicate(format: "placeholderValue BEGINSWITH 'Search'"))
        XCTAssertTrue(search.waitForExistence(timeout: 5), "favourites search field")
        search.tap()
        search.typeText("chicken\n")
        // The short filtered list can rest a row under the category strip; start from its top.
        let list = app.scrollViews["favorites.list"]
        if list.exists { list.swipeDown(velocity: .slow) }
        for id in ["chicken-breast", "chicken-thighs", "chicken-wings", "whole-chicken", "ground-chicken"] {
            let chip = app.buttons["favorite.item." + id].firstMatch
            XCTAssertTrue(chip.waitForExistence(timeout: 5), id)
            if !chip.isHittable, list.exists { list.swipeDown(velocity: .slow) }
            XCTAssertTrue(chip.isHittable, "Unreachable control: favorite.item." + id)
            XCTAssertGreaterThanOrEqual(chip.frame.width, 44 - 0.001, id)
            XCTAssertGreaterThanOrEqual(chip.frame.height, 44 - 0.001, id)
            XCTAssertTrue(app.frame.insetBy(dx: 0, dy: 40).contains(CGPoint(x: chip.frame.midX, y: chip.frame.midY)),
                          "Control outside safe tap area: favorite.item." + id)
            chip.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.buttons["favorite.item." + id])
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        }
        advance("onboarding.favorites.finish", to: "onboarding.week.continue", in: app)
        advance("onboarding.week.continue", to: "onboarding.alerts.finish", in: app)
        tap("onboarding.alerts.finish", in: app)
        XCTAssertTrue(control("tab.home", in: app).waitForExistence(timeout: 15))
    }

    func testAppStoreScreenshotCandidates() {
        let app = XCUIApplication()
        onboard(app)
        for name in ["home", "meals", "shop", "train"] {
            tap("tab." + name, in: app)
            capture("store-candidate-" + name)
        }
    }

    /// Explicitly selected live integration test; uses only the default synthetic
    /// local profile in a dedicated disposable simulator. Onboarding has its
    /// own UI journeys; this test starts at the account settings.
    func testLiveGuestSignInChatAndAccountDeletion() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NOURLO_LIVE_GUEST_UI"] == "1",
                          "Set TEST_RUNNER_NOURLO_LIVE_GUEST_UI=1 on an isolated simulator.")
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Nourlo Guest AI Verification",
                          "This test may delete only its dedicated disposable simulator's app data.")
        let app = XCUIApplication()
        // No "-aiSharingConsent_v1" argument here: a launch argument would override the
        // switch the test turns on (the dedicated simulator is erased before each run).
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES",
                               "-bowlGuideVisible_v2", "YES"]
        launchForTesting(app)
        openProfile(in: app)
        capture("live-guest-profile-navigation")
        let guest = app.buttons["profile.guestSignIn"]
        // Profile is long (Features, week, appearance …); keep scrolling until the guest button shows.
        for _ in 0..<16 {
            if guest.exists && guest.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(guest.waitForExistence(timeout: 90))
        tap("profile.guestSignIn", in: app)
        XCTAssertTrue(app.staticTexts["Guest access on this device"].waitForExistence(timeout: 120))
        capture("live-guest-account-allowance")
        let consent = app.switches["profile.aiConsent"]
        for _ in 0..<8 {
            if consent.exists && consent.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(consent.isHittable)
        // The switch's value reads "0"/"1" on older systems and may differ on newer ones; tap until it is on.
        func isOn() -> Bool { ["1", "on", "true"].contains((consent.value as? String ?? "").lowercased()) }
        for _ in 0..<3 where !isOn() {
            // The custom switch reacts on its knob at the right edge of the row.
            consent.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(isOn(), "AI sharing switched on (value: \(consent.value ?? "nil"))")
        tap("tab.home", in: app)
        tap("mascot.guide", in: app)
        tap("guide.chat", in: app)
        // The composer grows to several lines, so it may be a text view.
        let field = app.descendants(matching: .any)["Ask about meals or groceries…"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Synthetic connection test: briefly confirm you can help plan a meal.")
        tap("chat.send", in: app)
        // The reply bubble appears empty while it streams; wait for real words in it.
        let reply = app.descendants(matching: .any)["chat.assistantReply"].firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 120), "The live authenticated AI must return a response.")
        let hasWords = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*[A-Za-z]{3,}.*[A-Za-z]{3,}.*"), object: reply)
        XCTAssertEqual(XCTWaiter.wait(for: [hasWords], timeout: 120), .completed, "The reply has text: \(reply.label)")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertFalse(app.otherElements["chat.notice"].exists)
        capture("live-guest-online-chat")
        app.buttons["Done"].tap()
        openProfile(in: app)
        let delete = app.buttons["Delete All Data"]
        for _ in 0..<10 {
            if delete.exists && delete.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        app.alerts.buttons["Delete Data"].tap()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 120),
                      "Test account deletion must complete before onboarding restarts.")
        capture("live-guest-account-deleted")
    }

    func testMascotGuideExpressionsAndLoggingShortcut() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO", "-ownerAISharingConsent_v1", "NO"]
        launchForTesting(app)
        XCTAssertTrue(app.buttons["mascot.guide"].waitForExistence(timeout: 10))
        capture("floating-bowl-home")
        // As in the large-text test below: a tap in the first moments after a
        // cold launch can be lost while Home finishes its first layout. Retry once.
        tap("mascot.guide", in: app)
        if !app.buttons["guide.path.logFood"].waitForExistence(timeout: 4) { tap("mascot.guide", in: app) }
        XCTAssertTrue(app.buttons["guide.path.logFood"].waitForExistence(timeout: 5))
        capture("floating-bowl-pathways")
        tap("guide.path.logFood", in: app)
        XCTAssertTrue(app.textFields["Search foods"].waitForExistence(timeout: 8))
        capture("mascot-log-shortcut")
    }

    func testFloatingBowlGuideTourAndTabNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO", "-bowlGuideVisible_v2", "YES"]
        launchForTesting(app)
        tap("mascot.guide", in: app)
        tap("guide.tour", in: app)
        XCTAssertTrue(app.staticTexts["Start with one meal"].waitForExistence(timeout: 5))
        capture("floating-bowl-tour-home")
        tap("guide.next", in: app)
        XCTAssertTrue(app.staticTexts["Build your grocery list"].waitForExistence(timeout: 5))
        XCTAssertTrue(control("tab.shop", in: app).isSelected)
        tap("guide.next", in: app)
        XCTAssertTrue(app.staticTexts["Make room for a plan"].waitForExistence(timeout: 5))
        tap("guide.next", in: app)
        XCTAssertFalse(app.buttons["guide.next"].exists)
        openProfile(in: app)
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        capture("profile-from-avatar")
    }

    func testFloatingBowlGuideLargeText() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO", "-bowlGuideVisible_v2", "YES", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launchForTesting(app)
        // At the largest text size a cold simulator can still be finishing its
        // first layout when the bowl appears; a tap then is lost. Retry once.
        tap("mascot.guide", in: app)
        if !app.buttons["guide.close"].waitForExistence(timeout: 4) { tap("mascot.guide", in: app) }
        XCTAssertTrue(app.buttons["guide.close"].waitForExistence(timeout: 5))
        capture("floating-bowl-large-text")
        tap("guide.path.logFood", in: app)
        XCTAssertTrue(app.textFields["Search foods"].waitForExistence(timeout: 8))
    }

    func testOnboardingAndAllTabs() {
        let app = XCUIApplication()
        onboard(app)
        for name in ["home", "meals", "shop", "train"] {
            tap("tab." + name, in: app)
            capture("system-" + name)
        }
    }

    func testMetricInfoHasAccessibleTouchTarget() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        launchForTesting(app)
        let info = app.buttons["More info"].firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 15))
        // Layout conversion may represent 44pt as 43.99999999999994.
        // Permit numerical roundoff, not a physically smaller touch target.
        let geometryTolerance: CGFloat = 0.001
        XCTAssertGreaterThanOrEqual(info.frame.width, 44 - geometryTolerance)
        XCTAssertGreaterThanOrEqual(info.frame.height, 44 - geometryTolerance)
    }

    /// "N selected" on Favourite foods lists only the chosen foods; tapping again shows all.
    func testFavouriteFoodsSelectedCountShowsOnlyThoseFoods() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-favoriteFoodIDs", "(chicken-breast)"]
        launchForTesting(app)
        chooseQuickAction("profile", in: app)
        let row = app.buttons["Favourite foods"].firstMatch
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        row.tap()
        let toggle = app.buttons["favorites.selectedOnly"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Chicken Thighs"].waitForExistence(timeout: 5), "the full list first")
        toggle.tap()
        XCTAssertTrue(app.staticTexts["Chicken Breast"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Chicken Thighs"].exists, "only the picked foods")
        capture("favourites-selected-only")
        app.buttons["favorites.selectedOnly"].tap()
        XCTAssertTrue(app.staticTexts["Chicken Thighs"].waitForExistence(timeout: 5), "all again")
        // A subgroup's "Select all" picks every chicken; then it offers "Clear".
        let chicken = app.buttons["favorites.selectAll.Chicken"]
        XCTAssertTrue(chicken.waitForExistence(timeout: 5))
        capture("favourites-grouped")
        chicken.tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Clear Chicken'"), object: chicken)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed, "all six chicken foods picked")
        let count = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '6 selected'"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [count], timeout: 5), .completed, "six selected")
        chicken.tap()
        let selectAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Select Chicken'"), object: chicken)
        XCTAssertEqual(XCTWaiter.wait(for: [selectAgain], timeout: 5), .completed)
    }

    /// With online AI offered, onboarding asks "Chat with Nourlo?" before reminders; "Not now" goes on.
    func testOnboardingOffersAnAIAccountStep() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "NO", "-hasCompletedOnboarding", "NO", "-aiSharingConsent_v1", "NO",
                               "-onlineAIOffered_v1", "YES"]
        launchForTesting(app)
        advance("onboarding.start", to: "onboarding.name.continue", in: app)
        advance("onboarding.name.continue", to: "onboarding.features.continue", in: app)
        // Workouts only, the shortest path to the account step.
        for id in ["tracking", "meals", "groceries"] {
            let row = app.buttons["onboarding.feature.\(id)"]
            if row.waitForExistence(timeout: 5) { row.tap() }
        }
        advance("onboarding.features.continue", to: "onboarding.height.continue", in: app)
        advance("onboarding.height.continue", to: "onboarding.weight.continue", in: app)
        advance("onboarding.weight.continue", to: "onboarding.activity.continue", in: app)
        advance("onboarding.activity.continue", to: "onboarding.goal.continue", in: app)
        tap("onboarding.goal.continue", in: app)
        XCTAssertTrue(app.staticTexts["Chat with Nourlo?"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["onboarding.account.skip"].exists)
        capture("onboarding-account-step")
        tap("onboarding.account.skip", in: app)
        XCTAssertTrue(app.buttons["onboarding.alerts.finish"].waitForExistence(timeout: 5))
    }

    func testSystemTabBarShowsIconsOnly() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPad shows the tabs in a floating bar at the top, not a tab bar")
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        launchForTesting(app)
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "the native tab bar")
        for name in ["Home", "Meals", "Shop", "Train"] {
            XCTAssertTrue(bar.buttons[name].exists, "\(name) is named for VoiceOver")
        }
        XCTAssertEqual(bar.staticTexts.count, 0, "icons only: no visible tab titles")
        // Quick actions is the round bowl button at the bar's right, not one of its tabs.
        let bowl = control("navigation.quickActions", in: app)
        XCTAssertTrue(bowl.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(bowl.frame.minX, bar.buttons["Train"].frame.maxX - 0.5, "beside the tabs, not over them")
        XCTAssertEqual(bowl.frame.width, bowl.frame.height, accuracy: 0.5, "a round button")
        // The bowl opens the quick actions without leaving the current tab.
        tap("navigation.quickActions", in: app)
        XCTAssertTrue(app.buttons["quickActions.logFood"].waitForExistence(timeout: 5))
        XCTAssertTrue(bar.buttons["Home"].isSelected)
        tap("quickActions.done", in: app)
        waitUntilGone(app.buttons["quickActions.done"])
        // The sheet also leads to Profile, which has no tab of its own.
        chooseQuickAction("profile", in: app)
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 8))
        // Shop provides an unobstructed header independent of transient Home banners.
        tap("tab.shop", in: app)
        XCTAssertTrue(bar.buttons["Shop"].isSelected)
        XCTAssertFalse(app.staticTexts["Best value in Lithuania"].exists)
        XCTAssertFalse(app.staticTexts["Everyday low prices"].exists)
        capture("system-tab-bar")
    }

    func testOnboardingAndTabsInLandscape() throws {
        let app = XCUIApplication()
        onboard(app)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        // Some headless simulators ignore rotation for every app (Apple's Settings
        // included). Check the screen itself turned; if it didn't, there's nothing
        // to test here, which is reported as a skip rather than an app failure.
        let deadline = Date().addingTimeInterval(4)
        var screen = XCUIScreen.main.screenshot().image.size
        while screen.width <= screen.height && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            screen = XCUIScreen.main.screenshot().image.size
        }
        if screen.width <= screen.height {
            throw XCTSkip("This simulator didn't rotate to landscape; check rotation on a device.")
        }
        tap("tab.home", in: app)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        for name in ["home", "meals", "shop", "train"] {
            tap("tab." + name, in: app)
            capture("landscape-" + name)
        }
    }

    func testOptionalAppleAccountDoesNotBlockLocalTabs() {
        let app = XCUIApplication()
        // The AI section shows only when online AI is offered; this checks its layout.
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO", "-onlineAIOffered_v1", "YES"]
        launchForTesting(app)
        openProfile(in: app)
        let signIn = app.buttons["profile.appleSignIn"]
        for _ in 0..<8 {
            if signIn.exists && signIn.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(signIn.frame.height, 44)
        tap("tab.home", in: app)
        XCTAssertTrue(control("tab.home", in: app).isSelected)
    }

    func testQuickActionsMenuOpensCartAndChecklist() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        launchForTesting(app)
        chooseQuickAction("cart", in: app)
        XCTAssertTrue(app.buttons["quickCart.done"].waitForExistence(timeout: 5))
        capture("quick-actions-cart")
        app.navigationBars["My Cart"].swipeDown()
        if app.buttons["quickCart.done"].exists && app.buttons["quickCart.done"].isHittable { tap("quickCart.done", in: app) }
        // The next tap only counts once the sheet has fully gone.
        waitUntilGone(app.buttons["quickCart.done"])
        XCTAssertTrue(control("navigation.quickActions", in: app).waitForExistence(timeout: 5))
        chooseQuickAction("groceries", in: app)
        XCTAssertTrue(app.buttons["groceries.done"].waitForExistence(timeout: 5))
        tap("groceries.done", in: app)
        XCTAssertTrue(control("tab.home", in: app).waitForExistence(timeout: 5))
    }

    func testQuickLoggerCustomServingDismissesAfterAdding() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        launchForTesting(app)
        chooseQuickAction("logFood", in: app)
        let foodSearch = app.textFields["logFood.search"]
        XCTAssertTrue(foodSearch.waitForExistence(timeout: 5))
        foodSearch.tap(); foodSearch.typeText("bananas raw")
        let apple = app.buttons["logFood.food.usda:173944"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        apple.tap()
        XCTAssertTrue(app.staticTexts["USDA SR Legacy · April 2018"].waitForExistence(timeout: 5))
        capture("nutrition-source-detail")
        tap("logFood.addServing", in: app)
        // The Add button plays a short "Added" success moment before the sheet closes.
        XCTAssertTrue(app.buttons["logFood.addServing"].waitForNonExistence(timeout: 15))
        XCTAssertTrue(control("navigation.quickActions", in: app).exists)
    }

    func testRestaurantMenuDishCanBeSavedAndLoggedPerServing() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        launchForTesting(app)
        chooseQuickAction("logFood", in: app)
        // A tap while the sheet is still sliding in can miss; retry until the dish editor shows.
        let menuMode = app.segmentedControls["customFood.mode"].buttons["Restaurant menu"]
        for _ in 0..<3 where !menuMode.exists {
            tap("logFood.createDishToolbar", in: app)
            if menuMode.waitForExistence(timeout: 8) { break }
        }
        XCTAssertTrue(menuMode.waitForExistence(timeout: 10))
        for _ in 0..<4 {
            menuMode.tap()
            if app.textFields["customFood.restaurant"].waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(app.textFields["customFood.restaurant"].exists, "Restaurant menu mode")
        for (id, value) in [("name", "QA Menu Plate"), ("restaurant", "QA Restaurant"), ("energy", "650"), ("protein", "35"), ("carbs", "80"), ("fat", "21")] {
            let field = app.textFields["customFood." + id]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            // A tap during the previous field's keyboard dismissal can miss; retry until focused.
            let focused = NSPredicate(format: "hasKeyboardFocus == true")
            for _ in 0..<3 {
                field.tap()
                if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 2) == .completed { break }
            }
            field.typeText(value)
            let done = app.buttons["customFood.keyboardDone"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap()
        }
        tap("customFood.save", in: app)
        XCTAssertTrue(app.staticTexts["Menu nutrition · entered by you"].waitForExistence(timeout: 5))
        // The kcal figure is a button now (tap it to type your own value); match it whatever it is.
        XCTAssertTrue((app.buttons["logFood.kcal"].value as? String ?? "").hasPrefix("650 kcal"), "kcal")
        capture("restaurant-menu-serving")
        tap("logFood.addServing", in: app)
        XCTAssertTrue(control("navigation.quickActions", in: app).waitForExistence(timeout: 5))
    }

    /// A spoken phrase (handed in as text, so no microphone) becomes a review
    /// card, and confirming it logs the food.
    func testVoiceCommandLogsFoodAfterConfirming() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloVoiceTestPhrase", "log two eggs for breakfast"]
        launchForTesting(app)
        // The microphone between My Stock and History opens the same sheet as "+" › Speak a command.
        tap("home.voice", in: app)
        XCTAssertTrue(app.buttons["voice.confirm"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["voice.slot"].exists)
        XCTAssertFalse(app.staticTexts["voice.missing"].exists)
        capture("voice-review")
        tap("voice.confirm", in: app)
        let result = app.staticTexts["voice.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.hasPrefix("Logged"), result.label)
        XCTAssertTrue(result.label.contains("breakfast"), result.label)
        XCTAssertTrue(app.buttons["voice.undo"].exists)
        capture("voice-done")
    }

    /// TestFlight: "Pridėk sausus pusryčius su pienu prie pusryčių" (add cereal with milk
    /// to breakfast) showed "Couldn't find". It is two foods for breakfast.
    func testVoiceCommandInLithuanianFindsCerealAndMilk() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-voiceLanguage_v1", "lt", "-NourloVoiceTestPhrase", "Pridėk sausus pusryčius su pienu prie pusryčių"]
        launchForTesting(app)
        tap("home.voice", in: app)
        XCTAssertTrue(app.buttons["voice.confirm"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["voice.missing"].exists, "nothing is missing")
        capture("voice-review-lithuanian")
    }

    /// Profile › Voice offers all nine languages, each in its own name.
    func testVoiceSettingsOffersEveryLanguage() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-voiceLanguage_v1", "ja"]
        launchForTesting(app)
        openProfile(in: app)
        tap("profile.voice", in: app)
        XCTAssertTrue(app.navigationBars["Voice"].waitForExistence(timeout: 5))
        capture("voice-settings-japanese")
        let picker = app.buttons["voice.language"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        for name in ["English", "Deutsch", "Español", "Français", "Русский", "Lietuvių", "العربية", "中文", "日本語"] {
            XCTAssertTrue(app.buttons[name].firstMatch.waitForExistence(timeout: 3), "\(name) is offered")
        }
        capture("voice-languages")
        app.buttons["Español"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Voice"].waitForExistence(timeout: 5))
        capture("voice-settings-spanish")
    }

    func testStockSearchAddConsumeAndHistory() {
        let app = XCUIApplication()
        // Starts from an empty kitchen: food other tests leave in stock would stay on the shelf.
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO", "-bowlGuideVisible_v2", "NO",
                               "-NourloEmptyKitchen"]
        launchForTesting(app)
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
        launchForTesting(app)
        chooseQuickAction("logFood", in: app)
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
        // The ingredient picker is still sliding away for a moment; wait until the field can be tapped.
        let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: yield)
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 8), .completed, "customFood.yield")
        yield.tap(); yield.typeText("200")
        tap("customFood.save", in: app)
        XCTAssertTrue(app.staticTexts["Your recipe · calculated estimate"].waitForExistence(timeout: 5))
        // The kcal figure is a button now (tap it to type your own value); match it whatever it is.
        XCTAssertTrue((app.buttons["logFood.kcal"].value as? String ?? "").hasPrefix("45 kcal"), "kcal")
        capture("recipe-source-and-yield")
        tap("logFood.addServing", in: app)
        XCTAssertTrue(control("navigation.quickActions", in: app).waitForExistence(timeout: 5))
    }

    func testStoreUsesNativeSwipeBackAndLargeQuantityTargets() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO"]
        launchForTesting(app)
        tap("tab.shop", in: app)
        tap("shop.catalog", in: app)
        let add = app.buttons["Add to cart"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(add.frame.width, 44 - 0.001)
        XCTAssertGreaterThanOrEqual(add.frame.height, 44 - 0.001)
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.navigationBars["Shop"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shop.catalog"].exists)
        capture("native-back-shop")
    }

    func testPrivacyAndSupportAreReachable() {
        let app = XCUIApplication()
        onboard(app)
        openProfile(in: app)
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
        for name in ["home", "meals", "shop", "train"] {
            tap("tab." + name, in: app)
            capture("largest-text-" + name)
        }
    }
}

extension XCUIApplication {
    /// A tab by its name: in the bottom tab bar on iPhone, in the floating bar at the top on iPad
    /// (iPadOS 18 and later put the tabs there, outside any tab bar element).
    func tab(_ name: String) -> XCUIElement {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        }
        return tabBars.buttons[name].firstMatch
    }
}
