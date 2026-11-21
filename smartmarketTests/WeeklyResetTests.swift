import XCTest
@testable import smartmarket

@MainActor
final class WeeklyResetTests: XCTestCase {
    private var defaults: UserDefaults!
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2   // Monday
        return c
    }()

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WeeklyResetTests")
        defaults.removePersistentDomain(forName: "WeeklyResetTests")
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 10))! }

    func testFirstLaunchOnlyNotesTheWeekThenANewWeekAsksOnce() {
        let wed = day(2026, 11, 18), sun = day(2026, 11, 22), mon = day(2026, 11, 23)
        XCTAssertFalse(WeeklyReset.isDue(now: wed, hasSomething: true, defaults: defaults, calendar: calendar), "never on day one")
        XCTAssertFalse(WeeklyReset.isDue(now: sun, hasSomething: true, defaults: defaults, calendar: calendar), "same week")
        XCTAssertTrue(WeeklyReset.isDue(now: mon, hasSomething: true, defaults: defaults, calendar: calendar), "Monday starts a new week")
        defaults.set(WeeklyReset.weekStart(of: mon, calendar: calendar), forKey: WeeklyReset.handledKey)
        XCTAssertFalse(WeeklyReset.isDue(now: mon, hasSomething: true, defaults: defaults, calendar: calendar), "asked once")
    }

    func testTheChosenStartDayDecidesTheWeek() {
        var saturday = calendar
        saturday.firstWeekday = 7
        let fri = day(2026, 11, 20), sat = day(2026, 11, 21)
        _ = WeeklyReset.isDue(now: fri, hasSomething: true, defaults: defaults, calendar: saturday)
        XCTAssertTrue(WeeklyReset.isDue(now: sat, hasSomething: true, defaults: defaults, calendar: saturday))
    }

    func testNothingToClearMeansNoQuestion() {
        _ = WeeklyReset.isDue(now: day(2026, 11, 18), hasSomething: false, defaults: defaults, calendar: calendar)
        XCTAssertFalse(WeeklyReset.isDue(now: day(2026, 11, 23), hasSomething: false, defaults: defaults, calendar: calendar))
    }

    func testEmptyingStockKeepsTheFoodHistory() throws {
        let stockDefaults = UserDefaults(suiteName: "WeeklyResetTests.stock")!
        stockDefaults.removePersistentDomain(forName: "WeeklyResetTests.stock")
        let stock = StockStore(defaults: stockDefaults)
        let food = try XCTUnwrap(NutritionCatalogService.shared.searchLocal("banana").first)
        try stock.add(food: food, amount: 500)
        let item = try XCTUnwrap(stock.items.first)
        try stock.consume(id: item.id, amount: 100, slot: .breakfast)
        stock.clearItems()
        XCTAssertTrue(stock.items.isEmpty)
        XCTAssertFalse(stock.logs.isEmpty, "what was eaten stays")
    }
}
