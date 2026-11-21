import XCTest
@testable import smartmarket

final class DailyQuestTests: XCTestCase {
    private typealias F = LoopFixture
    private let easy: Set<QuestID> = [.logAny, .breakfast, .anyWorkout]

    private func q(_ id: QuestID, _ i: LoopInputs) -> Quest { DailyLoop.evaluate(id, day: i.today, i) }

    func testThreeQuestsEasyFirst() {
        for n in 0..<30 {
            let i = F.inputs(cartHasItems: true, hasStock: true, now: F.date(n))
            let quests = DailyLoop.quests(for: i.today, i)
            XCTAssertEqual(quests.count, 3)
            XCTAssertTrue(easy.contains(quests[0].id), "day \(n): \(quests[0].id)")
            XCTAssertEqual(Set(quests.map(\.id)).count, 3)
        }
    }

    func testEveryDayHasANutritionQuest() {
        for n in 0..<30 {
            let i = F.inputs(cartHasItems: true, hasStock: true, now: F.date(n))
            let ids = DailyLoop.quests(for: i.today, i).map(\.id)
            XCTAssertTrue(ids.contains { DailyLoop.nutritionQuests.contains($0) }, "day \(n): \(ids)")
        }
    }

    func testVegetablesAndFruitCountWhatWasEaten() {
        let now = F.date(0)
        func entry(_ name: String, _ slot: MealSlot) -> FoodLogEntry {
            FoodLogEntry(name: name, slot: slot, servingG: 100, calories: 50, proteinG: 1, carbsG: 5, fatG: 0, loggedAt: now)
        }
        var i = F.inputs(now: now)
        i.foodEntries = [entry("Broccoli, raw", .lunch), entry("Chicken breast", .lunch), entry("Banana", .snack)]
        XCTAssertEqual(q(.vegetables, i).current, 1)
        XCTAssertFalse(q(.vegetables, i).isDone)
        XCTAssertTrue(q(.fruit, i).isDone)
        i.foodEntries.append(entry("Spinach", .dinner))
        XCTAssertTrue(q(.vegetables, i).isDone)
    }

    func testSelectionIsStableForADay() {
        let i = F.inputs(cartHasItems: true, hasStock: true)
        XCTAssertEqual(DailyLoop.quests(for: i.today, i).map(\.id), DailyLoop.quests(for: i.today, i).map(\.id))
        let week = (0..<7).map { n -> [QuestID] in
            let d = F.inputs(cartHasItems: true, hasStock: true, now: F.date(n))
            return DailyLoop.quests(for: d.today, d).map(\.id)
        }
        XCTAssertGreaterThan(Set(week.map { $0.map(\.rawValue).joined(separator: ",") }).count, 1)
    }

    func testNewUserGetsNoTargetQuests() {
        for n in 0..<14 {
            let i = F.inputs(calorieGoal: 0, proteinGoal: 0, now: F.date(n))
            let ids = Set(DailyLoop.quests(for: i.today, i).map(\.id))
            XCTAssertFalse(ids.contains(.protein)); XCTAssertFalse(ids.contains(.onTarget))
        }
    }

    func testBudgetNeedsCartItems() {
        XCTAssertFalse(DailyLoop.available(day: F.day(), F.inputs(cartHasItems: false)).contains(.budget))
        XCTAssertTrue(DailyLoop.available(day: F.day(), F.inputs(cartHasItems: true)).contains(.budget))
    }

    func testFromStockNeedsStock() {
        XCTAssertFalse(DailyLoop.available(day: F.day(), F.inputs(hasStock: false)).contains(.fromStock))
        XCTAssertTrue(DailyLoop.available(day: F.day(), F.inputs(hasStock: true)).contains(.fromStock))
    }

    func testWorkoutQuestsAtMostFourDaysAWeek() {
        let days = (0..<7).filter { n in
            let i = F.inputs(now: F.date(n))
            return DailyLoop.available(day: i.today, i).contains(.workout)
        }
        XCTAssertEqual(days.count, 4)
    }

    func testDone_logAny() {
        XCTAssertFalse(q(.logAny, F.inputs()).isDone)
        XCTAssertTrue(q(.logAny, F.inputs(food: [F.food()])).isDone)
    }

    func testDone_breakfast() {
        XCTAssertFalse(q(.breakfast, F.inputs(food: [F.food(slot: .lunch)])).isDone)
        XCTAssertTrue(q(.breakfast, F.inputs(food: [F.food(slot: .breakfast)])).isDone)
    }

