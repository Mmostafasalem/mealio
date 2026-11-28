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

    func testTourCoversEveryPageForTheChosenFeatures() {
        let all = GuidedTourStep.steps(for: AppFeature.all, offersChat: true)
        XCTAssertEqual(Set(all.map(\.page)), [.home, .quickActions, .meals, .shop, .train, .profile])
        XCTAssertEqual(all.first?.id, "hello")
        XCTAssertEqual(all.last?.id, "bye")
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "unique step ids")
        for step in all {
            XCTAssertFalse(step.what.isEmpty, step.id)
            XCTAssertFalse(step.how.isEmpty, step.id)
        }
        // Pages follow the features; Home, the quick actions and Profile are always there.
        let workouts = GuidedTourStep.steps(for: [.workouts])
        XCTAssertEqual(Set(workouts.map(\.page)), [.home, .quickActions, .train, .profile])
        XCTAssertFalse(workouts.contains { $0.target == .calories })
        let groceries = GuidedTourStep.steps(for: [.groceries])
        XCTAssertEqual(Set(groceries.map(\.page)), [.home, .quickActions, .shop, .profile])
        XCTAssertFalse(GuidedTourStep.steps(for: AppFeature.all, offersChat: false).contains { $0.target == .qaChat })
        // Each page's steps sit together, so the tour never jumps back and forth.
        var seen: [TourPage] = []
        for page in all.map(\.page) where seen.last != page { seen.append(page) }
        XCTAssertEqual(seen, [.home, .quickActions, .meals, .shop, .train, .profile, .home])
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
        XCTAssertEqual(tour.current?.id, "hello")
        tour.next(); tour.next(); tour.back()
        XCTAssertEqual(tour.current?.id, "calories")
        tour.finish()
        XCTAssertFalse(tour.isRunning)
        XCTAssertTrue(tour.hasSeen, "not shown by itself again")
    }
}
