import XCTest
@testable import smartmarket

/// Only true kitchen basics are assumed; everything else a recipe needs is in stock or missing.
@MainActor
final class CookbookBasicsTests: XCTestCase {

    private func recipe(_ lines: [CookbookRecipe.Line]) -> CookbookRecipe {
        CookbookRecipe(id: "dessert", title: "Dessert", url: "https://en.wikibooks.org/wiki/Cookbook:Dessert", course: .dessert,
                       servings: 2, servingsEstimated: false, minutes: 10, difficulty: 1, ingredients: lines,
                       steps: ["Mix.", "Chill."], perServing: .init(kcal: 200, protein: 1, carbs: 40, fat: 1),
                       gramsPerServing: 200, tags: ["vegetarian", "vegan"])
    }

    func testPersianAppleDessertIsNotReadyWithOnlyApples() throws {
        let dessert = try XCTUnwrap(CookbookLibrary.recipes.first { $0.title.contains("Persian Apple") })
        let kitchen = KitchenMatcher(names: ["Apples, raw, with skin"])
        let missing = kitchen.missing(in: dessert).map(\.text)
        XCTAssertTrue(missing.contains { $0.contains("lemon juice") }, "lemon juice is a real ingredient: \(missing)")
        XCTAssertTrue(missing.contains { $0.contains("flower water") }, "rose water is a real ingredient: \(missing)")
        XCTAssertFalse(missing.contains { $0.contains("sugar") || $0.contains("salt") }, "sugar and salt are basics")
        XCTAssertNotEqual(CookbookSuggester.stockSummary(dessert, missing: kitchen.missing(in: dessert)), "You have everything for this.")
        XCTAssertTrue(CookbookSuggester.stockSummary(dessert, missing: kitchen.missing(in: dessert)).hasPrefix("\(missing.count) missing"))

        let found = CookbookSuggester.suggestions(stock: ["Apples, raw, with skin"], recipes: [dessert], prefs: [])
        XCTAssertFalse(found.contains { $0.recipe.id == dessert.id && $0.missing.isEmpty }, "not under Ready to cook")

        // With lemons in stock only the flower water is left.
        let more = KitchenMatcher(names: ["Apples, raw, with skin", "Lemons, raw, without peel"])
        XCTAssertEqual(more.missing(in: dessert).count, 1)
    }

    func testOnlyBasicsAreAssumedAndOptionalExtrasDoNotCount() {
        let dish = recipe([
            .init(text: "3 apples", food: "usda:1", grams: 500, match: "apple", pantry: false),
            .init(text: "1 tbsp sugar", food: "usda:2", grams: 12, match: "sugar", pantry: true),
            .init(text: "1 tsp lemon juice", food: "usda:3", grams: 5, match: "lemon", pantry: false),
            .init(text: "1 tsp rose water", food: nil, grams: nil, match: nil, pantry: false),
            .init(text: "Whipped cream, to serve", food: "usda:4", grams: nil, match: "cream", pantry: false, optional: true),
        ])
        XCTAssertEqual(dish.keyIngredients.map(\.text), ["3 apples", "1 tsp lemon juice", "1 tsp rose water"])
        let kitchen = KitchenMatcher(names: ["Apples, raw"])
        XCTAssertEqual(kitchen.missing(in: dish).map(\.text), ["1 tsp lemon juice", "1 tsp rose water"],
                       "a small amount still counts, and a line no stock name can match is missing")
        XCTAssertEqual(dish.ingredients.map { IngredientState($0, kitchen: kitchen) }, [.have, .basic, .missing, .missing, .optional])

        // A line with no flags at all is an ingredient, not a basic.
        let unflagged = CookbookRecipe.Line(text: "cream", food: nil, grams: 10, match: "cream", pantry: nil)
        XCTAssertEqual(unflagged.kind, .ingredient)

        // Everything but the basics in stock: ready.
        let full = KitchenMatcher(names: ["Apples, raw", "Lemons, raw"])
        let ready = recipe(Array(dish.ingredients.filter { $0.match != nil }))
        XCTAssertTrue(full.missing(in: ready).isEmpty)
        XCTAssertEqual(CookbookSuggester.stockSummary(ready, missing: []), "You have everything for this, plus the kitchen basics.")
        XCTAssertEqual(CookbookSuggester.suggestions(stock: ["Apples, raw", "Lemons, raw"], recipes: [ready, dish], prefs: []).map(\.missing.count), [0, 1])
    }

    func testTheBundledBasicsAreOnlyTrueBasics() {
        let basics: Set<String> = ["salt", "sea salt", "kosher salt", "pepper", "black pepper", "white pepper", "peppercorn", "water",
                                   "cayenne pepper", "cayenne", "red pepper flakes", "paprika", "cumin", "cinnamon", "nutmeg",
                                   "allspice", "cloves", "cardamom", "turmeric", "garlic powder", "onion powder", "chili powder",
                                   "ground ginger", "garam masala", "curry powder", "fennel seed", "mustard seed", "bay leaf",
                                   "oil", "vegetable oil", "canola oil", "sunflower oil", "olive oil", "peanut oil",
                                   "sugar", "granulated sugar", "white sugar", "flour", "all-purpose flour", "baking soda", "baking powder",
                                   "vinegar", "stock", "broth", "chicken broth", "chicken stock", "beef broth", "vegetable broth",
                                   "dehydrated broth", "bouillon cube",
                                   "oregano", "thyme", "rosemary", "basil", "parsley", "cilantro", "dill", "mint", "sage", "coriander", "chives"]
        var basicCount = 0
        for r in CookbookLibrary.recipes {
            for line in r.ingredients where line.isBasic {
                basicCount += 1
                if let m = line.match { XCTAssertTrue(basics.contains(m), "\(r.title): \(line.text) (\(m)) isn't a kitchen basic") }
            }
            for line in r.ingredients where ["lemon", "lime", "cream", "soy sauce", "vanilla extract", "honey"].contains(line.match ?? "") {
                XCTAssertFalse(line.isBasic, "\(r.title): \(line.text)")
            }
        }
        XCTAssertGreaterThan(basicCount, 1000)
    }
}
