import XCTest
@testable import smartmarket

@MainActor
final class CookbookTests: XCTestCase {

    private func line(_ text: String, match: String?, grams: Double? = 100, pantry: Bool = false) -> CookbookRecipe.Line {
        CookbookRecipe.Line(text: text, food: "usda:1", grams: grams, match: match, pantry: pantry)
    }

    private func recipe(_ id: String, _ lines: [CookbookRecipe.Line], tags: [String] = ["vegetarian"],
                        course: CookbookRecipe.Course = .main, carbs: Double = 30) -> CookbookRecipe {
        CookbookRecipe(id: id, title: id.capitalized, url: "https://en.wikibooks.org/wiki/Cookbook:\(id)", course: course,
                       servings: 2, servingsEstimated: false, minutes: 20, difficulty: 1, ingredients: lines,
                       steps: ["Mix.", "Cook."], perServing: .init(kcal: 400, protein: 20, carbs: carbs, fat: 10),
                       gramsPerServing: 300, tags: tags)
    }

    func testTheBundledCookbookLoadsWithOverAThousandValidRecipes() throws {
        let recipes = CookbookLibrary.recipes
        XCTAssertGreaterThan(recipes.count, 1000)
        XCTAssertEqual(Set(recipes.map(\.id)).count, recipes.count, "ids are unique")
        XCTAssertNotNil(CookbookLibrary.file?.credit.contains("CC BY-SA 4.0"))
        for r in recipes {
            XCTAssertTrue(r.servingFood.isValid, r.title)
            XCTAssertTrue(r.url.hasPrefix("https://en.wikibooks.org/wiki/"), r.title)
            XCTAssertGreaterThanOrEqual(r.steps.count, 2, r.title)
            XCTAssertGreaterThan(r.servings, 0, r.title)
        }
    }

    func testKitchenNamesMatchTheWayUSDANamesAreWritten() {
        let kitchen = KitchenMatcher(names: ["Eggs, Grade A, Large, egg whole", "Peppers, sweet, red, raw", "Tomatoes, red, ripe, raw"])
        XCTAssertTrue(kitchen.has(line("2 eggs", match: "egg")))
        XCTAssertTrue(kitchen.has(line("1 red bell pepper", match: "sweet pepper|bell pepper")))
        XCTAssertTrue(kitchen.has(line("3 tomatoes", match: "tomato")))
        XCTAssertFalse(kitchen.has(line("1 eggplant", match: "eggplant")))
        XCTAssertFalse(kitchen.has(line("2 chicken breasts", match: "chicken")))
    }

    func testReadyRecipesComeFirstAndBasicsNeverCountAsMissing() {
        let omelette = recipe("omelette", [line("3 eggs", match: "egg"), line("Salt", match: "salt", grams: nil, pantry: true),
                                           line("1 tbsp oil", match: "oil", pantry: true)])
        let shakshuka = recipe("shakshuka", [line("4 eggs", match: "egg"), line("4 tomatoes", match: "tomato"),
                                             line("1 onion", match: "onion")])
        let curry = recipe("curry", [line("chicken", match: "chicken"), line("rice", match: "rice"), line("onion", match: "onion")])
        let found = CookbookSuggester.suggestions(stock: ["Eggs, whole", "Tomatoes, raw"],
                                                  recipes: [curry, shakshuka, omelette], prefs: [])
        XCTAssertEqual(found.map(\.recipe.id), ["omelette", "shakshuka"])
        XCTAssertTrue(found[0].missing.isEmpty)
        XCTAssertEqual(found[1].missing.map(\.text), ["1 onion"])
    }

    func testSuggestionsFollowTheDiet() {
        let chicken = recipe("chicken-rice", [line("chicken", match: "chicken")], tags: ["glutenFree", "dairyFree"])
        let salad = recipe("salad", [line("tomato", match: "tomato")], tags: ["vegetarian", "vegan", "glutenFree"], carbs: 8)
        let pasta = recipe("pasta", [line("tomato", match: "tomato")], tags: ["vegetarian"], carbs: 80)
        let stock = ["Chicken, breast", "Tomatoes, raw"]
        XCTAssertEqual(CookbookSuggester.suggestions(stock: stock, recipes: [chicken, salad, pasta], prefs: [.vegetarian]).map(\.recipe.id).sorted(), ["pasta", "salad"])
        XCTAssertEqual(CookbookSuggester.suggestions(stock: stock, recipes: [chicken, salad, pasta], prefs: [.keto, .vegan]).map(\.recipe.id), ["salad"])
        XCTAssertTrue(CookbookSuggester.suggestions(stock: [], recipes: [salad], prefs: []).isEmpty)
    }

    func testCookingTakesTheRecipesAmountsOutOfStock() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CookbookTests"))
        defaults.removePersistentDomain(forName: "CookbookTests")
        let stock = StockStore(defaults: defaults)
        let egg = NutritionFood(id: "usda:171287", name: "Egg, whole, raw, fresh", brand: nil, basis: .grams,
                                kcal: 143, protein: 12.6, carbs: 0.7, fat: 9.5, source: .usda, sourceID: "171287", sourceDate: nil)
        let rice = NutritionFood(id: "usda:2512381", name: "Rice, white, long grain, raw", brand: nil, basis: .grams,
                                 kcal: 360, protein: 6.6, carbs: 79, fat: 0.6, source: .usda, sourceID: "2512381", sourceDate: nil)
        try stock.add(food: egg, amount: 300)
        try stock.add(food: rice, amount: 100)
        let r = recipe("egg-fried-rice", [line("3 eggs", match: "egg", grams: 150), line("1 cup rice", match: "rice", grams: 185),
                                          line("Salt", match: "salt", grams: 1, pantry: true)])
        let used = CookbookCooking.takeFromStock(r, store: stock)
        XCTAssertEqual(Set(used), ["Egg, whole, raw, fresh", "Rice, white, long grain, raw"])
        XCTAssertEqual(stock.items.count, 1, "the rice ran out and left the shelf")
        XCTAssertEqual(stock.items.first?.amount ?? 0, 150, accuracy: 0.01)
    }

    func testAServingLogsAsACookbookFoodWithItsPage() {
        let r = recipe("lentil-soup", [line("lentils", match: "lentil")])
        let food = r.servingFood
        XCTAssertEqual(food.id, "cookbook:lentil-soup")
        XCTAssertEqual(food.basis, .serving)
        XCTAssertTrue(food.isValid)
        XCTAssertEqual(food.sourceURL?.absoluteString, r.url)
        let entry = FoodLogEntry(nutritionFood: food, slot: .lunch, amount: 1.5)
        XCTAssertEqual(entry.calories, 600)
    }
}
