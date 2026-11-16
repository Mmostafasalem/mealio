import XCTest
import UserNotifications
@testable import smartmarket

@MainActor
private final class SilentScheduler: ReminderScheduling {
    var removed: [String] = []
    var added: [UNNotificationRequest] = []
    func requestAuthorization() async -> Bool { true }
    func isDenied() async -> Bool { false }
    func pendingReminderIdentifiers() async -> [String] { [] }
    func remove(_ identifiers: [String]) { removed += identifiers }
    func add(_ request: UNNotificationRequest) { added.append(request) }
}

@MainActor
final class HomeFixesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "HomeFixesTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = day; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    // MARK: Reminder dismissals follow the day

    func testYesterdaysDismissalDoesNotHideTodaysReminder() async {
        let store = ReminderStore(scheduler: SilentScheduler(), defaults: defaults)
        await store.setEnabled(true)
        let lunch = store.reminders.first { $0.kind == .lunch }!
        store.dismiss(lunch, now: date(day: 17, hour: 14))
        XCTAssertFalse(store.due(now: date(day: 17, hour: 14)).contains(lunch))
        // Same long-lived process, next day.
        XCTAssertTrue(store.due(now: date(day: 18, hour: 14)).contains(lunch))
        XCTAssertTrue(store.dismissed(on: date(day: 18, hour: 9)).isEmpty)
    }

    func testDismissingOnANewDayDoesNotCarryYesterdaysIDs() async {
        let store = ReminderStore(scheduler: SilentScheduler(), defaults: defaults)
        await store.setEnabled(true)
        let lunch = store.reminders.first { $0.kind == .lunch }!
        let breakfast = store.reminders.first { $0.kind == .breakfast }!
        store.dismiss(lunch, now: date(day: 17, hour: 14))
        store.dismiss(breakfast, now: date(day: 18, hour: 9))
        XCTAssertEqual(store.dismissed(on: date(day: 18, hour: 9)), ["breakfast"])
        let reloaded = ReminderStore(scheduler: SilentScheduler(), defaults: defaults)
        XCTAssertEqual(reloaded.dismissed(on: date(day: 18, hour: 20)), ["breakfast"])
        XCTAssertTrue(reloaded.dismissed(on: date(day: 19, hour: 9)).isEmpty)
    }

    func testDismissAllDueUsesTheGivenDay() async {
        let store = ReminderStore(scheduler: SilentScheduler(), defaults: defaults)
        await store.setEnabled(true)
        store.dismissAllDue(now: date(day: 17, hour: 14))
        XCTAssertTrue(store.due(now: date(day: 17, hour: 14)).isEmpty)
        XCTAssertEqual(store.due(now: date(day: 18, hour: 14)).map(\.kind), [.lunch, .breakfast])
    }

    // MARK: Logged meals hide their reminder

    func testMealReminderHiddenOnceThatMealIsLogged() async {
        let store = ReminderStore(scheduler: SilentScheduler(), defaults: defaults)
        await store.setEnabled(true)
        // Tuesday 17 Nov, 14:00: breakfast and lunch are due.
        let now = date(day: 17, hour: 14)
        XCTAssertEqual(store.due(now: now, loggedSlots: [.breakfast]).map(\.kind), [.lunch])
        XCTAssertTrue(store.due(now: now, loggedSlots: [.breakfast, .lunch]).isEmpty)
        // A logged snack doesn't hide anything else.
        XCTAssertEqual(store.due(now: now, loggedSlots: [.snack]).map(\.kind), [.lunch, .breakfast])
    }

    func testWorkoutAndLogDayRemindersIgnoreLoggedSlots() {
        XCTAssertNil(Reminder(kind: .workout, hour: 8, minute: 0, isOn: true).mealSlot)
        XCTAssertNil(Reminder(kind: .logDay, hour: 8, minute: 0, isOn: true).mealSlot)
    }

    // MARK: Streak nudges wait for the loop state

    func testRescheduleKeepsStreakNudgesUntilStateIsAvailable() async {
        let scheduler = SilentScheduler()
        let store = ReminderStore(scheduler: scheduler, defaults: defaults)
        await store.setEnabled(true)
        scheduler.removed = []
        await store.reschedule()
        XCTAssertFalse(scheduler.removed.contains { $0.hasPrefix("streak_") })
        store.streakState = { LoopState(streak: 4) }
        await store.reschedule()
        XCTAssertTrue(scheduler.removed.contains { $0.hasPrefix("streak_") })
    }

    func testTurningRemindersOffStillClearsStreakNudgesWithoutState() async {
        let scheduler = SilentScheduler()
        let store = ReminderStore(scheduler: scheduler, defaults: defaults)
        await store.setEnabled(false)
        XCTAssertTrue(scheduler.removed.contains { $0.hasPrefix("streak_") })
    }

    // MARK: Macro rounding

    func testMacroGramsRoundToNearest() {
        XCTAssertEqual(CalorieSummaryCard.grams(29.9), 30)
        XCTAssertEqual(CalorieSummaryCard.grams(29.4), 29)
        XCTAssertEqual(CalorieSummaryCard.grams(.nan), 0)
        XCTAssertEqual(CalorieSummaryCard.macroText(current: 29.9, goal: 120.5), "30 / 121 g")
        XCTAssertEqual(CalorieSummaryCard.macroAccessibilityText(label: "Protein", current: 29.9, goal: 120),
                       "Protein: 30 of 120 grams")
    }

    // MARK: Amount formatting

    func testAmountTextKeepsFractionsAndUnits() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(LogFoodSheet.amountText(0.5, basis: .serving, locale: en), "0.5 serving")
        XCTAssertEqual(LogFoodSheet.amountText(1, basis: .serving, locale: en), "1 serving")
        XCTAssertEqual(LogFoodSheet.amountText(2, basis: .serving, locale: en), "2 servings")
        XCTAssertEqual(LogFoodSheet.amountText(100, basis: .grams, locale: en), "100 g")
        XCTAssertEqual(LogFoodSheet.amountText(250, basis: .millilitres, locale: en), "250 ml")
        XCTAssertEqual(LogFoodSheet.amountText(0.25, basis: .serving, locale: en), "0.25 serving")
    }

    // MARK: Today's plan and log follow the day

    /// Breakfast names the weekday, indexed like `Calendar` (1 = Sunday).
    private static let weekdayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private func weekPlan() -> WeeklyMealPlan {
        func day(_ weekday: Int) -> DayPlan {
            DayPlan(pusryciai: MealItem(pavadinimas: Self.weekdayNames[weekday], ingredientai: [], kcal: 500),
                    pietus: nil, vakariene: nil, uzkandziai: nil, visoKcal: 500)
        }
        return WeeklyMealPlan(agentMessage: nil, pirmadienis: day(2), antradienis: day(3), treciadienis: day(4),
                              ketvirtadienis: day(5), pentadienis: day(6), sestadienis: day(7), sekmadienis: day(1))
    }

    private func breakfastName(on date: Date) -> String {
        Self.weekdayNames[Calendar.current.component(.weekday, from: date)]
    }

    func testMealPlanRebuildsWhenTheDayChanges() {
        let previous = AppState.shared.weeklyMealPlan
        defer { AppState.shared.weeklyMealPlan = previous }
        AppState.shared.weeklyMealPlan = weekPlan()
        let vm = HomeViewModel()
        // Fixed dates either side of midnight, so the test never depends on the real time.
        let lateEvening = date(day: 16, hour: 23, minute: 58)
        let afterMidnight = date(day: 17, hour: 0, minute: 1)
        XCTAssertNotEqual(breakfastName(on: lateEvening), breakfastName(on: afterMidnight))

        vm.tick(lateEvening)
        XCTAssertEqual(vm.mealPlan?.breakfast.first?.foodName, breakfastName(on: lateEvening))
        vm.tick(afterMidnight)
        XCTAssertEqual(vm.mealPlan?.breakfast.first?.foodName, breakfastName(on: afterMidnight),
                       "the next day shows the next weekday's meals")

        // The saved plan goes away without a notification.
        AppState.shared.weeklyMealPlan = nil
        vm.tick(afterMidnight.addingTimeInterval(120))  // same day: kept
        XCTAssertEqual(vm.mealPlan?.breakfast.first?.foodName, breakfastName(on: afterMidnight))
        vm.tick(date(day: 18, hour: 8))                 // next day: rebuilt
        XCTAssertNil(vm.mealPlan)
    }

    func testMealPlanFromWeeklyUsesTheGivenDate() {
        let weekly = weekPlan()
        for day in 15...21 {
            let d = date(day: day, hour: 12)
            XCTAssertEqual(MealPlan.from(weekly: weekly, date: d)?.breakfast.first?.foodName, breakfastName(on: d))
        }
    }

    func testTodaysTotalsFollowTheClock() {
        let log = FoodLogStore(defaults: defaults)
        let lunchDay = date(day: 10, hour: 12)
        log.add(FoodLogEntry(name: "Old", slot: .lunch, servingG: 100, calories: 300,
                             proteinG: 10, carbsG: 10, fatG: 10, loggedAt: lunchDay))
        let vm = HomeViewModel(log: log)

        let sameEvening = date(day: 10, hour: 18)
        vm.tick(sameEvening)
        XCTAssertTrue(vm.entries(for: .lunch).contains { $0.name == "Old" })
        XCTAssertTrue(vm.loggedSlots.contains(.lunch))
        XCTAssertEqual(vm.consumed, log.entries(on: sameEvening).reduce(0) { $0 + $1.calories })
        XCTAssertGreaterThanOrEqual(vm.consumed, 300)
        XCTAssertGreaterThanOrEqual(vm.proteinCurrent, 10)

        let nextMorning = date(day: 11, hour: 9)
        vm.tick(nextMorning)
        XCTAssertFalse(vm.entries(for: .lunch).contains { $0.name == "Old" })
        XCTAssertEqual(vm.consumed, log.entries(on: nextMorning).reduce(0) { $0 + $1.calories })
    }

    func testChatIgnoresNewlineOnlyMessages() async {
        let vm = HomeViewModel()
        vm.chatInput = "\n \n"
        await vm.sendChatMessage()
        XCTAssertTrue(vm.chatMessages.isEmpty)
    }
}
