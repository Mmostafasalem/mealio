import XCTest
@testable import smartmarket

final class DailyLoopTests: XCTestCase {
    private typealias F = LoopFixture

    func testEntriesAtMidnightFallOnTheirOwnDays() {
        let i = F.inputs(food: [F.food(-1, hour: 23, minute: 59), F.food(0, hour: 0, minute: 1)])
        XCTAssertEqual(DailyLoop.keptDays(i), [F.day(-1), F.day(0)])
    }

    func testStreakCountsBackThroughHistory() {
        let i = F.inputs(food: (1...20).map { F.food(-$0) })
        XCTAssertEqual(DailyLoop.streak(i), 20)
    }

    func testTodayKeptAddsToStreak() {
        let i = F.inputs(food: (0...20).map { F.food(-$0) })
        XCTAssertEqual(DailyLoop.streak(i), 21)
    }

    func testGapBreaksStreak() {
        let i = F.inputs(food: [F.food(-5), F.food(-4), F.food(-3), F.food(-1)])
        XCTAssertEqual(DailyLoop.streak(i), 1)
    }

    func testSavedDayBridgesButDoesNotAdd() {
        let i = F.inputs(food: [F.food(-3), F.food(-1)], ledger: [.saverUsed(F.day(-2))])
        XCTAssertEqual(DailyLoop.streak(i), 2)
    }

    func testWorkoutAndBudgetCheckInKeepADay() {
        let i = F.inputs(workouts: [F.workout(-2)], ledger: [.budgetCheckIn(F.day(-1))])
        XCTAssertEqual(DailyLoop.keptDays(i), [F.day(-2), F.day(-1)])
        XCTAssertEqual(DailyLoop.streak(i), 2)
    }

    func testLongestStreak() {
        let i = F.inputs(food: [F.food(-10), F.food(-9), F.food(-8), F.food(-7), F.food(-3), F.food(-2)])
        XCTAssertEqual(DailyLoop.longestStreak(i), 4)
    }

    func testWeekRowMarksTodayAndFuture() {
        // 2026-11-11 is a Wednesday: Mon, Tue past; Wed today; Thu–Sun future.
        let i = F.inputs(food: [F.food(-2)], ledger: [.saverUsed(F.day(-1))])
        XCTAssertEqual(DailyLoop.week(i), [.kept, .saved, .today(kept: false), .future, .future, .future, .future])
    }

    func testMoodNewUserIsHappy() {
        XCTAssertEqual(DailyLoop.mood(F.inputs(calorieGoal: 0), justCompleted: false, generating: false), .happy)
    }

    func testMoodWorriedAfterSixWhenNotKept() {
        let late = F.inputs(food: [F.food(-1)], now: F.date(0, hour: 18, minute: 30))
        XCTAssertEqual(DailyLoop.mood(late, justCompleted: false, generating: false), .worried)
        let early = F.inputs(food: [F.food(-1)], now: F.date(0, hour: 17, minute: 59))
        XCTAssertEqual(DailyLoop.mood(early, justCompleted: false, generating: false), .happy)
    }

    func testMoodSleepyOnlyAfterLosingStreakOfTwo() {
        let lost = F.inputs(food: [F.food(-3), F.food(-2)])
        XCTAssertEqual(DailyLoop.mood(lost, justCompleted: false, generating: false), .sleepy)
        let short = F.inputs(food: [F.food(-2)])
        XCTAssertEqual(DailyLoop.mood(short, justCompleted: false, generating: false), .happy)
    }

    func testMoodJustCompletedCelebratesAndGeneratingThinks() {
        let i = F.inputs(food: [F.food(0)])
        XCTAssertEqual(DailyLoop.mood(i, justCompleted: true, generating: false), .celebrate)
        XCTAssertEqual(DailyLoop.mood(i, justCompleted: true, generating: true), .thinking)
    }

    func testMoodLoveOnPerfectDay() {
        // Everything any quest could ask for is done today.
        let food = [F.food(-2, foodId: "old"), F.food(slot: .breakfast, foodId: "new1", id: "s1"),
                    F.food(slot: .lunch), F.food(slot: .dinner)]
        let i = F.inputs(food: food, stockIDs: ["s1"], workouts: [F.workout(minutes: 30)], calorieGoal: 0, proteinGoal: 0,
                         cartHasItems: true, hasStock: true, ledger: [.budgetCheckIn(F.day())])
        XCTAssertEqual(DailyLoop.mood(i, justCompleted: false, generating: false), .love)
    }

    func testTodayKeptIsHappyEvenLate() {
        let i = F.inputs(food: [F.food(0, hour: 9)], now: F.date(0, hour: 21))
        XCTAssertEqual(DailyLoop.mood(i, justCompleted: false, generating: false), .happy)
    }

    // Review fixes
    func testPerfectDayRecordDoesNotKeepLoveAfterDeletion() {
        let i = F.inputs(ledger: [.perfectDay(F.day(0))])
        XCTAssertNotEqual(DailyLoop.mood(i, justCompleted: false, generating: false), .love)
    }

    func testWeekRowStartsMondayEvenForSundayFirstLocales() {
        var cal = F.calendar
        cal.firstWeekday = 1
        var i = F.inputs(food: [F.food(-2)], now: F.date(0))
        i.calendar = cal
        // Wednesday is still the third dot.
        XCTAssertEqual(DailyLoop.week(i)[2], .today(kept: false))
        XCTAssertEqual(DailyLoop.week(i)[0], .kept)
    }

    func testRecordedKeptDaysSurviveLostHistory() {
        // The workout behind day -2 fell out of the capped history; the ledger remembers the day.
        let i = F.inputs(food: [F.food(-1)], ledger: [.dayKept(F.day(-2))])
        XCTAssertEqual(DailyLoop.streak(i), 2)
    }

    func testRefreshWithAYearOfHistoryIsFast() {
        var food: [FoodLogEntry] = []
        for d in 0..<365 { for h in [8, 12, 15, 19, 21] { food.append(F.food(-d, hour: h, foodId: "f\(d % 40)")) } }
        let i = F.inputs(food: food, workouts: (0..<200).map { F.workout(-$0) }, ledger: [.loopStarted(F.day(-300))]).prepared()
        let start = Date()
        _ = DailyLoop.saverEvents(i); _ = DailyLoop.streak(i); _ = DailyLoop.longestStreak(i); _ = DailyLoop.week(i)
        _ = DailyLoop.quests(for: i.today, i); _ = DailyLoop.mood(i, justCompleted: false, generating: false)
        _ = DailyLoop.milestoneEvent(i)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.015)
    }
}
