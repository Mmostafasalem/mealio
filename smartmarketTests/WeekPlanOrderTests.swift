import XCTest
@testable import smartmarket

@MainActor
final class WeekPlanOrderTests: XCTestCase {
    private func day(_ kcal: Int) -> DayPlan {
        let m = MealItem(pavadinimas: "Meal", ingredientai: [], kcal: kcal)
        return DayPlan(pusryciai: m, pietus: m, vakariene: m, uzkandziai: m, visoKcal: kcal * 4)
    }

    func testWeekStartsTodayAndRunsForward() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vilnius")!
        // Saturday 14 November 2026.
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 13))!
        let weekly = WeeklyMealPlan(agentMessage: nil, pirmadienis: day(100), antradienis: day(200), treciadienis: day(300),
                                    ketvirtadienis: day(400), pentadienis: day(500), sestadienis: day(600), sekmadienis: day(700))
        let plans = MealPlanViewModel.buildWeek(from: weekly, now: now, calendar: cal)
        XCTAssertEqual(plans.map { cal.component(.day, from: $0.date) }, [14, 15, 16, 17, 18, 19, 20])
        // Saturday's plan is today's, Sunday's tomorrow's.
        XCTAssertEqual(plans.first?.totalCalories, 2400)
        XCTAssertEqual(plans[1].totalCalories, 2800)
    }
}

final class MealPlanTargetCheckTests: XCTestCase {
    private func week(_ k: [Int]) -> WeeklyMealPlan {
        func meal(_ v: Int) -> MealItem { MealItem(pavadinimas: "Meal", ingredientai: [], kcal: v) }
        let d = DayPlan(pusryciai: meal(k[0]), pietus: meal(k[1]), vakariene: meal(k[2]), uzkandziai: meal(k[3]), visoKcal: k.reduce(0, +))
        return WeeklyMealPlan(agentMessage: nil, pirmadienis: d, antradienis: d, treciadienis: d, ketvirtadienis: d,
                              pentadienis: d, sestadienis: d, sekmadienis: d)
    }

    func testCopiedKcalPlanIsNotOnTarget() {
        XCTAssertFalse(week([500, 500, 500, 500]).isOnTarget(2550))
    }

    func testFarPlanIsNotOnTarget() {
        XCTAssertFalse(week([300, 500, 450, 120]).isOnTarget(2550))
    }

    func testNearPlanIsOnTarget() {
        XCTAssertTrue(week([640, 880, 760, 260]).isOnTarget(2550))
    }
}

@MainActor
final class SavedPlanCheckTests: XCTestCase {
    func testSavedOffTargetPlanNeedsReplacing() {
        func meal(_ v: Int) -> MealItem { MealItem(pavadinimas: "Meal", ingredientai: [], kcal: v) }
        let d = DayPlan(pusryciai: meal(500), pietus: meal(500), vakariene: meal(500), uzkandziai: meal(500), visoKcal: 2000)
        let plan = WeeklyMealPlan(agentMessage: nil, pirmadienis: d, antradienis: d, treciadienis: d, ketvirtadienis: d,
                                  pentadienis: d, sestadienis: d, sekmadienis: d)
        XCTAssertTrue(AgentLoop.savedPlanNeedsReplacing(plan, target: 2550))
        XCTAssertFalse(AgentLoop.savedPlanNeedsReplacing(nil, target: 2550))
    }
}
