import XCTest
@testable import smartmarket

@MainActor
final class MealGoalTests: XCTestCase {
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
}
