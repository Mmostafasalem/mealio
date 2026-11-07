import XCTest
@testable import smartmarket

@MainActor
final class NutritionCatalogTests: XCTestCase {
    func testBundledSourceCatalogIsLargeAndKeepsRawCookedDistinct() throws {
        let foods = try NutritionDatabase.load()
        XCTAssertGreaterThan(foods.count, 7000)
        XCTAssertEqual(Food.catalog.count, 35, "All legacy food IDs must resolve to source records")
        XCTAssertEqual(Set(foods.map(\.id)).count, foods.count)
        let chicken = NutritionDatabase.search("chicken breast raw", in: foods)
        XCTAssertFalse(chicken.isEmpty)
        XCTAssertTrue(chicken.allSatisfy { $0.name.localizedCaseInsensitiveContains("raw") })
        XCTAssertFalse(NutritionDatabase.search("chicken breast cooked", in: foods).isEmpty)
    }

    func testProviderRejectsMissingMacrosAndKeepsRealZero() throws {
        let valid = product(nutrients: ["energy-kcal_100g": 0, "proteins_100g": 0, "carbohydrates_100g": 0, "fat_100g": 0])
        XCTAssertNotNil(NutritionFood.openFoodFacts(valid))
        XCTAssertNil(NutritionFood.openFoodFacts(product(nutrients: ["energy-kcal_100g": 120, "proteins_100g": 5])))
        XCTAssertNil(NutritionFood.openFoodFacts(product(nutrients: ["energy-kcal_100g": -5, "proteins_100g": 1, "carbohydrates_100g": 1, "fat_100g": 1])))
    }

    func testServingUsesFractionalMacrosAndPreservesVolumeBasis() throws {
        var raw = product(nutrients: ["energy-kj_100g": 418.4, "proteins_100g": 3.25, "carbohydrates_100g": 4.5, "fat_100g": 2.1])
        raw["product_quantity_unit"] = "ml"
        raw["serving_quantity_unit"] = "ml"
        let food = try XCTUnwrap(NutritionFood.openFoodFacts(raw))
        XCTAssertEqual(food.basis.rawValue, "ml")
        let portion = food.portion(150)
        XCTAssertEqual(portion.kcal, 150, accuracy: 0.01)
        XCTAssertEqual(portion.protein, 4.875, accuracy: 0.0001)
        XCTAssertEqual(food.sourceID, "12345678")
    }

    func testLogSnapshotSurvivesEncodingAndOldLogsStillDecode() throws {
        let food = try XCTUnwrap(NutritionFood.openFoodFacts(product(nutrients: ["energy-kcal_100g": 100, "proteins_100g": 3.25, "carbohydrates_100g": 4.5, "fat_100g": 2.1])))
        let entry = FoodLogEntry(nutritionFood: food, slot: .snack, amount: 150.5)
        let decoded = try JSONDecoder().decode(FoodLogEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(decoded.nutritionFood, food)
        XCTAssertEqual(decoded.amount, 150.5)
        XCTAssertEqual(decoded.proteinG, 4.89125, accuracy: 0.0001)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        old.removeValue(forKey: "nutritionFood")
        old.removeValue(forKey: "portionAmount")
        let legacy = try JSONDecoder().decode(FoodLogEntry.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.nutritionFood)
        XCTAssertEqual(legacy.calories, 151)
    }

    func testProviderRejectsBooleanNutrientsAndAmbiguousUnits() throws {
        let valid: [String: Any] = ["energy-kcal_100g": 100, "proteins_100g": 4, "carbohydrates_100g": 5, "fat_100g": 2]
        for key in valid.keys {
            var n = valid; n[key] = true
            XCTAssertNil(NutritionFood.openFoodFacts(product(nutrients: n)), key)
        }
        var raw = product(nutrients: valid)
        raw["product_quantity_unit"] = "g"
        raw["serving_quantity_unit"] = "ml"
        XCTAssertNil(NutritionFood.openFoodFacts(raw), "Mass and volume conflict must not assume density")
        raw.removeValue(forKey: "product_quantity_unit")
        raw.removeValue(forKey: "serving_quantity_unit")
        XCTAssertNil(NutritionFood.openFoodFacts(raw), "The legacy 100g flag alone cannot distinguish grams from ml")
    }

    private func product(nutrients: [String: Any]) -> [String: Any] {
        ["code": "12345678", "product_name": "Test food", "brands": "Test brand", "serving_quantity_unit": "g", "nutriments": nutrients]
    }
}
