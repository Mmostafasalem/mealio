import XCTest
@testable import smartmarket

@MainActor
final class MealGoalTests: XCTestCase {
    func testChatUsesActualGoalIntakeStockAndDietaryExclusions() throws {
        var profile = UserProfile()
        profile.weightGoal = .lose
        profile.dailyCalorieGoal = 1800
        let food = try XCTUnwrap(NutritionDatabase.load().first)
        let entries = [FoodLogEntry(name: "Lunch", slot: .lunch, servingG: 150,
                                   calories: 400, proteinG: 25, carbsG: 40, fatG: 10)]
        let batch = StockItem(id: UUID(), food: food, amount: 250, expiresAt: nil, addedAt: Date())
        let context = AgentUserContext.make(profile: profile, entries: entries, stock: [batch, batch],
                                            preferences: [.nutAllergy, .noPork], favoriteFoods: [], lang: "ar")
        XCTAssertEqual(context.targetCalories, 1800)
        XCTAssertEqual(context.caloriesConsumed, 400)
        XCTAssertEqual(context.remainingToday?.calories, 1400)
        XCTAssertEqual(context.remainingToday?.protein, 110)
        XCTAssertEqual(context.stock.count, 1)
        XCTAssertEqual(context.stock.first?.availableAmount, 500)
        XCTAssertEqual(context.allergies, ["nut_allergy"])
        XCTAssertEqual(context.dietaryOptions, ["no_pork"])
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any])
        XCTAssertNil(payload["weight"])
        XCTAssertNil(payload["name"])
        XCTAssertEqual(payload["lang"] as? String, "ar")
    }

    func testRemainingGoalsSubtractLoggedPortionsAndClampAtZero() {
        let vm = MealPlanViewModel()
        let empty = vm.nutritionalGaps(entries: [])
        let meal = FoodLogEntry(name: "Lunch", slot: .lunch, servingG: 150,
                               calories: 400, proteinG: 25.5, carbsG: 40.5, fatG: 10.5)
        let remaining = vm.nutritionalGaps(entries: [meal])
        XCTAssertEqual(remaining.caloriesNeeded, max(empty.caloriesNeeded - 400, 0))
        XCTAssertEqual(remaining.proteinNeeded, max(empty.proteinNeeded - 25.5, 0))
        XCTAssertEqual(remaining.carbsNeeded, max(empty.carbsNeeded - 40.5, 0))
        XCTAssertEqual(remaining.fatNeeded, max(empty.fatNeeded - 10.5, 0))
        let over = vm.nutritionalGaps(entries: Array(repeating: meal, count: 100))
        XCTAssertEqual(over.caloriesNeeded, 0)
        XCTAssertEqual(over.proteinNeeded, 0)
        XCTAssertEqual(over.carbsNeeded, 0)
        XCTAssertEqual(over.fatNeeded, 0)
    }

    func testPlanningCannotCombineCorrectedProductUnitsOrNutrients() throws {
        let food = try XCTUnwrap(NutritionDatabase.load().first)
        let original = StockItem(id: UUID(), food: food, amount: 100, expiresAt: nil, addedAt: Date())
        for basis in [NutritionFood.Basis.millilitres, food.basis] {
            let corrected = NutritionFood(id: food.id, name: food.name, brand: food.brand, basis: basis,
                                          kcal: food.kcal + 1, protein: food.protein, carbs: food.carbs,
                                          fat: food.fat, source: food.source, sourceID: food.sourceID, sourceDate: food.sourceDate)
            let batch = StockItem(id: UUID(), food: corrected, amount: 200, expiresAt: nil, addedAt: Date())
            XCTAssertTrue(PlanningFood.grouped([original, batch]).isEmpty)
        }
        XCTAssertEqual(PlanningFood.grouped([original, original]).first?.availableAmount, 200)
        let refreshed = NutritionFood(id: food.id, name: "Translated product name", brand: food.brand, basis: food.basis,
                                      kcal: food.kcal, protein: food.protein, carbs: food.carbs, fat: food.fat,
                                      source: food.source, sourceID: food.sourceID, sourceDate: "2026-11-08")
        let metadataOnly = StockItem(id: UUID(), food: refreshed, amount: 200, expiresAt: nil, addedAt: Date())
        XCTAssertEqual(PlanningFood.grouped([original, metadataOnly]).first?.availableAmount, 300)
    }
}
