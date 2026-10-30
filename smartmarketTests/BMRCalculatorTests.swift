import XCTest
@testable import smartmarket

@MainActor
final class BMRCalculatorTests: XCTestCase {

    func testBMRMaleKnownValue() {
        // Mifflin-St Jeor: 10*80 + 6.25*180 - 5*30 + 5 = 1780
        let bmr = BMRCalculator.bmr(weight: 80, height: 180, age: 30, gender: .male)
        XCTAssertEqual(bmr, 1780, accuracy: 0.5)
    }

    func testTDEEAppliesMultiplier() {
        let tdee = BMRCalculator.tdee(bmr: 1780, activityLevel: .moderatelyActive)
        XCTAssertGreaterThan(tdee, 1780)
    }

    func testCalorieFloorRespected() {
        let goal = BMRCalculator.dailyGoal(tdee: 1000, goal: .lose, pace: .medium, gender: .female)
        XCTAssertGreaterThanOrEqual(goal, Constants.Calories.minimumFemale)
    }

    func testMacroSplitRoughlySumsToCalories() {
        let m = BMRCalculator.macroTargets(calories: 2000)
        let kcal = m.proteinG * 4 + m.carbsG * 4 + m.fatG * 9
        XCTAssertEqual(Double(kcal), 2000, accuracy: 80)   // allow rounding
    }
}
