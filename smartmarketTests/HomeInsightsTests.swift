import XCTest
@testable import smartmarket

/// TestFlight B6 and B7: the guided tour's steps and the calorie insights numbers.
@MainActor
final class HomeInsightsTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 12))!

    private func entry(_ daysAgo: Int, _ kcal: Int, protein: Double = 10) -> FoodLogEntry {
        FoodLogEntry(name: "Food", slot: .lunch, servingG: 100, calories: kcal, proteinG: protein, carbsG: 20, fatG: 5,
                     loggedAt: calendar.date(byAdding: .day, value: -daysAgo, to: now)!)
    }

    func testInsightsFillEveryDayAndAverageOnlyLoggedOnes() {
        let insights = CalorieInsights(entries: [entry(0, 1000), entry(0, 1000), entry(2, 1800), entry(10, 5000)],
                                       target: 2000, days: 7, now: now, calendar: calendar)
        XCTAssertEqual(insights.days.count, 7)
        XCTAssertEqual(insights.days.last?.kcal, 2000, "today is last")
        XCTAssertEqual(insights.days.first?.date, calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)))
        XCTAssertEqual(insights.loggedDays.count, 2, "the 10-days-ago entry is outside 7 days")
        XCTAssertEqual(insights.averageKcal, 1900)
        XCTAssertEqual(insights.averageProtein, 15)
        XCTAssertEqual(insights.daysOnTarget, 2, "2000 and 1800 are within 10% of 2000")
    }

    func testOverTheTargetIsNotOnTarget() {
        let insights = CalorieInsights(entries: [entry(0, 2300), entry(1, 1500)], target: 2000, days: 7, now: now, calendar: calendar)
        XCTAssertEqual(insights.daysOnTarget, 0)
    }

    func testStreakCountsBackFromTodayOrYesterday() {
        let withToday = CalorieInsights(entries: [entry(0, 500), entry(1, 500), entry(2, 500), entry(4, 500)],
                                        target: 2000, days: 30, now: now, calendar: calendar)
        XCTAssertEqual(withToday.streak, 3)
        let notYetToday = CalorieInsights(entries: [entry(1, 500), entry(2, 500)], target: 2000, days: 7, now: now, calendar: calendar)
        XCTAssertEqual(notYetToday.streak, 2, "an empty today doesn't end the streak yet")
        let broken = CalorieInsights(entries: [entry(2, 500)], target: 2000, days: 7, now: now, calendar: calendar)
        XCTAssertEqual(broken.streak, 0)
        XCTAssertNil(CalorieInsights(entries: [], target: 2000, days: 7, now: now, calendar: calendar).averageKcal)
    }

    func testTourCoversTheMainPartsForTheChosenFeatures() {
        XCTAssertEqual(GuidedTourStep.steps(for: AppFeature.all).map(\.target), [.calories, .meals, .quickActions, .shop, .train])
        XCTAssertEqual(GuidedTourStep.steps(for: [.workouts]).map(\.target), [.quickActions, .train])
        XCTAssertEqual(GuidedTourStep.steps(for: [.groceries]).map(\.target), [.quickActions, .shop])
    }

    func testTourIsShownOnceAndCanBeReplayed() {
        let defaults = UserDefaults(suiteName: "HomeInsightsTests-\(UUID().uuidString)")!
        let tour = GuidedTour(defaults: defaults)
        XCTAssertFalse(tour.hasSeen)
        let started = expectation(description: "started")
        tour.start(features: AppFeature.all)
        Task { @MainActor in
            while !tour.isRunning { try? await Task.sleep(for: .milliseconds(10)) }
            started.fulfill()
        }
        wait(for: [started], timeout: 2)
        XCTAssertEqual(tour.current?.target, .calories)
        tour.next(); tour.next(); tour.back()
        XCTAssertEqual(tour.current?.target, .meals)
        tour.finish()
        XCTAssertFalse(tour.isRunning)
        XCTAssertTrue(tour.hasSeen, "not shown by itself again")
    }
}
