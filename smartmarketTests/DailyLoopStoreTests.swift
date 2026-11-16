import XCTest
@testable import smartmarket

@MainActor
final class DailyLoopStoreTests: XCTestCase {
    private typealias F = LoopFixture
    private var defaults: UserDefaults!
    private var source = LoopSource(foodEntries: [], stockEntryIDs: [], workouts: [], calorieGoal: 2000,
                                    proteinGoal: 90, cartHasItems: false, cartWithinBudget: false, hasStock: false)

    override func setUp() {
        defaults = UserDefaults(suiteName: "DailyLoopStoreTests-\(UUID().uuidString)")
    }

    private func makeStore() -> DailyLoopStore {
        DailyLoopStore(defaults: defaults, calendar: F.calendar, source: { [unowned self] in self.source })
    }

    private func events(_ store: DailyLoopStore) -> [LoopEvent] { store.ledger }

    func testFirstRefreshStartsLoopOnce() {
        let store = makeStore()
        store.refresh(now: F.date())
        store.refresh(now: F.date())
        XCTAssertEqual(events(store).filter { $0 == .loopStarted(F.day()) }.count, 1)
    }

    func testQuestCompletionRecordedOnceAndSetsLastCompletion() {
        // Breakfast + a workout satisfy whichever easy quest leads today.
        source.foodEntries = [F.food(slot: .breakfast)]
        source.workouts = [F.workout()]
        let store = makeStore()
        store.refresh(now: F.date())
        let doneCount = events(store).filter { if case .questDone = $0 { return true }; return false }.count
        XCTAssertGreaterThan(doneCount, 0)
        let first = store.lastCompletion
        XCTAssertNotNil(first)
        store.refresh(now: F.date(0, hour: 13))
        XCTAssertEqual(store.lastCompletion, first)
        XCTAssertEqual(events(store).filter { if case .questDone = $0 { return true }; return false }.count, doneCount)
    }

    func testDeletingEntryUnticksQuestButKeepsRecord() {
        source.foodEntries = [F.food()]
        let store = makeStore()
        store.refresh(now: F.date())
        XCTAssertTrue(store.state.todayKept)
        let recorded = events(store)
        source.foodEntries = []
        store.refresh(now: F.date(0, hour: 13))
        XCTAssertFalse(store.state.todayKept)
        XCTAssertFalse(store.state.quests.contains { $0.isDone })
        XCTAssertEqual(events(store), recorded)
    }

    func testCartCheckInOnlyAfterCartChange() {
        source.cartHasItems = true; source.cartWithinBudget = true
        let store = makeStore()
        store.refresh(now: F.date())
        XCTAssertFalse(store.state.todayKept)
        store.cartChanged(now: F.date())
        XCTAssertTrue(store.state.todayKept)
        XCTAssertTrue(events(store).contains(.budgetCheckIn(F.day())))
    }

    func testOverBudgetCartDoesNotCheckIn() {
        source.cartHasItems = true; source.cartWithinBudget = false
        let store = makeStore()
        store.cartChanged(now: F.date())
        XCTAssertFalse(events(store).contains(.budgetCheckIn(F.day())))
    }

    func testLedgerSurvivesReload() {
        source.foodEntries = [F.food(-1)]
        let a = makeStore()
        a.cartChanged(now: F.date()) // no cart → nothing
        source.cartHasItems = true; source.cartWithinBudget = true
        a.cartChanged(now: F.date())
        let b = makeStore()
        b.refresh(now: F.date())
        XCTAssertEqual(b.state.streak, 2)
    }

    func testMilestonePendingThenConsumed() {
        source.foodEntries = (0...2).map { F.food(-$0) }
        let store = makeStore()
        store.refresh(now: F.date())
        XCTAssertEqual(store.pendingMilestone, 3)
        store.consumeMilestone()
        XCTAssertNil(store.pendingMilestone)
        store.refresh(now: F.date(0, hour: 14))
        XCTAssertNil(store.pendingMilestone)
    }

    // Review fixes
    func testTodaysQuestsStayPutWhenTheCartEmpties() {
        source.cartHasItems = true; source.cartWithinBudget = true; source.hasStock = true
        let store = makeStore()
        store.refresh(now: F.date())
        let morning = store.state.quests.map(\.id)
        source.cartHasItems = false; source.hasStock = false; source.calorieGoal = 0
        store.refresh(now: F.date(0, hour: 15))
        XCTAssertEqual(store.state.quests.map(\.id), morning)
    }

    func testPerfectTodayFollowsCurrentEntries() {
        let store = makeStore()
        defaults.set(try! JSONEncoder().encode([LoopEvent.loopStarted(F.day()), .perfectDay(F.day())]), forKey: DailyLoopStore.key)
        store.refresh(now: F.date())
        XCTAssertFalse(store.state.perfectToday)
    }

    func testStateForNudgeRefreshesFirst() {
        source.foodEntries = [F.food(-1)]
        let store = makeStore()
        store.refresh(now: F.date())
        XCTAssertFalse(store.state.todayKept)
        source.workouts = [F.workout()]
        XCTAssertTrue(store.stateForNudge(now: F.date(0, hour: 19)).todayKept)
    }

    func testPastKeptDaysAreRecorded() {
        source.workouts = [F.workout(-2), F.workout(-1)]
        let store = makeStore()
        store.refresh(now: F.date(-3)) // loop starts before the workouts
        store.refresh(now: F.date())
        source.workouts = [F.workout(-1)] // day -2 falls out of the capped history
        store.refresh(now: F.date(0, hour: 13))
        XCTAssertEqual(store.state.streak, 2)
    }

    func testCalendarIsReadOnEveryRefresh() {
        var zone = TimeZone(identifier: "Europe/Vilnius")!
        let store = DailyLoopStore(defaults: defaults, calendar: {
            var c = Calendar(identifier: .gregorian); c.timeZone = zone; c.firstWeekday = 2; return c
        }, source: { [unowned self] in self.source })
        // 23:30 in Vilnius on day -1 is 16:30 the same day in New York.
        source.foodEntries = [F.food(0, hour: 3)] // 03:00 Vilnius today = 20:00 yesterday in New York
        store.refresh(now: F.date(0, hour: 12))
        XCTAssertTrue(store.state.todayKept)
        zone = TimeZone(identifier: "America/New_York")!
        store.refresh(now: F.date(0, hour: 12)) // 05:00 today in New York
        XCTAssertFalse(store.state.todayKept)
    }
}
