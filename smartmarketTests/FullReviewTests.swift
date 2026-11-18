import XCTest
@testable import smartmarket

/// The data and logic fixes from the full review, each pinned to the case that went wrong.
@MainActor
final class FullReviewTests: XCTestCase {

    // MARK: Search

    func testSearchLeadsWithTheFoodItself() {
        let catalog = NutritionCatalogService.shared
        func top(_ query: String, _ n: Int = 12) -> [String] { catalog.searchLocal(query).prefix(n).map { $0.name.lowercased() } }
        XCTAssertTrue(top("chicken").contains { $0.hasPrefix("chicken") && $0.contains("breast") }, "chicken breast is near the top")
        XCTAssertTrue(top("chicken").allSatisfy { $0.hasPrefix("chicken") })
        XCTAssertTrue(top("rice", 10).contains { $0.hasPrefix("rice,") && ($0.contains("cooked") || $0.contains("raw")) })
        XCTAssertTrue(top("egg", 6).contains { $0.hasPrefix("egg, whole") })
        XCTAssertFalse(top("tea", 20).contains { $0.contains("steak") }, "letters inside another word don't match")
        XCTAssertFalse(catalog.searchLocal("yoghurt").isEmpty, "both spellings find yogurt")
    }

    // MARK: Recipes

    func testNoMeatRecipeIsTaggedVegetarianOrHalal() {
        let meat: Set<String> = ["chicken", "pork", "beef", "lamb", "turkey", "ham", "bacon", "sausage", "fish", "salmon", "tuna", "shrimp"]
        for r in CookbookLibrary.recipes {
            let terms = Set(r.ingredients.flatMap(\.terms))
            if r.tags.contains("vegetarian") { XCTAssertTrue(terms.isDisjoint(with: meat), r.title) }
            if r.tags.contains("noPork") || r.tags.contains("halal") { XCTAssertFalse(terms.contains("pork"), r.title) }
            XCTAssertLessThanOrEqual(r.perServing.kcal, 1500, r.title)
            XCTAssertLessThanOrEqual(r.gramsPerServing, 1300, r.title)
        }
    }

    func testStockMatchingKnowsPeanutButterIsNotButter() {
        func line(_ match: String) -> CookbookRecipe.Line { .init(text: match, food: nil, grams: 100, match: match, pantry: false) }
        let kitchen = KitchenMatcher(names: ["Peanut butter, smooth style", "Noodles, egg, enriched, cooked", "Tomato, paste, canned",
                                             "Peppers, sweet, red, raw", "Fish, salmon, Atlantic, farmed, raw", "Butter, salted"])
        XCTAssertTrue(kitchen.has(line("butter")), "real butter still counts")
        XCTAssertFalse(KitchenMatcher(names: ["Peanut butter, smooth style"]).has(line("butter")))
        XCTAssertFalse(kitchen.has(line("egg")))
        XCTAssertFalse(kitchen.has(line("tomato")))
        XCTAssertTrue(kitchen.has(line("sweet pepper|bell pepper")))
        XCTAssertTrue(kitchen.has(line("salmon")))
    }

    // MARK: Diets

    func testDietsMatchWholeWords() {
        XCTAssertTrue(Set<DietaryPreference>([.glutenFree]).allows(name: "Buckwheat", category: "grains"), "buckwheat isn't wheat")
        XCTAssertTrue(Set<DietaryPreference>([.vegan]).allows(name: "Eggplant", category: "vegetables"))
        XCTAssertTrue(Set<DietaryPreference>([.vegan]).allows(name: "Butternut Squash", category: "vegetables"))
        XCTAssertFalse(Set<DietaryPreference>([.vegan]).allows(name: "Eggs 10-pack", category: "eggs"))
        XCTAssertFalse(Set<DietaryPreference>([.halal]).allows(name: "Chicken Breast", category: "meat"), "unlabelled meat isn't suggested")
        XCTAssertTrue(Set<DietaryPreference>([.halal]).allows(name: "Chicken Breast", category: "meat", owned: true), "the person's own meat is their call")
        XCTAssertFalse(Set<DietaryPreference>([.halal]).allows(name: "Pork Chops", category: "meat", owned: true))
        XCTAssertTrue(Set<DietaryPreference>([.halal]).allows(name: "Tuna Steak", category: "seafood"))
    }

    // MARK: Portions

