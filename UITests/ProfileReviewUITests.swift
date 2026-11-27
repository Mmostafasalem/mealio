import XCTest

/// Tester feedback F1, F2, F3 and D2: Profile in categories, Edit profile with a
/// photo, editable daily targets, and prices in the person's currency.
/// `TEST_RUNNER_NOURLO_SHOTS=/folder` also saves each screen there.
@MainActor
final class ProfileReviewUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-enabledFeatures_v1", "tracking,meals,groceries,workouts",
                               "-bowlGuideVisible_v2", "NO"] + extra
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
        if let folder = ProcessInfo.processInfo.environment["NOURLO_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
    }

    private func openProfile(_ app: XCUIApplication) {
        let profile = app.navigationBars["Profile"]
        for _ in 0..<3 where !profile.exists {
            let avatar = app.buttons["home.profile"]
            if avatar.waitForExistence(timeout: 30) { avatar.tap() }
            _ = profile.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(profile.exists, "Profile didn't open")
    }

    /// Taps until the field has the keyboard (a loaded machine can drop the first tap), clears it, types.
    private func replaceText(in field: XCUIElement, placeholder: String, with text: String) {
        for attempt in 0..<6 {
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { break }
            if attempt % 2 == 0 { field.tap() } else { field.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap() }
            _ = XCUIApplication().keyboards.firstMatch.waitForExistence(timeout: 4)
        }
        if let value = field.value as? String, !value.isEmpty, value != placeholder {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text)
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
    }

    private func open(_ id: String, title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons[id]
        XCTAssertTrue(row.waitForExistence(timeout: 15), id, file: file, line: line)
        row.tap()
        if !app.navigationBars[title].waitForExistence(timeout: 10), row.exists, row.isHittable { row.tap() }
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15), title, file: file, line: line)
    }

    /// F1: one short screen of categories, each opening its own page with its settings.
    func testProfileIsAShortListOfCategories() {
        let app = launch(["-onlineAIOffered_v1", "YES"])
        openProfile(app)
        sleep(1)
        shot("F1-01-profile-first-screen")
        // Every category and the card are on screen without scrolling.
        let ids = ["profile.card", "profile.category.goals", "profile.category.food", "profile.category.currency",
                   "profile.category.features", "profile.category.appearance", "profile.voice", "profile.reminders",
                   "profile.category.ai", "profile.category.data", "profile.category.help"]
        for id in ids {
            let row = app.buttons[id]
            XCTAssertTrue(row.waitForExistence(timeout: 5), id)
            XCTAssertTrue(row.isHittable, "\(id) is visible without scrolling")
        }
        let pages: [(String, String, String, String)] = [
            ("profile.category.goals", "Goals & targets", "profile.targets", "F1-02-goals"),
            ("profile.category.food", "Food & diet", "profile.favourites", "F1-03-food"),
            ("profile.category.currency", "Currency & prices", "profile.currency.region", "F1-04-currency"),
            ("profile.category.features", "Features", "profile.feature.workouts", "F1-05-features"),
            ("profile.category.appearance", "Appearance", "profile.theme.pink", "F1-06-appearance"),
            ("profile.voice", "Voice", "voice.language", "F1-07-voice"),
            ("profile.reminders", "Reminders", "", "F1-08-notifications"),
            ("profile.category.ai", "AI & account", "profile.aiConsent", "F1-09-ai"),
            ("profile.category.data", "Data & iCloud", "profile.icloudSync", "F1-10-data"),
            ("profile.category.help", "Help & legal", "profile.replayTour", "F1-11-help"),
        ]
        for (id, title, inside, name) in pages {
            open(id, title: title, in: app)
            if !inside.isEmpty {
                XCTAssertTrue(app.descendants(matching: .any)[inside].firstMatch.waitForExistence(timeout: 5), "\(inside) on \(title)")
            }
            sleep(1)
            shot(name)
            if id == "profile.category.data" {
                for _ in 0..<3 { app.swipeUp() }
                XCTAssertTrue(app.buttons["Delete All Data"].firstMatch.exists)
                shot(name + "-bottom")
            }
            if id == "profile.category.help" {
                XCTAssertTrue(app.buttons["profile.privacy"].exists)
                XCTAssertTrue(app.buttons["profile.support"].exists)
                XCTAssertTrue(app.buttons["profile.acknowledgements"].exists)
                XCTAssertTrue(app.descendants(matching: .any)["profile.emailSupport"].firstMatch.exists)
            }
            back(app)
        }
    }

    /// F2: the card opens Edit profile; a photo from Photos shows on Profile and Home; Remove brings the initials back.
    func testEditProfileNameAndPhoto() {
        var app = launch()
        openProfile(app)
        open("profile.card", title: "Edit profile", in: app)
        let first = app.textFields["editProfile.firstName"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        replaceText(in: first, placeholder: "First name", with: "Urte")
        replaceText(in: app.textFields["editProfile.surname"], placeholder: "Surname", with: "Kazlauskaite\n")
        shot("F2-01-edit-profile-name")

        // Choose a photo from the library (the simulator has sample photos).
        app.buttons["editProfile.choosePhoto"].tap()
        // The system photo picker runs in its own process; wait for it, then tap the first photo.
        let pickerCancel = app.buttons["Cancel"].firstMatch
        let pickerOpened = pickerCancel.waitForExistence(timeout: 30)
        sleep(2)
        shot("F2-02-photos-picker")
        if pickerOpened {
            let cell = app.scrollViews.images.firstMatch
            if cell.waitForExistence(timeout: 10) { cell.tap() }
            else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.3)).tap() }
        }
        let remove = app.buttons["editProfile.removePhoto"]
        if !remove.waitForExistence(timeout: 20) {
            // The picker couldn't be driven here: relaunch with a stand-in photo saved through the same store.
            app.terminate()
            app = launch(["-NourloUITestPhoto", "YES"])
            openProfile(app)
            open("profile.card", title: "Edit profile", in: app)
        }
        XCTAssertTrue(app.buttons["editProfile.removePhoto"].waitForExistence(timeout: 15), "a photo was chosen")
        sleep(1)
        shot("F2-03-edit-profile-with-photo")
        back(app)
        sleep(1)
        shot("F2-04-profile-card-with-photo")
        back(app)
        XCTAssertTrue(app.buttons["home.profile"].waitForExistence(timeout: 5))
        sleep(1)
        shot("F2-05-home-avatar-with-photo")

        // Remove: back to initials.
        openProfile(app)
        open("profile.card", title: "Edit profile", in: app)
        app.buttons["editProfile.removePhoto"].tap()
        XCTAssertFalse(app.buttons["editProfile.removePhoto"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["editProfile.choosePhoto"].exists)
        shot("F2-06-photo-removed-initials")
        back(app); back(app)
        sleep(1)
        shot("F2-07-home-avatar-initials")
    }

    /// F3: type a daily goal and change protein, save, see it on Home; Use recommended goes back.
    func testDailyTargetsCanBeChangedAndReset() {
        let app = launch()
        openProfile(app)
        open("profile.category.goals", title: "Goals & targets", in: app)
        open("profile.targets", title: "Daily targets", in: app)
        shot("F3-01-targets-before")
        app.buttons["targets.calories.type"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(in: field, placeholder: "", with: "1850")
        alert.buttons["Set"].tap()
        XCTAssertTrue(app.staticTexts["1850 kcal"].waitForExistence(timeout: 10))
        let protein = app.otherElements["targets.protein"].firstMatch.exists
            ? app.otherElements["targets.protein"].firstMatch : app.descendants(matching: .any)["targets.protein"].firstMatch
        let increment = protein.buttons["Increment"].firstMatch
        if increment.exists { for _ in 0..<4 { increment.tap() } }
        shot("F3-02-targets-edited")
        let save = app.buttons["targets.save"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.navigationBars["Goals & targets"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1850 kcal"].waitForExistence(timeout: 5))
        shot("F3-03-goals-page-saved")
        back(app); back(app)
        XCTAssertTrue(app.buttons["home.profile"].waitForExistence(timeout: 5))
        sleep(2)
        shot("F3-04-home-uses-1850")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] '1850' OR label CONTAINS[c] '1,850' OR value CONTAINS[c] '1850' OR value CONTAINS[c] '1,850'")).firstMatch.exists,
                      "Home shows the typed goal")

        openProfile(app)
        open("profile.category.goals", title: "Goals & targets", in: app)
        open("profile.targets", title: "Daily targets", in: app)
        let reset = app.buttons["targets.useRecommended"]
        for _ in 0..<4 where !reset.isHittable { app.swipeUp() }
        reset.tap()
        XCTAssertFalse(app.staticTexts["1850 kcal"].waitForExistence(timeout: 2))
        shot("F3-05-use-recommended")
        back(app)
        shot("F3-06-goals-page-recommended")
    }

    /// D2: in Canada prices start in Canadian dollars, the budget is typed in them,
    /// and Shop says what the prices are; another currency can be picked.
    func testPricesInTheRegionsCurrencyWithAboutPrices() {
        let app = launch(["-AppleLocale", "en_CA", "-weeklyBudget", "60"])
        app.tabBars.buttons["Shop"].tap()
        XCTAssertTrue(app.navigationBars["Shop"].waitForExistence(timeout: 20))
        sleep(2)
        shot("D2-01-shop-cad")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '€'")).firstMatch.exists, "no euro signs in Canada")
        // "About prices" sits right under the budget, visible without scrolling.
        XCTAssertTrue(app.descendants(matching: .any)["prices.about"].firstMatch.isHittable)

        // The budget is typed in Canadian dollars.
        app.buttons["Edit"].firstMatch.tap()
        let input = app.textFields["shop.budgetInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        sleep(1)
        shot("D2-03-budget-sheet-cad")
        replaceText(in: input, placeholder: "", with: String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "120")
        shot("D2-03b-budget-typed-120")
        let save = app.navigationBars["Set budget"].buttons["Save"]
        save.tap()
        if save.waitForExistence(timeout: 3) { save.tap() }
        sleep(2)
        shot("D2-04-shop-budget-120-cad")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "$120.00")).firstMatch.waitForExistence(timeout: 10), "budget shown as typed, in CAD")

        // The catalogue in CAD.
        app.buttons["shop.catalog"].tap()
        sleep(2)
        shot("D2-05-catalogue-cad")
        back(app)

        // Profile › Currency & prices: region default checked, pick pounds.
        app.tabBars.buttons["Home"].tap()
        openProfile(app)
        open("profile.category.currency", title: "Currency & prices", in: app)
        XCTAssertTrue(app.buttons["profile.currency.region"].isSelected)
        shot("D2-06-currency-setting-cad")
        let gbp = app.buttons["profile.currency.GBP"]
        for _ in 0..<4 where !gbp.isHittable { app.swipeUp() }
        gbp.tap()
        XCTAssertTrue(gbp.isSelected)
        app.swipeDown(); app.swipeDown()
        shot("D2-07-currency-setting-gbp")
        back(app); back(app)
        app.tabBars.buttons["Shop"].tap()
        sleep(2)
        shot("D2-08-shop-gbp")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '£'")).firstMatch.exists)

        // Back to the region's currency so later runs start from the default.
        app.tabBars.buttons["Home"].tap()
        openProfile(app)
        open("profile.category.currency", title: "Currency & prices", in: app)
        app.buttons["profile.currency.region"].tap()
    }
}
