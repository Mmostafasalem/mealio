import XCTest
@testable import smartmarket

@MainActor
final class MealPlanGroundingTests: XCTestCase {
    func testNutritionUsesSourcePortionsAndIgnoresModelCalories() throws {
        let food = try XCTUnwrap(NutritionDatabase.load().first)
        let item = MealItem(portions: [PlannedPortion(foodID: food.id, amount: 125)], pavadinimas: "Lunch", ingredientai: [], kcal: 9999)
        let resolved = MealPlanGrounding.resolve(item, foods: [food.id: food])
        let entry = try XCTUnwrap(MealPlan.entry(resolved).first)
        XCTAssertEqual(entry.calories, Int(food.portion(125).kcal.rounded()))
        XCTAssertEqual(entry.proteinG, food.portion(125).protein, accuracy: 0.0001)
        XCTAssertEqual(entry.carbsG, food.portion(125).carbs, accuracy: 0.0001)
        XCTAssertEqual(entry.fatG, food.portion(125).fat, accuracy: 0.0001)
        XCTAssertEqual(entry.nutritionIngredients?.first?.food.id, food.id)
    }
    func testUnresolvedIngredientsCannotProducePartialOrRemoteNutrition() throws {
        let food = try XCTUnwrap(NutritionDatabase.load().first)
        for portions in [[PlannedPortion(foodID: "invented", amount: 100)],
                         [PlannedPortion(foodID: food.id, amount: .infinity)],
                         [PlannedPortion(foodID: food.id, amount: -1)],
                         [PlannedPortion(foodID: food.id, amount: 100), PlannedPortion(foodID: "unknown", amount: 50)]] {
            let item = MealItem(portions: portions, nutritionIngredients: [NutritionIngredient(food: food, amount: 999)],
                                pavadinimas: "Meal", ingredientai: ["Unknown"], kcal: 400)
            let entry = try XCTUnwrap(MealPlan.entry(MealPlanGrounding.resolve(item, foods: [food.id: food])).first)
            XCTAssertNil(entry.nutritionIngredients)
            XCTAssertEqual(entry.proteinG, 0)
            XCTAssertEqual(entry.portionG, 0)
            XCTAssertEqual(entry.calories, 400)
        }
    }
    func testLegacyPlansRemainReadableWithoutInventedMacros() throws {
        let item = try JSONDecoder().decode(MealItem.self, from: Data(#"{"pavadinimas":"Old meal","ingredientai":["Rice"],"kcal":500}"#.utf8))
        let entry = try XCTUnwrap(MealPlan.entry(item).first)
        XCTAssertEqual(entry.calories, 500)
        XCTAssertEqual(entry.proteinG + entry.carbsG + entry.fatG, 0)
        XCTAssertEqual(entry.portionG, 0)
    }
}
