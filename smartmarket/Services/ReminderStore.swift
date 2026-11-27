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
    /// Reminders the person swiped away in the app, and the day they did it.
    /// Read through `dismissed(on:)` so yesterday's swipes never hide today's cards.
    private var dismissedIDs: Set<String> = []
    private var dismissedDay = ""
    /// The evening streak nudge (only while the bell is on).
    private(set) var streakNudgeOn = true
    /// Today's loop, for the streak nudge. Set by the app at launch.
    @ObservationIgnored var streakState: (() -> LoopState)?

    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?
    @ObservationIgnored private let scheduler: any ReminderScheduling
    @ObservationIgnored private let defaults: UserDefaults
    private let key = "reminders_v1", enabledKey = "remindersEnabled_v1", dismissedKey = "remindersDismissed_v1",
                streakKey = "streakNudge_v1"

    init(scheduler: any ReminderScheduling, defaults: UserDefaults = .standard) {
        self.scheduler = scheduler
        self.defaults = defaults
        reload()
        // Turning a feature off cancels its reminders; turning it on brings them back.
        NotificationCenter.default.addObserver(forName: .enabledFeaturesDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.reschedule() }
        }
    }

    func reload() {
        isEnabled = defaults.bool(forKey: enabledKey)
        streakNudgeOn = defaults.object(forKey: streakKey) as? Bool ?? true
        let saved = ResilientStorage.loadArray(Reminder.self, key: key, defaults: defaults)
        // Keep the built-in order and pick up any kind added in a later version.
        reminders = Reminder.defaults.map { fallback in saved.first { $0.kind == fallback.kind } ?? fallback }
        // One day is stored; `dismissed(on:)` ignores it once that day has passed.
        if let stored = defaults.dictionary(forKey: dismissedKey) as? [String: [String]],
           let latest = stored.max(by: { $0.key < $1.key }) {
            dismissedDay = latest.key
            dismissedIDs = Set(latest.value)
        } else {
            dismissedDay = ""
            dismissedIDs = []
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

    func setStreakNudge(_ on: Bool, now: Date = Date(), calendar: Calendar = .current) async {
        streakNudgeOn = on
        defaults.set(on, forKey: streakKey)
        replanStreakNudges(now: now, calendar: calendar)
    }

    /// Re-plans streak nudges from today's loop. Until the app has handed over
    /// `streakState` there's nothing to plan from, so pending nudges are kept,
    /// unless the bell or the nudge is off, when they're removed.
    private func replanStreakNudges(now: Date = Date(), calendar: Calendar = .current) {
        if let state = streakState?() {
            scheduleStreakNudges(state, now: now, calendar: calendar)
        } else if !isEnabled || !streakNudgeOn {
            scheduler.remove(StreakNudge.candidateIDs(now: now, calendar: calendar))
        }
    }

    /// Replaces pending streak nudges. Nothing is added unless the bell and
    /// the streak nudge are both on and a streak is at risk.
    func scheduleStreakNudges(_ loop: LoopState, now: Date = Date(), calendar: Calendar = .current) {
        scheduler.remove(StreakNudge.candidateIDs(now: now, calendar: calendar))
        guard isEnabled, streakNudgeOn else { return }
        for item in StreakNudge.plan(now: now, todayKept: loop.todayKept, streak: loop.streak, calendar: calendar,
                                     saversHeld: loop.saversHeld) {
            scheduler.add(StreakNudge.request(item, calendar: calendar))
        }
    }

    func refreshPermission() async {
        permissionDenied = await scheduler.isDenied()
        if permissionDenied && isEnabled {
            isEnabled = false
            defaults.set(false, forKey: enabledKey)
            // Clears what was scheduled, so nothing fires if permission comes back.
            await reschedule()
        }
    }

    // MARK: Scheduling

    /// Replaces every pending reminder with the current set. One run at a
    /// time: a newer call cancels the one still waiting, so two can't interleave.
    func reschedule() async {
        rescheduleTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.replacePending()
        }
        rescheduleTask = task
        await task.value
    }

    private func replacePending() async {
        let pending = await scheduler.pendingReminderIdentifiers()
        // Nothing below waits, so a run that gets past here finishes whole.
        guard !Task.isCancelled else { return }
        scheduler.remove(pending)
        replanStreakNudges()
        guard isEnabled else { return }
        // Only reminders for the features the person chose (no workout nudges without Workouts).
        let features = AppFeature.load(from: defaults)
        for reminder in reminders where reminder.isOn && FeatureLayout.offersReminder(reminder.kind, features) {
            for request in Self.requests(for: reminder) { scheduler.add(request) }
        }
    }

    /// One repeating request per chosen weekday, or a single daily one. The
    /// workout reminder carries a line of encouragement instead of a fixed text:
    /// it always gets one request per day, so each training day has its own
    /// line, and the lines move on each week (the app replans them when it opens).
    static func requests(for reminder: Reminder, now: Date = Date(), calendar: Calendar = .current) -> [UNNotificationRequest] {
        let isWorkout = reminder.kind == .workout
        let week = calendar.component(.weekOfYear, from: now)
        let everyDay: [Int?] = isWorkout ? (1...7).map { $0 } : [nil]
        let days: [Int?] = reminder.weekdays.isEmpty ? everyDay : reminder.weekdays.sorted().map { $0 }
        return days.map { weekday in
            let content = UNMutableNotificationContent()
            content.title = isWorkout ? "Time to train" : reminder.title
            content.body = isWorkout ? TrainingMotivation.line(week: week, weekday: weekday ?? 1) : reminder.message
            content.sound = .default
            content.userInfo = ["reminder": reminder.kind.rawValue]
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
    /// newest first: what the Home stack shows. A meal reminder is left out
    /// once something is logged for that meal today (`loggedSlots`).
    func due(now: Date = Date(), loggedSlots: Set<MealSlot> = []) -> [Reminder] {
        guard isEnabled else { return [] }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let dismissed = dismissed(on: now)
        return reminders
            .filter { $0.isOn && FeatureLayout.offersReminder($0.kind, AppFeature.load(from: defaults)) && $0.isScheduled(on: weekday) && $0.hour * 60 + $0.minute <= minutes
                      && !dismissed.contains($0.id)
                      && !($0.mealSlot.map(loggedSlots.contains) ?? false) }
            .sorted { $0.hour * 60 + $0.minute > $1.hour * 60 + $1.minute }
    }

    /// The reminders swiped away on `date`'s day; empty once that day has passed.
    func dismissed(on date: Date) -> Set<String> {
        dismissedDay == Self.dayKey(date) ? dismissedIDs : []
    }

    func dismiss(_ reminder: Reminder, now: Date = Date()) {
        markDismissed([reminder.id], now: now)
    }

    func dismissAllDue(now: Date = Date(), loggedSlots: Set<MealSlot> = []) {
        markDismissed(due(now: now, loggedSlots: loggedSlots).map(\.id), now: now)
    }

    /// Adds to the day's dismissals, starting afresh on a new day.
    private func markDismissed(_ ids: [String], now: Date) {
        let day = Self.dayKey(now)
        dismissedIDs = dismissed(on: now).union(ids)
        dismissedDay = day
        defaults.set([day: Array(dismissedIDs)], forKey: dismissedKey)
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Training motivation

/// Short lines of encouragement for the workout reminder. Written for Nourlo,
/// not quoted from anyone, and free of promises about results.
enum TrainingMotivation {
    static let lines = [
        "You never regret the session you showed up for.",
        "Start small. Ten minutes still counts.",
        "Today's effort is tomorrow's easier day.",
        "You don't have to feel ready. You just have to start.",
        "One more session, one step closer.",
        "Strong is built on ordinary days like this one.",
        "Your future self is cheering for you right now.",
        "Show up for yourself. The rest follows.",
        "Progress is quiet. Keep going.",
        "The hardest part is the first five minutes.",
        "A little today beats a lot someday.",
        "Move your body, clear your head.",
        "You've done hard things before. This is one more.",
        "Consistency beats intensity. Just begin.",
        "This hour is yours. Use it well.",
        "Every rep is a vote for the person you're becoming.",
        "Tired is a feeling. Proud lasts longer.",
        "Shoes on. That's the whole plan for the next minute.",
        "Do it for the energy you'll have afterwards.",
        "Small steps, repeated, move mountains.",
        "You're stronger than the excuse.",
        "Not perfect, just present. Let's go.",
        "The work you do today stays with you.",
        "Make this session the best part of your day.",
        "Keep the promise you made to yourself.",
        "Slow progress is still progress.",
        "Your body can do it. Bring your mind along.",
        "Warm up, breathe, begin.",
    ]

    /// A different line for each training day, moving on every week.
    static func line(week: Int, weekday: Int) -> String {
        lines[abs(week * 7 + weekday) % lines.count]
    }
}
