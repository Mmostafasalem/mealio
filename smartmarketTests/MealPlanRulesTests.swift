import XCTest
@testable import smartmarket

@MainActor
final class MealPlanRulesTests: XCTestCase {
    override func setUp() {
        StockStore.shared.clearItems()   // the plan reads My Stock; start each test with an empty shelf
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "shoppingCart_v1")
        UserDefaults.standard.removeObject(forKey: MealSplit.storageKey)
    }

    private func meals(_ plan: WeeklyMealPlan) -> [[MealItem?]] {
        plan.allDays.map(\.plan).map { [$0.pusryciai, $0.pietus, $0.vakariene, $0.uzkandziai] }
    }

    func testEveryDayFollowsTheSameRulesAndTheChosenSplit() {
        let split = MealSplit(breakfast: 35, lunch: 30, dinner: 25, snack: 10)
        let plan = FallbackData.mealPlan(targetKcal: 2000, preferences: [], split: split)
        for day in meals(plan) {
            XCTAssertEqual(day.compactMap { $0 }.count, 4, "breakfast, lunch, dinner and a snack every day")
            XCTAssertEqual(Double(day[0]?.kcal ?? 0), 700, accuracy: 120)
            XCTAssertEqual(Double(day[2]?.kcal ?? 0), 500, accuracy: 120)
        }
    }

    func testNoSnackSplitLeavesTheSnackOut() {
        let plan = FallbackData.mealPlan(targetKcal: 2000, preferences: [], split: MealSplit(breakfast: 30, lunch: 40, dinner: 30, snack: 0))
        XCTAssertTrue(meals(plan).allSatisfy { $0[3] == nil })
    }

    func testCatalogueFoodsAreMarkedWhenNothingIsOwned() {
        let plan = FallbackData.mealPlan(targetKcal: 2000, preferences: [])
        let lunch = meals(plan)[0][1]
        XCTAssertFalse(lunch?.missing?.isEmpty ?? true, "an empty kitchen means suggested foods")
        XCTAssertFalse(lunch?.missingCatalogIds?.isEmpty ?? true)
    }

    func testCartFoodsAreUsedAndNotMarked() throws {
        let cart = [CartItem(id: UUID(), catalogId: "salmon-fillet", name: "Salmon Fillet", store: "Catalogue", price: 6, category: "seafood", quantity: 1)]
        UserDefaults.standard.set(try JSONEncoder().encode(cart), forKey: "shoppingCart_v1")
        let plan = FallbackData.mealPlan(targetKcal: 2000, preferences: [])
        let lunch = try XCTUnwrap(meals(plan)[0][1])
        XCTAssertTrue(lunch.pavadinimas.hasPrefix("Salmon Fillet"))
        XCTAssertFalse(lunch.missing?.contains("Salmon Fillet") ?? false)
        UserDefaults.standard.removeObject(forKey: "shoppingCart_v1")
    }

    func testAnotherPlanPairsTheSameFoodsDifferently() throws {
        let cart = [
            CartItem(id: UUID(), catalogId: "salmon-fillet", name: "Salmon Fillet", store: "Catalogue", price: 6, category: "seafood", quantity: 1),
            CartItem(id: UUID(), catalogId: "chicken-breast", name: "Chicken Breast", store: "Catalogue", price: 5, category: "meat", quantity: 1),
            CartItem(id: UUID(), catalogId: "brown-rice", name: "Brown Rice", store: "Catalogue", price: 2, category: "grains", quantity: 1),
            CartItem(id: UUID(), catalogId: "spaghetti", name: "Spaghetti", store: "Catalogue", price: 1, category: "grains", quantity: 1),
            CartItem(id: UUID(), catalogId: "broccoli", name: "Broccoli", store: "Catalogue", price: 2, category: "vegetables", quantity: 1),
        ]
        UserDefaults.standard.set(try JSONEncoder().encode(cart), forKey: "shoppingCart_v1")
        defer { UserDefaults.standard.removeObject(forKey: "shoppingCart_v1") }
        let first = FallbackData.mealPlan(targetKcal: 2000, preferences: [], variation: 0)
        let next = FallbackData.mealPlan(targetKcal: 2000, preferences: [], variation: 1)
        XCTAssertNotEqual(MealPlanViewModel.fingerprint(first), MealPlanViewModel.fingerprint(next), "regenerate changes the plan")
        XCTAssertNotEqual(meals(first)[0][1]?.pavadinimas, meals(next)[0][1]?.pavadinimas, "today's lunch changes")
        // The same step builds the same plan, so background rebuilds keep the person's choice.
        XCTAssertEqual(MealPlanViewModel.fingerprint(next),
                       MealPlanViewModel.fingerprint(FallbackData.mealPlan(targetKcal: 2000, preferences: [], variation: 1)))
    }

    func testSplitsMustAddUpToAHundred() {
        XCTAssertFalse(MealSplit(breakfast: 30, lunch: 30, dinner: 30, snack: 30).isValid)
        XCTAssertTrue(MealSplit.presets.allSatisfy(\.split.isValid))
    }
}