    func testDone_threeMeals() {
        let two = [F.food(slot: .breakfast), F.food(slot: .lunch), F.food(slot: .lunch)]
        XCTAssertFalse(q(.threeMeals, F.inputs(food: two)).isDone)
        XCTAssertTrue(q(.threeMeals, F.inputs(food: two + [F.food(slot: .dinner)])).isDone)
    }

    func testProteinProgressReports62Of90() {
        let quest = q(.protein, F.inputs(food: [F.food(protein: 62)], proteinGoal: 112))
        XCTAssertEqual(quest.current, 62); XCTAssertEqual(quest.goal, 90); XCTAssertEqual(quest.unit, "g")
        XCTAssertFalse(quest.isDone)
    }

    func testDone_protein() {
        XCTAssertTrue(q(.protein, F.inputs(food: [F.food(protein: 90)], proteinGoal: 112)).isDone)
    }

    func testDone_onTarget() {
        let food = [F.food(slot: .breakfast, kcal: 900), F.food(slot: .lunch, kcal: 1000)]
        XCTAssertTrue(q(.onTarget, F.inputs(food: food, now: F.date(0, hour: 19))).isDone)
        let oneSlot = [F.food(slot: .lunch, kcal: 1900)]
        XCTAssertFalse(q(.onTarget, F.inputs(food: oneSlot, now: F.date(0, hour: 19))).isDone)
        let over = [F.food(slot: .breakfast, kcal: 1200), F.food(slot: .lunch, kcal: 1100)]
        XCTAssertFalse(q(.onTarget, F.inputs(food: over, now: F.date(0, hour: 19))).isDone)
    }

    func testOnTargetNotDoneBeforeFive() {
        let food = [F.food(slot: .breakfast, kcal: 900), F.food(slot: .lunch, kcal: 1000)]
        XCTAssertFalse(q(.onTarget, F.inputs(food: food, now: F.date(0, hour: 16, minute: 59))).isDone)
    }

    func testDone_workout() {
        XCTAssertFalse(q(.workout, F.inputs(workouts: [F.workout(minutes: 15)])).isDone)
        XCTAssertTrue(q(.workout, F.inputs(workouts: [F.workout(minutes: 15), F.workout(minutes: 10)])).isDone)
    }

    func testDone_anyWorkout() {
        XCTAssertFalse(q(.anyWorkout, F.inputs(workouts: [F.workout(-1)])).isDone)
        XCTAssertTrue(q(.anyWorkout, F.inputs(workouts: [F.workout(minutes: 5)])).isDone)
    }

    func testDone_fromStock() {
        let e = F.food(id: "s1")
        XCTAssertFalse(q(.fromStock, F.inputs(food: [e])).isDone)
        XCTAssertTrue(q(.fromStock, F.inputs(food: [e], stockIDs: ["s1"])).isDone)
    }

    func testDone_newFood() {
        XCTAssertFalse(q(.newFood, F.inputs(food: [F.food(-3, foodId: "oats"), F.food(0, foodId: "oats")])).isDone)
        XCTAssertTrue(q(.newFood, F.inputs(food: [F.food(-3, foodId: "oats"), F.food(0, foodId: "kiwi")])).isDone)
        XCTAssertFalse(q(.newFood, F.inputs(food: [F.food(0, foodId: nil)])).isDone)
    }

    func testDone_budget() {
        XCTAssertFalse(q(.budget, F.inputs(cartHasItems: true)).isDone)
        XCTAssertTrue(q(.budget, F.inputs(cartHasItems: true, ledger: [.budgetCheckIn(F.day())])).isDone)
    }

    func testPerfectDayWhenAllThreeDone() {
        let i = F.inputs(calorieGoal: 0, proteinGoal: 0)
        let ids = DailyLoop.quests(for: i.today, i).map(\.id)
        XCTAssertFalse(DailyLoop.isPerfect(day: i.today, i))
        // Satisfy everything any quest could ask for.
        var food = [F.food(-2, foodId: "old")]
        food += [F.food(slot: .breakfast, foodId: "new1", id: "s1", name: "Banana"), F.food(slot: .lunch, name: "Broccoli"),
                 F.food(slot: .dinner, name: "Spinach")]
        let all = F.inputs(food: food, stockIDs: ["s1"], workouts: [F.workout(minutes: 30)], calorieGoal: 0, proteinGoal: 0,
                           cartHasItems: true, hasStock: true, ledger: [.budgetCheckIn(F.day())])
        XCTAssertEqual(DailyLoop.quests(for: all.today, all).count, 3, "\(ids)")
        XCTAssertTrue(DailyLoop.isPerfect(day: all.today, all))
    }
}
