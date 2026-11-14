import Foundation
import Observation
import UserNotifications

// MARK: - Reminders
//
// Gentle local reminders for meals, training and logging. Everything is
// scheduled on the phone with repeating calendar triggers: nothing is sent to
// a server, and nothing here makes claims about prices, stock or offers.

struct Reminder: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case breakfast, lunch, dinner, snack, workout, logDay
    }

    var id: String { kind.rawValue }
    let kind: Kind
    var hour: Int
    var minute: Int
    var isOn: Bool
    /// Calendar weekdays (1 = Sunday … 7 = Saturday). Empty means every day.
    var weekdays: Set<Int> = []

    var title: String {
        switch kind {
        case .breakfast: return "Breakfast"
        case .lunch:     return "Lunch"
        case .dinner:    return "Dinner"
        case .snack:     return "Snack"
        case .workout:   return "Workout"
        case .logDay:    return "Log your day"
        }
    }

    var symbol: String {
        switch kind {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.fill"
        case .snack:     return "sparkles"
        case .workout:   return "figure.run"
        case .logDay:    return "checklist"
        }
    }

    /// What the notification (and the in-app card) says.
    var message: String {
        switch kind {
        case .breakfast: return "Time for breakfast. Log it when you've eaten."
        case .lunch:     return "Lunch time. Your plan for today is in Meals."
        case .dinner:    return "Dinner time. Log it to close out your day."
        case .snack:     return "Snack break. A small one keeps you on target."
        case .workout:   return "Time to move. Build a session in Train."
        case .logDay:    return "Anything left to log today? It takes a minute."
        }
    }

    var mealSlot: MealSlot? { MealSlot(rawValue: kind.rawValue) }

    var timeText: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    func isScheduled(on weekday: Int) -> Bool { weekdays.isEmpty || weekdays.contains(weekday) }

    static let defaults: [Reminder] = [
        Reminder(kind: .breakfast, hour: 8, minute: 0, isOn: true),
        Reminder(kind: .lunch, hour: 13, minute: 0, isOn: true),
        Reminder(kind: .dinner, hour: 19, minute: 0, isOn: true),
        Reminder(kind: .snack, hour: 16, minute: 0, isOn: false),
        Reminder(kind: .workout, hour: 18, minute: 0, isOn: true, weekdays: [2, 4, 6]),
        Reminder(kind: .logDay, hour: 21, minute: 0, isOn: false),
    ]
}

/// Where reminders get scheduled; injectable so tests need no permissions.
@MainActor
protocol ReminderScheduling {
    func requestAuthorization() async -> Bool
    func isDenied() async -> Bool
    func pendingReminderIdentifiers() async -> [String]
    func remove(_ identifiers: [String])
    func add(_ request: UNNotificationRequest)
}

@MainActor
private struct SystemReminderScheduler: ReminderScheduling {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }
    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }
    func pendingReminderIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(ReminderStore.prefix) }
    }
    func remove(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func add(_ request: UNNotificationRequest) { center.add(request) }
}

@MainActor
@Observable
final class ReminderStore {

    static let shared = ReminderStore(scheduler: SystemReminderScheduler())
    static let prefix = "reminder_"

    /// The master switch (the bell). Off by default: nothing is scheduled and
    /// permission is not asked until the person turns it on.
    private(set) var isEnabled = false
    private(set) var reminders: [Reminder] = Reminder.defaults
    /// True when iOS notifications are switched off for the app.
    private(set) var permissionDenied = false
    /// Reminders the person swiped away in the app today.
    private(set) var dismissedToday: Set<String> = []

    @ObservationIgnored private let scheduler: any ReminderScheduling
    @ObservationIgnored private let defaults: UserDefaults
    private let key = "reminders_v1", enabledKey = "remindersEnabled_v1", dismissedKey = "remindersDismissed_v1"

    init(scheduler: any ReminderScheduling, defaults: UserDefaults = .standard) {
        self.scheduler = scheduler
        self.defaults = defaults
        reload()
    }

    func reload() {
        isEnabled = defaults.bool(forKey: enabledKey)
        let saved = ResilientStorage.loadArray(Reminder.self, key: key, defaults: defaults)
        // Keep the built-in order and pick up any kind added in a later version.
        reminders = Reminder.defaults.map { fallback in saved.first { $0.kind == fallback.kind } ?? fallback }
        if let stored = defaults.dictionary(forKey: dismissedKey) as? [String: [String]],
           let today = stored[Self.dayKey(Date())] {
            dismissedToday = Set(today)
        } else {
            dismissedToday = []
        }
    }

    var activeCount: Int { isEnabled ? reminders.filter(\.isOn).count : 0 }

    // MARK: Changes

    /// Turning reminders on asks iOS for permission the first time.
    func setEnabled(_ on: Bool) async {
        if on {
            let granted = await scheduler.requestAuthorization()
            permissionDenied = !granted
            isEnabled = granted
        } else {
            isEnabled = false
        }
        defaults.set(isEnabled, forKey: enabledKey)
        await reschedule()
    }

    func update(_ reminder: Reminder) {
        guard let index = reminders.firstIndex(where: { $0.kind == reminder.kind }) else { return }
        reminders[index] = reminder
        if let data = try? JSONEncoder().encode(reminders) { defaults.set(data, forKey: key) }
        Task { await reschedule() }
    }

    func refreshPermission() async {
        permissionDenied = await scheduler.isDenied()
        if permissionDenied && isEnabled {
            isEnabled = false
            defaults.set(false, forKey: enabledKey)
        }
    }

    // MARK: Scheduling

    /// Replaces every pending reminder with the current set.
    func reschedule() async {
        scheduler.remove(await scheduler.pendingReminderIdentifiers())
        guard isEnabled else { return }
        for reminder in reminders where reminder.isOn {
            for request in Self.requests(for: reminder) { scheduler.add(request) }
        }
    }

    /// One repeating request per chosen weekday, or a single daily one.
    static func requests(for reminder: Reminder) -> [UNNotificationRequest] {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.message
        content.sound = .default
        content.userInfo = ["reminder": reminder.kind.rawValue]
        let days: [Int?] = reminder.weekdays.isEmpty ? [nil] : reminder.weekdays.sorted().map { $0 }
        return days.map { weekday in
            var when = DateComponents()
            when.hour = reminder.hour
            when.minute = reminder.minute
            when.weekday = weekday
            return UNNotificationRequest(
                identifier: prefix + reminder.kind.rawValue + (weekday.map { "_\($0)" } ?? ""),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
        }
    }

    // MARK: In-app stack

    /// Today's reminders whose time has come and that haven't been swiped away,
    /// newest first: what the Home stack shows.
    func due(now: Date = Date()) -> [Reminder] {
        guard isEnabled else { return [] }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return reminders
            .filter { $0.isOn && $0.isScheduled(on: weekday) && $0.hour * 60 + $0.minute <= minutes
                      && !dismissedToday.contains($0.id) }
            .sorted { $0.hour * 60 + $0.minute > $1.hour * 60 + $1.minute }
    }

    func dismiss(_ reminder: Reminder) {
        dismissedToday.insert(reminder.id)
        defaults.set([Self.dayKey(Date()): Array(dismissedToday)], forKey: dismissedKey)
    }

    func dismissAllDue() {
        for reminder in due() { dismissedToday.insert(reminder.id) }
        defaults.set([Self.dayKey(Date()): Array(dismissedToday)], forKey: dismissedKey)
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
