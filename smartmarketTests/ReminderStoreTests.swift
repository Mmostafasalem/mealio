import XCTest
import UserNotifications
@testable import smartmarket

@MainActor
private final class FakeScheduler: ReminderScheduling {
    var grants = true
    var pending: [UNNotificationRequest] = []
    func requestAuthorization() async -> Bool { grants }
    func isDenied() async -> Bool { !grants }
    func pendingReminderIdentifiers() async -> [String] { pending.map(\.identifier) }
    func remove(_ identifiers: [String]) { pending.removeAll { identifiers.contains($0.identifier) } }
    func add(_ request: UNNotificationRequest) { pending.append(request) }
}

@MainActor
final class ReminderStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "ReminderStoreTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testNothingIsScheduledUntilRemindersAreTurnedOn() async {
        let scheduler = FakeScheduler()
        let store = ReminderStore(scheduler: scheduler, defaults: defaults)
        XCTAssertFalse(store.isEnabled)
        await store.reschedule()
        XCTAssertTrue(scheduler.pending.isEmpty)
        XCTAssertTrue(store.due().isEmpty)
    }

    func testTurningOnSchedulesOneRequestPerDailyReminderAndPerWorkoutDay() async {
        let scheduler = FakeScheduler()
        let store = ReminderStore(scheduler: scheduler, defaults: defaults)
        await store.setEnabled(true)
        XCTAssertTrue(store.isEnabled)
        // Defaults: breakfast, lunch, dinner daily; workout on three days.
        let ids = Set(scheduler.pending.map(\.identifier))
        XCTAssertEqual(ids, ["reminder_breakfast", "reminder_lunch", "reminder_dinner",
                             "reminder_workout_2", "reminder_workout_4", "reminder_workout_6"])
        for request in scheduler.pending {
            let trigger = try? XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
            XCTAssertEqual(trigger?.repeats, true)
            XCTAssertFalse(request.content.body.isEmpty)
        }
        let lunch = scheduler.pending.first { $0.identifier == "reminder_lunch" }?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(lunch?.dateComponents.hour, 13)
        XCTAssertNil(lunch?.dateComponents.weekday)
    }

    func testDeniedPermissionLeavesRemindersOffAndSaysWhy() async {
        let scheduler = FakeScheduler()
        scheduler.grants = false
        let store = ReminderStore(scheduler: scheduler, defaults: defaults)
        await store.setEnabled(true)
        XCTAssertFalse(store.isEnabled)
        XCTAssertTrue(store.permissionDenied)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testTurningOffRemovesEveryPendingReminder() async {
        let scheduler = FakeScheduler()
        let store = ReminderStore(scheduler: scheduler, defaults: defaults)
        await store.setEnabled(true)
        XCTAssertFalse(scheduler.pending.isEmpty)
        await store.setEnabled(false)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testChangesPersistAndReload() async {
        let scheduler = FakeScheduler()
        let store = ReminderStore(scheduler: scheduler, defaults: defaults)
        await store.setEnabled(true)
        var lunch = try! XCTUnwrap(store.reminders.first { $0.kind == .lunch })
        lunch.hour = 12; lunch.minute = 30
        store.update(lunch)
        let reloaded = ReminderStore(scheduler: scheduler, defaults: defaults)
        XCTAssertTrue(reloaded.isEnabled)
        XCTAssertEqual(reloaded.reminders.first { $0.kind == .lunch }?.hour, 12)
        XCTAssertEqual(reloaded.reminders.first { $0.kind == .lunch }?.minute, 30)
        XCTAssertEqual(reloaded.reminders.count, Reminder.defaults.count)
    }

    func testDueShowsOnlyPastRemindersForTodayUntilDismissed() async {
        let scheduler = FakeScheduler()
        let store = ReminderStore(scheduler: scheduler, defaults: defaults)
        await store.setEnabled(true)
        // 14:00 on a Tuesday (weekday 3): breakfast and lunch are due, dinner is not,
        // and the Mon/Wed/Fri workout isn't today.
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 17; c.hour = 14
        let now = try! XCTUnwrap(Calendar.current.date(from: c))
        XCTAssertEqual(Calendar.current.component(.weekday, from: now), 3)
        XCTAssertEqual(store.due(now: now).map(\.kind), [.lunch, .breakfast])
        store.dismiss(try! XCTUnwrap(store.reminders.first { $0.kind == .lunch }))
        XCTAssertEqual(store.due(now: now).map(\.kind), [.breakfast])
    }
}
