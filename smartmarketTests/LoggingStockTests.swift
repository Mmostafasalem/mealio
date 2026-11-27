import XCTest
@testable import smartmarket

/// G2: every way of logging food takes the amount out of matching stock (soonest use-by
/// first), never twice, and an undo puts it back. The review cards say where it comes from.
@MainActor
final class LoggingStockTests: XCTestCase {

    private var suite = ""
    private var defaults: UserDefaults!
    private var stock: StockStore!
    private var log: FoodLogStore!

    override func setUp() {
        super.setUp()
        suite = "LoggingStockTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
        stock = StockStore(defaults: defaults)
        log = FoodLogStore(defaults: defaults, stock: stock)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    static func food(_ name: String, id: Int, kcal: Double = 100, basis: NutritionFood.Basis = .grams) -> NutritionFood {
        NutritionFood(id: "usda:\(id)", name: name, brand: nil, basis: basis, kcal: kcal, protein: 5, carbs: 10, fat: 3,
                      source: .usda, sourceID: "\(id)", sourceDate: nil)
    }

    private func amount(of id: String) -> Double {
        stock.items.filter { $0.food.id == id }.reduce(0) { $0 + $1.amount }
    }

    // MARK: Search and quick add (FoodLogStore.add, as HomeViewModel.logFood does)

    func testLoggingASearchedFoodTakesItOutOfStockAndUndoPutsItBack() throws {
        let bread = Self.food("Bread, whole-wheat", id: 1001)
        try stock.add(food: bread, amount: 500)
        let entry = FoodLogEntry(nutritionFood: bread, slot: .breakfast, amount: 60)
        let used = log.add(entry)
        XCTAssertEqual(used.first?.amount, 60)
        XCTAssertEqual(amount(of: bread.id), 440)
        XCTAssertEqual(stock.summary(afterLogging: entry.id, food: bread, amount: 60).left, 440)
        // Saved: a fresh store reads the same stock and what the entry took.
        XCTAssertEqual(StockStore(defaults: defaults).items.first?.amount, 440)
        XCTAssertEqual(StockStore(defaults: defaults).draws(for: entry.id).first?.amount, 60)
        log.remove(entry)
        XCTAssertEqual(amount(of: bread.id), 500, "undo puts the amount back")
        XCTAssertTrue(stock.draws(for: entry.id).isEmpty)
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testSoonestUseByComesOutFirstAndAUsedUpBatchComesBackOnUndo() throws {
        let milk = Self.food("Milk, whole", id: 1002, basis: .millilitres)
        let soon = Date().addingTimeInterval(86_400)
        let later = Date().addingTimeInterval(5 * 86_400)
        try stock.add(food: milk, amount: 1000, expiresAt: later)
        try stock.add(food: milk, amount: 200, expiresAt: soon)
        let entry = FoodLogEntry(nutritionFood: milk, slot: .breakfast, amount: 300)
        log.add(entry)
        XCTAssertEqual(stock.items.count, 1, "the 200 ml carton that expires first is used up")
        XCTAssertEqual(stock.items.first?.amount, 900, "the rest comes from the carton that keeps longer")
        log.remove(entry)
        XCTAssertEqual(stock.items.count, 2)
        XCTAssertEqual(amount(of: milk.id), 1200)
    }

    func testSameFoodByNameCountsButBrothIsNotChicken() throws {
        let rawEgg = Self.food("Egg, whole, raw, fresh", id: 1003)
        let broth = Self.food("Soup, chicken broth, ready-to-serve", id: 1004)
        try stock.add(food: rawEgg, amount: 600)
        try stock.add(food: broth, amount: 1000)
        let scrambled = Self.food("Egg, whole, cooked, scrambled", id: 1005)
        let chicken = Self.food("Chicken, broilers or fryers, breast, meat only, cooked, roasted", id: 1006)
        XCTAssertEqual(stock.summary(for: scrambled, amount: 100).name, "Egg, whole, raw, fresh")
        XCTAssertFalse(stock.summary(for: chicken, amount: 150).inStock, "chicken broth is not chicken")
        log.add(FoodLogEntry(nutritionFood: scrambled, slot: .breakfast, amount: 100))
        log.add(FoodLogEntry(nutritionFood: chicken, slot: .lunch, amount: 150))
        XCTAssertEqual(amount(of: rawEgg.id), 500)
        XCTAssertEqual(amount(of: broth.id), 1000)
    }

    func testMoreThanInStockTakesWhatThereIsAndSaysSo() throws {
        let rice = Self.food("Rice, white, long-grain, regular, raw, enriched", id: 1007)
        try stock.add(food: rice, amount: 50)
        let summary = stock.summary(for: rice, amount: 80)
        XCTAssertEqual(summary.left, 0)
        XCTAssertEqual(summary.short, 30, accuracy: 0.001)
        XCTAssertTrue(summary.text.contains("30 g more than you had"), summary.text)
        log.add(FoodLogEntry(nutritionFood: rice, slot: .dinner, amount: 80))
        XCTAssertTrue(stock.items.isEmpty)
    }

    func testReviewCardLine() throws {
        let bread = Self.food("Bread, whole-wheat", id: 1008).withPieces(20, name: "slice", package: 600)
        XCTAssertEqual(stock.summary(for: bread, amount: 60).text, "Not in your stock")
        try stock.add(food: bread, amount: 600)
        XCTAssertEqual(stock.summary(for: bread, amount: 60).text,
                       "From your stock: Bread, whole-wheat (540 g left after this, about 18 slices)")
    }

    // MARK: No double counting

    func testMyStocksOwnLoggingIsNotTakenTwice() throws {
        let apple = Self.food("Apples, raw, with skin", id: 1009)
        try stock.add(food: apple, amount: 500)
        let id = try XCTUnwrap(stock.items.first?.id)
        try stock.consume(id: id, amount: 180, slot: .snack)
        XCTAssertEqual(amount(of: apple.id), 320)
        XCTAssertEqual(log.entries.count, 1)
        // A dish logged without taking from stock (its ingredients are handled by the recipe).
        let entry = FoodLogEntry(nutritionFood: apple, slot: .snack, amount: 100)
        log.add(entry, takeFromStock: false)
        XCTAssertEqual(amount(of: apple.id), 320)
        XCTAssertTrue(stock.draws(for: entry.id).isEmpty)
    }

    func testPlannedMealFromStockStillLogsOnce() throws {
        let oats = Self.food("Oats", id: 1010)
        try stock.add(food: oats, amount: 500)
        try stock.consumeMeal([NutritionIngredient(food: oats, amount: 80)], slot: .breakfast, operationID: "plan-1")
        try stock.consumeMeal([NutritionIngredient(food: oats, amount: 80)], slot: .breakfast, operationID: "plan-1")
        XCTAssertEqual(amount(of: oats.id), 420)
    }

    // MARK: Plan rows (each planned portion logged)

    func testOneTapPlanRowTakesEachPortion() throws {
        let oats = Self.food("Oats", id: 1011)
        let banana = Self.food("Bananas, raw", id: 1012)
        try stock.add(food: oats, amount: 500)
        let entries = [NutritionIngredient(food: oats, amount: 60), NutritionIngredient(food: banana, amount: 120)]
            .map { FoodLogEntry(nutritionFood: $0.food, slot: .breakfast, amount: $0.amount) }
        entries.forEach { log.add($0) }
        XCTAssertEqual(amount(of: oats.id), 440)
        XCTAssertTrue(stock.draws(for: entries[1].id).isEmpty, "no banana in stock: nothing taken")
        entries.forEach { log.remove($0) }
        XCTAssertEqual(amount(of: oats.id), 500)
    }

    // MARK: Cookbook "I cooked this" and your own recipes

    func testCookedRecipeTakesItsIngredientsAndRemovingThePutsThemBack() throws {
        let rice = Self.food("Rice, white, long-grain, regular, raw, enriched", id: 1013)
        try stock.add(food: rice, amount: 1000)
        let line = CookbookRecipe.Line(text: "200 g rice", food: rice.name, grams: 200, match: "rice", pantry: nil)
        let entryID = UUID().uuidString
        let uses = CookbookCooking.uses(for: [line], items: stock.items)
        stock.takeOut(for: entryID, uses: uses)
        XCTAssertEqual(amount(of: rice.id), 800)
        XCTAssertTrue(stock.putBack(for: entryID))
        XCTAssertEqual(amount(of: rice.id), 1000)
    }

    func testOwnRecipeTakesTheCookedAmountsAndUndoRestores() throws {
        let pasta = Self.food("Pasta, dry, enriched", id: 1014, kcal: 371)
        let beef = Self.food("Beef, ground, 85% lean meat / 15% fat, raw", id: 1015, kcal: 215)
        try stock.add(food: pasta, amount: 500)
        try stock.add(food: beef, amount: 500)
        let parsed = RecipeTextParser.parse("Bolognese\nServes 4\n400 g spaghetti\n500 g minced beef")
        let draft = RecipeDraft(parsed, search: { name in name.contains("spaghetti") ? [pasta] : name.contains("beef") ? [beef] : [] })
        draft.scale = 0.5
        draft.eaten = 1
        let food = try XCTUnwrap(draft.food())
        XCTAssertEqual(food.basis, .serving)
        XCTAssertEqual(food.kcal, (371 * 4 + 215 * 5) / 4, accuracy: 0.5, "a serving stays the same when the recipe is halved")
        let entry = FoodLogEntry(nutritionFood: food, slot: .dinner, amount: draft.eaten)
        log.add(entry, takeFromStock: false)
        stock.takeOut(for: entry.id, ingredients: draft.ingredients)
        XCTAssertEqual(amount(of: pasta.id), 300)
        XCTAssertEqual(amount(of: beef.id), 250)
        log.remove(entry)
        XCTAssertEqual(amount(of: pasta.id), 500)
        XCTAssertEqual(amount(of: beef.id), 500)
    }

    // MARK: Voice and photo (shared stores, cleaned up)

    func testVoiceLoggingTakesFromStockAndUndoRestores() throws {
        let shared = StockStore.shared
        let burger = Self.food("Veggie burger, on bun", id: 1016, kcal: 224)
        try shared.add(food: burger, amount: 440)
        let id = try XCTUnwrap(shared.items.last?.id)
        defer { try? shared.remove(id: id) }
        let phrases = [VoiceFoodPhrase(name: "veggie burgers", quantity: 2, unit: nil)]
        let plan = VoiceCommandRunner.plan(for: .logFood(items: phrases, slot: .lunch), search: { _ in [burger] })
        guard case .food(let matches, _, _) = plan, let match = matches.first else { return XCTFail("no food plan") }
        XCTAssertEqual(match.amount, 220)
        XCTAssertEqual(match.summary, "2 × veggie burger · 220 g · 493 kcal")
        XCTAssertEqual(shared.summary(for: match.food, amount: match.amount).text,
                       "From your stock: Veggie burger, on bun (220 g left after this)")
        let outcome = VoiceCommandRunner.perform(plan)
        XCTAssertTrue(outcome.message.contains("Taken out of My Stock"), outcome.message)
        XCTAssertEqual(shared.items.first { $0.id == id }?.amount, 220)
        outcome.undo?()
        XCTAssertEqual(shared.items.first { $0.id == id }?.amount, 440)
    }

    func testMealPhotoLoggingTakesFromStockAtThePhotosTime() throws {
        let shared = StockStore.shared
        let rice = Self.food("Rice, white, cooked", id: 1017, kcal: 130)
        try shared.add(food: rice, amount: 300)
        let id = try XCTUnwrap(shared.items.last?.id)
        defer { try? shared.remove(id: id) }
        let taken = Date().addingTimeInterval(-3600)
        let plan = VoiceCommandRunner.plan(for: .logFood(items: [VoiceFoodPhrase(name: "rice", quantity: 150, unit: .gram)], slot: .lunch),
                                           search: { _ in [rice] })
        let outcome = VoiceCommandRunner.perform(plan, loggedAt: taken)
        XCTAssertEqual(shared.items.first { $0.id == id }?.amount, 150)
        let entry = try XCTUnwrap(FoodLogStore.shared.allEntries.last { $0.foodId == rice.id })
        XCTAssertEqual(entry.loggedAt.timeIntervalSince1970, taken.timeIntervalSince1970, accuracy: 1)
        outcome.undo?()
        XCTAssertEqual(shared.items.first { $0.id == id }?.amount, 300)
    }
}
