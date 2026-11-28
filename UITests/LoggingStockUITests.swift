import XCTest

/// TestFlight G1–G5 (docs/TESTER_FEEDBACK.md): logging takes food out of My Stock and the
/// review cards say from which item; counts × unit on the voice card; pieces per package;
/// "Amount in package" filled from the barcode; meal photos saved to clarify; recipes you follow.
/// Screenshots go to /tmp/r2-log as well as the test report.
@MainActor
final class LoggingStockUITests: XCTestCase {

    private static let folder = "/tmp/r2-log"

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
        try? FileManager.default.createDirectory(atPath: Self.folder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "\(Self.folder)/\(name).png"))
    }

    /// Waits (the simulator can be slow) and leaves a screenshot when it never shows.
    private func wait(_ element: XCUIElement, _ name: String, timeout: TimeInterval = 40) -> Bool {
        if element.waitForExistence(timeout: timeout) { return true }
        shot("debug-missing-" + name + "-" + String(UUID().uuidString.prefix(4)))
        return false
    }

    /// Taps until `next` shows (a tap while a sheet is still settling can be lost).
    private func tap(_ button: XCUIElement, until next: XCUIElement) {
        for _ in 0..<4 {
            if button.exists, button.isHittable { button.tap() }
            if next.waitForExistence(timeout: 12) { return }
        }
    }

    /// Types once the field really has the keyboard (a tap during a sheet's slide can miss).
    private func type(_ text: String, into field: XCUIElement) {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<5 {
            field.tap()
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 4) == .completed { break }
        }
        field.typeText(text)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-NourloEmptyKitchen",
                               "-enabledFeatures_v1", "tracking,meals,groceries,workouts", "-voiceLanguage_v1", "en"] + extra
        app.launch()
        return app
    }

    private func quickAction(_ id: String, in app: XCUIApplication) {
        let plus = app.buttons["navigation.quickActions"].firstMatch
        XCTAssertTrue(wait(plus, "plus"))
        let row = app.buttons["quickActions." + id].firstMatch
        for _ in 0..<3 {
            if !row.exists { plus.tap() }
            if row.waitForExistence(timeout: 8), row.isHittable {
                row.tap()
                // A tap while the panel is still settling can be lost: tap again until it closes.
                for _ in 0..<3 where !row.waitForNonExistence(timeout: 6) { if row.isHittable { row.tap() } }
                return
            }
        }
        XCTFail("quick action \(id) not found")
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, up: Bool = false) {
        for _ in 0..<14 where !(element.exists && element.isHittable) { up ? app.swipeDown() : app.swipeUp() }
    }

    private func stockAmount(_ app: XCUIApplication, id: String) -> String {
        let row = app.buttons["stock.item." + id]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "stock row \(id)")
        return row.label
    }

    // MARK: G2 + G3: voice

    func testVoiceCardShowsCountGramsKcalAndStockAndLoggingTakesItOut() {
        continueAfterFailure = false
        let app = launch(["-NourloVoiceTestPhrase", "I had 2 veggie burgers for lunch",
                          "-NourloSeedStock", "Veggie burger, on bun=440"])
        quickAction("voice", in: app)
        let confirm = app.buttons["voice.confirm"]
        XCTAssertTrue(wait(confirm, "confirm"))
        let summary = app.staticTexts["voice.food.summary"]
        XCTAssertTrue(wait(summary, "summary"))
        XCTAssertEqual(summary.label, "2 × veggie burger · 220 g · 493 kcal")
        let line = app.descendants(matching: .any)["stockLine.from"].firstMatch
        XCTAssertTrue(line.exists, "the card says which stock item it comes from")
        XCTAssertTrue(line.label.contains("From your stock: Veggie burger, on bun (220 g left after this)"), line.label)
        shot("G3-G2b-voice-card-2-veggie-burgers")

        // The count can be changed: one more burger is 330 g.
        app.buttons["One more"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["3 × veggie burger · 330 g · 739 kcal"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any)["stockLine.from"].firstMatch.label.contains("110 g left after this"))
        shot("G3-voice-card-count-changed-to-3")
        app.buttons["One fewer"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["2 × veggie burger · 220 g · 493 kcal"].waitForExistence(timeout: 30))

        confirm.tap()
        if !app.staticTexts["voice.result"].waitForExistence(timeout: 15), confirm.exists { confirm.tap() }
        let result = app.staticTexts["voice.result"]
        XCTAssertTrue(wait(result, "result"))
        XCTAssertTrue(result.label.contains("Taken out of My Stock"), result.label)
        shot("G2a-voice-logged-taken-out-of-stock")
        app.buttons["voice.done"].tap()

        // My Stock now holds 220 g.
        quickAction("stock", in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stock.item.'")).firstMatch
        XCTAssertTrue(wait(row, "row"))
        XCTAssertTrue(row.label.contains("220 g available"), row.label)
        shot("G2a-my-stock-after-voice-220g-left")
    }

    // MARK: G2: search and quick add, G4: pieces

    func testSearchedFoodShowsStockLinePiecesAndComesOutOfStock() {
        continueAfterFailure = false
        let app = launch(["-NourloSeedStock", "Bread, whole-wheat, commercially prepared=600:20:slice"])
        quickAction("logFood", in: app)
        let search = app.textFields["logFood.search"]
        XCTAssertTrue(wait(search, "search"))
        type("whole-wheat bread commercially prepared", into: search)
        let food = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'logFood.food.' AND label CONTAINS[c] 'whole-wheat, commercially prepared'")).firstMatch
        XCTAssertTrue(wait(food, "food"))
        tap(food, until: app.descendants(matching: .any)["logFood.pieces"].firstMatch)
        // Pieces from the stock item: 600 g in 20 slices, so a slice is 30 g.
        let pieces = app.descendants(matching: .any)["logFood.pieces"].firstMatch
        XCTAssertTrue(wait(pieces, "pieces"), "logging by pieces")
        let line = app.descendants(matching: .any)["stockLine.from"].firstMatch
        XCTAssertTrue(line.exists)
        shot("G4-log-by-pieces-and-G2b-stock-line")
        // Two slices: 60 g.
        app.buttons["Half fewer"].firstMatch.tap()
        app.buttons["Half fewer"].firstMatch.tap()
        app.buttons["Half fewer"].firstMatch.tap()
        XCTAssertTrue(wait(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '2 slices'")).firstMatch, "two-slices"))
        XCTAssertTrue(app.descendants(matching: .any)["stockLine.from"].firstMatch.label.contains("540 g left after this, about 18 slices"),
                      app.descendants(matching: .any)["stockLine.from"].firstMatch.label)
        shot("G4-two-slices-60g")
        app.swipeUp()
        shot("G2b-search-stock-line-540g-left")
        app.buttons["logFood.addServing"].tap()
        XCTAssertTrue(app.buttons["logFood.addServing"].waitForNonExistence(timeout: 60))

        quickAction("stock", in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stock.item.'")).firstMatch
        XCTAssertTrue(wait(row, "row"))
        XCTAssertTrue(row.label.contains("540 g available"), row.label)
        shot("G2a-my-stock-after-search-log-540g")
    }

    // MARK: G5 + G4: add to stock from a barcode

    func testAddToStockSaysAmountInPackageAndFillsItFromTheBarcode() throws {
        continueAfterFailure = false
        let app = launch()
        quickAction("stock", in: app)
        let add = app.buttons["stock.add"]
        XCTAssertTrue(wait(add, "add"))
        let search = app.textFields["logFood.search"]
        tap(add, until: search)
        XCTAssertTrue(wait(search, "search"))
        // A typed barcode takes the scanner's path (Président Emmental 250 g, Open Food Facts).
        type("3228021170022\n", into: search)
        let facts = app.descendants(matching: .any)["logFood.packageFacts"].firstMatch
        guard facts.waitForExistence(timeout: 25) else {
            shot("G5-barcode-lookup-offline")
            throw XCTSkip("Open Food Facts could not be reached from the simulator")
        }
        XCTAssertTrue(app.staticTexts["Amount in package"].exists)
        XCTAssertFalse(app.staticTexts["Serving"].exists, "never \"Serving\" for the package")
        XCTAssertTrue(app.buttons["logFood.preset.package"].exists, "the package size from the barcode")
        XCTAssertTrue(app.buttons["logFood.preset.serving"].exists, "the serving size from the barcode")
        shot("G5-add-to-stock-amount-in-package-from-barcode")
        app.swipeUp(); app.swipeUp()
        shot("G5-package-facts-and-rounded-nutrition")
        // Pieces in package: typed, 10 slices.
        let piecesControl = app.descendants(matching: .any)["logFood.piecesInPackage"].firstMatch
        scrollTo(piecesControl, in: app, up: true)
        for _ in 0..<10 { app.buttons["More pieces"].firstMatch.tap() }
        shot("G4-pieces-in-package-typed")
    }

    // MARK: G1a: a meal photo saved to clarify later

    func testSavedMealPhotoCanBeFinishedLater() {
        continueAfterFailure = false
        let app = launch(["-NourloSeedPendingPhoto", "YES"])
        quickAction("logFood", in: app)
        let pending = app.buttons["logFood.toClarify"].firstMatch
        XCTAssertTrue(wait(pending, "pending"), "To clarify on the food logger")
        shot("G1a-to-clarify-in-add-food")
        let addFood = app.buttons["clarify.addFood"]
        tap(pending, until: addFood)
        XCTAssertTrue(wait(addFood, "addFood"))
        shot("G1a-clarify-meal-photo-and-time")
        let search = app.textFields["pickFood.search"]
        tap(addFood, until: search)
        XCTAssertTrue(wait(search, "search"))
        type("bananas raw", into: search)
        let banana = app.buttons["logFood.food.usda:173944"]
        XCTAssertTrue(wait(banana, "banana"))
        tap(banana, until: app.buttons["logFood.addServing"])
        app.buttons["logFood.addServing"].tap()
        let log = app.buttons["clarify.log"]
        XCTAssertTrue(wait(log, "log"))
        XCTAssertTrue(log.isEnabled)
        shot("G1a-clarify-with-food-picked")
        log.tap()
        XCTAssertTrue(app.descendants(matching: .any)["clarify.done"].firstMatch.waitForExistence(timeout: 30))
        shot("G1a-clarify-logged")
    }

    // MARK: G1b: a recipe I'm following

    func testRecipeFromPastedTextAsksServingsAndScales() {
        continueAfterFailure = false
        let recipe = "Spaghetti bolognese|Serves 4|Ingredients|400 g spaghetti|500 g minced beef|1 onion|2 tbsp olive oil|400 g chopped tomatoes|Salt to taste|Method|Cook everything."
        let app = launch(["-NourloRecipeTestText", recipe, "-NourloSeedStock", "Pasta, dry, enriched=500"])
        quickAction("logFood", in: app)
        let add = app.buttons["logFood.addRecipe"]
        XCTAssertTrue(wait(add, "add"))
        let read = app.buttons["recipe.read"]
        tap(add, until: read)
        XCTAssertTrue(wait(read, "read"))
        shot("G1b-add-a-recipe-paste")
        tap(read, until: app.staticTexts["How many servings does this recipe make?"])
        XCTAssertTrue(wait(app.staticTexts["How many servings does this recipe make?"], "servings"))
        XCTAssertTrue(app.staticTexts["How many did you eat?"].exists)
        shot("G1b-recipe-servings-and-eaten")
        let doubled = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Now it makes 8 servings'")).firstMatch
        tap(app.buttons["recipe.scale.2"], until: doubled)
        XCTAssertTrue(wait(doubled, "doubled"))
        shot("G1b-recipe-doubled")
        app.swipeUp(); app.swipeUp()
        shot("G1b-recipe-ingredients-with-stock")
        let done = app.descendants(matching: .any)["recipe.done"].firstMatch
        tap(app.buttons["recipe.logToolbar"], until: done)
        XCTAssertTrue(wait(done, "done"))
        shot("G1b-recipe-logged")
    }
}
