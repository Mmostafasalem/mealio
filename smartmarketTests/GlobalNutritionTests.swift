import XCTest
@testable import smartmarket

@MainActor
final class GlobalNutritionTests: XCTestCase {
    func testReferenceDatasetLabelsAndRegionalIngredientSearch() throws {
        let foods = try NutritionDatabase.load()
        XCTAssertGreaterThan(foods.count, 13000)
        XCTAssertTrue(foods.contains { $0.dataset == "survey" && $0.name.contains("Falafel") })
        XCTAssertTrue(foods.contains { $0.dataset == "foundation" && $0.sourceName.contains("Foundation") })
        XCTAssertFalse(NutritionDatabase.search("ryžiai virti", in: foods).isEmpty)
        XCTAssertFalse(NutritionDatabase.search("أرز مطبوخ", in: foods).isEmpty)
        XCTAssertFalse(NutritionDatabase.search("حمص", in: foods).isEmpty)
        XCTAssertTrue(NutritionDatabase.search("كشري", in: foods).isEmpty, "Do not relabel generic rice as a regional recipe")
    }
    func testRecipeUsesActualIngredientAmountsAndCookedYield() throws {
        let foods = try NutritionDatabase.load()
        let rice = try XCTUnwrap(foods.first { $0.id == "usda:168877" })
        let lentils = try XCTUnwrap(foods.first { $0.id == "usda:172420" })
        let ingredients = [NutritionIngredient(food: rice, amount: 100), NutritionIngredient(food: lentils, amount: 50)]
        let recipe = try NutritionFood.makeRecipe(name: "My koshari", ingredients: ingredients, cookedYieldG: 600)
        let expected = rice.portion(100).kcal + lentils.portion(50).kcal
        XCTAssertEqual(recipe.portion(600).kcal, expected, accuracy: 0.0001)
        XCTAssertEqual(recipe.source, .recipe)
        XCTAssertEqual(recipe.recipeDetails?.ingredients.count, 2)
        XCTAssertThrowsError(try NutritionFood.makeRecipe(name: "Bad", ingredients: ingredients, cookedYieldG: 0))
        let decoded = try JSONDecoder().decode(NutritionFood.self, from: JSONEncoder().encode(recipe))
        XCTAssertEqual(decoded, recipe)
    }
    func testRestaurantMenuNutritionHasARealServingBasis() throws {
        let dish = try NutritionFood.makeMenuFood(name: "Lunch plate", restaurant: "My restaurant", kcal: 650, protein: 35, carbs: 80, fat: 21, sourceURL: "https://example.com/menu")
        XCTAssertEqual(dish.basis, .serving)
        XCTAssertEqual(dish.portion(1).kcal, 650)
        XCTAssertEqual(dish.portion(0.5).protein, 17.5)
        XCTAssertTrue(dish.sourceName.contains("entered"))
        XCTAssertThrowsError(try NutritionFood.makeMenuFood(name: "Incomplete", restaurant: "Place", kcal: -1, protein: 2, carbs: 3, fat: 4, sourceURL: ""))
    }
    func testCustomDishesPersistAndDeleteWithoutChangingLoggedSnapshots() throws {
        let suite = "GlobalNutritionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = NutritionCatalogService(defaults: defaults)
        let dish = try NutritionFood.makeMenuFood(name: "My dish", restaurant: "Local restaurant", kcal: 500, protein: 20, carbs: 65, fat: 18, sourceURL: "")
        try catalog.saveCustom(dish)
        let entry = FoodLogEntry(nutritionFood: dish, slot: .dinner, amount: 0.5)
        let reopened = NutritionCatalogService(defaults: defaults)
        XCTAssertEqual(reopened.find(dish.id), dish)
        XCTAssertEqual(reopened.searchLocal("My dish").first, dish)
        reopened.removeCustom(dish.id)
        XCTAssertNil(reopened.find(dish.id))
        XCTAssertEqual(entry.calories, 250)
        XCTAssertEqual(entry.amount, 0.5)
        try reopened.saveCustom(dish)
        reopened.clear()
        XCTAssertNil(defaults.data(forKey: NutritionCatalogService.customKey))
        XCTAssertTrue(reopened.customFoods.isEmpty)
    }

    func testCustomResultsCannotDisplaceRecipeIngredients() throws {
        let suite = "IngredientIndexTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let dishes = try (0..<61).map { _ in
            try NutritionFood.makeMenuFood(name: "Rice", restaurant: "Place", kcal: 100, protein: 1, carbs: 10, fat: 1, sourceURL: "")
        }
        defaults.set(try JSONEncoder().encode(dishes), forKey: NutritionCatalogService.customKey)
        let catalog = NutritionCatalogService(defaults: defaults)
        let ingredients = catalog.searchIngredients("rice")
        XCTAssertFalse(ingredients.isEmpty)
        XCTAssertTrue(ingredients.allSatisfy { $0.source == .usda })
    }

}