    func testPlatesHoldSensibleAmountsOfDryRice() throws {
        _ = NutritionCatalogService.shared
        StockStore.shared.clearItems()
        let cart = ["chicken-breast": "meat", "basmati-rice": "grains", "broccoli": "vegetables", "oats": "grains",
                    "banana": "fruits", "greek-yogurt": "dairy", "almonds": "nuts"]
            .map { entry in CartItem(id: UUID(), catalogId: entry.key, name: CatalogItem.all.first { c in c.id == entry.key }?.name ?? entry.key,
                                     store: "Catalogue", price: 2, category: entry.value, quantity: 1) }
        UserDefaults.standard.set(try JSONEncoder().encode(cart), forKey: "shoppingCart_v1")
        defer { UserDefaults.standard.removeObject(forKey: "shoppingCart_v1") }
        let plan = FallbackData.mealPlan(targetKcal: 2000, preferences: [], variation: 0)
        let day = try XCTUnwrap(plan.allDays.first?.plan)
        XCTAssertEqual(Double(day.visoKcal ?? 0), 2000, accuracy: 160, "the day still reaches the target")
        let lunch = try XCTUnwrap(day.pietus?.nutritionIngredients)
        let rice = try XCTUnwrap(lunch.first { $0.food.name.lowercased().hasPrefix("rice") })
        XCTAssertLessThanOrEqual(rice.amount, 150, "about a cup of dry rice at most, not 250 g")
        let chicken = try XCTUnwrap(lunch.first { $0.food.name.lowercased().hasPrefix("chicken") })
        XCTAssertGreaterThanOrEqual(chicken.amount, 150, "the protein is a real portion")
    }

    func testAPotatoPlateStillReachesItsShare() throws {
        _ = NutritionCatalogService.shared
        StockStore.shared.clearItems()
        let cart = ["chicken-breast": "meat", "potato": "vegetables", "broccoli": "vegetables", "oats": "grains",
                    "banana": "fruits", "greek-yogurt": "dairy", "almonds": "nuts"]
            .map { entry in CartItem(id: UUID(), catalogId: entry.key, name: CatalogItem.all.first { c in c.id == entry.key }?.name ?? entry.key,
                                     store: "Catalogue", price: 2, category: entry.value, quantity: 1) }
        UserDefaults.standard.set(try JSONEncoder().encode(cart), forKey: "shoppingCart_v1")
        defer { UserDefaults.standard.removeObject(forKey: "shoppingCart_v1") }
        let day = try XCTUnwrap(FallbackData.mealPlan(targetKcal: 2000, preferences: [], variation: 0).allDays.first?.plan)
        XCTAssertGreaterThanOrEqual(day.visoKcal ?? 0, 1800, "potatoes as the carb no longer leave the day at 83%")
    }

    // MARK: Shop

    func testShopItemsGetSensiblePacksAndRecords() throws {
        _ = NutritionCatalogService.shared
        func item(_ id: String) throws -> CatalogItem { try XCTUnwrap(CatalogItem.all.first { $0.id == id }) }
        func pack(_ id: String) throws -> Double {
            let i = try item(id)
            return CartStockLink.packAmount(for: i, food: try XCTUnwrap(CartStockLink.food(for: i)))
        }
        XCTAssertEqual(try pack("milk-25"), 1000, "a litre of milk")
        XCTAssertEqual(try pack("lemon"), 100)
        XCTAssertEqual(try pack("eggs-6"), 330)
        XCTAssertEqual(try pack("chickpeas-canned"), 400)
        XCTAssertEqual(CartStockLink.food(for: try item("chicken-broth"))?.name, "Soup, chicken broth, ready-to-serve")
        XCTAssertEqual(CartStockLink.food(for: try item("frozen-shrimp"))?.name, "Crustaceans, shrimp, raw")
        // Every shop food that plays a part in the plan has a record, so it reaches My Stock.
        for i in CatalogItem.all where FallbackData.planRole(name: i.name, category: i.category.rawValue) != nil {
            XCTAssertNotNil(CartStockLink.food(for: i), i.name)
        }
    }

    func testWeeklyResetIsNotAskedAgainAfterATimeZoneMove() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FullReviewTests.week"))
        defaults.removePersistentDomain(forName: "FullReviewTests.week")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Vilnius"))
        calendar.firstWeekday = 2
        let wednesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12)))
        XCTAssertFalse(WeeklyReset.isDue(now: wednesday, hasSomething: true, defaults: defaults, calendar: calendar))
        var london = calendar
        london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        XCTAssertFalse(WeeklyReset.isDue(now: wednesday.addingTimeInterval(86_400), hasSomething: true, defaults: defaults, calendar: london),
                       "the same week, two hours west")
        XCTAssertTrue(WeeklyReset.isDue(now: wednesday.addingTimeInterval(7 * 86_400), hasSomething: true, defaults: defaults, calendar: london))
    }
}
