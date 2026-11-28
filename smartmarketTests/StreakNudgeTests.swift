import XCTest
import UserNotifications
@testable import smartmarket

@MainActor
private final class RecordingScheduler: ReminderScheduling {
    var granted = true
    var added: [UNNotificationRequest] = []
    var removed: [String] = []
    func requestAuthorization() async -> Bool { granted }
    func isDenied() async -> Bool { !granted }
    func pendingReminderIdentifiers() async -> [String] { [] }
    func remove(_ identifiers: [String]) { removed += identifiers; added.removeAll { identifiers.contains($0.identifier) } }
    func add(_ request: UNNotificationRequest) { added.append(request) }
}

@MainActor
final class StreakNudgeTests: XCTestCase {
    private typealias F = LoopFixture

    func testPlanSkipsTodayWhenKept() {
        let plan = StreakNudge.plan(now: F.date(0, hour: 12), todayKept: true, streak: 5, calendar: F.calendar)
        XCTAssertEqual(plan.map(\.id), ["streak_\(F.day(1))", "streak_\(F.day(2))"])
        XCTAssertTrue(plan[0].body.contains("5-day"))
    }

    func testPlanTodayNamesStreak() {
        let plan = StreakNudge.plan(now: F.date(0, hour: 12), todayKept: false, streak: 12, calendar: F.calendar)
        XCTAssertEqual(plan.first?.id, "streak_\(F.day(0))")
        XCTAssertEqual(plan.first?.body, "Nourlo's getting sleepy… one quest keeps your 12-day streak.")
        XCTAssertEqual(F.calendar.component(.hour, from: plan[0].fire), 20)
    }

    func testTomorrowCopyWhenTodayNotKept() {
        let plan = StreakNudge.plan(now: F.date(0, hour: 12), todayKept: false, streak: 12, calendar: F.calendar)
        XCTAssertEqual(plan[1].body, "Nourlo misses you. Log one thing to start a new streak.")
    }

    func testThirdEveningCopy() {
        let plan = StreakNudge.plan(now: F.date(0, hour: 12), todayKept: false, streak: 3, calendar: F.calendar)
        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual(plan[2].body, "Nourlo saved you a spot. One quest is all it takes.")
    }

    func testNoNudgesWhenNoStreak() {
        XCTAssertEqual(StreakNudge.plan(now: F.date(0, hour: 12), todayKept: false, streak: 0, calendar: F.calendar).count, 0)
    }

    func testAfterEightSkipsToday() {
        let plan = StreakNudge.plan(now: F.date(0, hour: 20, minute: 5), todayKept: false, streak: 4, calendar: F.calendar)
        XCTAssertEqual(plan.first?.id, "streak_\(F.day(1))")
    }

    func testRescheduleRemovesAndAddsNothingWhenRemindersOff() async {
        let scheduler = RecordingScheduler()
        let store = ReminderStore(scheduler: scheduler, defaults: UserDefaults(suiteName: "nudge-\(UUID())")!)
        store.scheduleStreakNudges(LoopState(streak: 5), now: F.date(0, hour: 12), calendar: F.calendar)
        XCTAssertTrue(scheduler.added.isEmpty)
        XCTAssertTrue(scheduler.removed.contains("streak_\(F.day(0))"))
    }

    func testRescheduleAddsThreeWhenOn() async {
        let scheduler = RecordingScheduler()
        let store = ReminderStore(scheduler: scheduler, defaults: UserDefaults(suiteName: "nudge-\(UUID())")!)
        await store.setEnabled(true)
        store.scheduleStreakNudges(LoopState(streak: 5), now: F.date(0, hour: 12), calendar: F.calendar)
        XCTAssertEqual(scheduler.added.filter { $0.identifier.hasPrefix("streak_") }.count, 3)
        await store.setStreakNudge(false, now: F.date(0, hour: 12), calendar: F.calendar)
        XCTAssertEqual(scheduler.added.filter { $0.identifier.hasPrefix("streak_") }.count, 0)
    }
}
