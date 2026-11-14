import Foundation

// MARK: - Shared between the app and its widget extension
//
// This folder is compiled into both targets. Keep it free of app-only types:
// plain value types, Codable, Sendable, no singletons from the app.

/// The App Group both targets read and write. Registered on the team as
/// `group.com.mostafa.mealio` (see the .entitlements files).
nonisolated enum NourloAppGroup {
    static let identifier = "group.com.mostafa.mealio"

    /// The shared defaults, or `nil` when the App Group isn't available
    /// (unsigned simulator test runs, or a build without the capability).
    static var defaults: UserDefaults? { UserDefaults(suiteName: identifier) }
}

/// Today's numbers, written by the app whenever they change and shown by the
/// widgets, Siri answers and the Control Center button.
nonisolated struct NourloSnapshot: Codable, Equatable, Sendable {
    struct Meal: Codable, Equatable, Sendable {
        var slot: String          // "Breakfast", "Lunch", "Dinner", "Snacks"
        var name: String
        var kcal: Int
    }

    var date: Date
    var caloriesEaten: Int
    var calorieGoal: Int
    var proteinG: Int
    var proteinGoalG: Int
    var carbsG: Int
    var carbsGoalG: Int
    var fatG: Int
    var fatGoalG: Int
    var meals: [Meal]
    var streakDays: Int
    /// Tomorrow's planned meals, so the meals widget can turn over at midnight
    /// without the app. Optional: snapshots saved before it existed still decode.
    var nextDayMeals: [Meal]? = nil

    var caloriesLeft: Int { max(calorieGoal - caloriesEaten, 0) }
    var progress: Double { calorieGoal > 0 ? min(Double(caloriesEaten) / Double(calorieGoal), 1) : 0 }

    /// Whether this snapshot describes the given day (a widget must not show yesterday's totals).
    func isFor(_ day: Date, calendar: Calendar = .current) -> Bool { calendar.isDate(date, inSameDayAs: day) }

    /// What a widget shows before the app has written anything, or on a new day.
    static func empty(on day: Date = Date(), goal: Int = 2000) -> NourloSnapshot {
        NourloSnapshot(date: day, caloriesEaten: 0, calorieGoal: goal, proteinG: 0, proteinGoalG: 0,
                       carbsG: 0, carbsGoalG: 0, fatG: 0, fatGoalG: 0, meals: [], streakDays: 0)
    }

    static let placeholder = NourloSnapshot(
        date: Date(), caloriesEaten: 1240, calorieGoal: 2100, proteinG: 82, proteinGoalG: 140,
        carbsG: 130, carbsGoalG: 230, fatG: 41, fatGoalG: 70,
        meals: [.init(slot: "Breakfast", name: "Oats with berries", kcal: 420),
                .init(slot: "Lunch", name: "Chicken rice bowl", kcal: 640),
                .init(slot: "Dinner", name: "Salmon and potatoes", kcal: 610)],
        streakDays: 4)
}

nonisolated enum NourloSnapshotStore {
    private static let key = "nourloSnapshot_v1"

    static func load(from defaults: UserDefaults? = NourloAppGroup.defaults) -> NourloSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NourloSnapshot.self, from: data)
    }

    /// Today's snapshot: the saved one if it is for today, otherwise an empty day
    /// that keeps the saved goal.
    static func today(from defaults: UserDefaults? = NourloAppGroup.defaults, now: Date = Date()) -> NourloSnapshot {
        guard let saved = load(from: defaults) else { return .empty(on: now) }
        if saved.isFor(now) { return saved }
        var fresh = NourloSnapshot.empty(on: now, goal: saved.calorieGoal)
        fresh.proteinGoalG = saved.proteinGoalG; fresh.carbsGoalG = saved.carbsGoalG; fresh.fatGoalG = saved.fatGoalG
        fresh.streakDays = saved.streakDays
        // Saved yesterday: its "tomorrow" plan is today's.
        if let next = Calendar.current.date(byAdding: .day, value: 1, to: saved.date),
           Calendar.current.isDate(next, inSameDayAs: now) {
            fresh.meals = saved.nextDayMeals ?? []
        }
        return fresh
    }

    /// Saves the snapshot; returns whether it changed (so callers only reload widgets when needed).
    /// Only what a widget shows counts as a change: the snapshot's day, not its time
    /// of day, so re-syncing the same numbers later the same day costs no reload.
    @discardableResult
    static func save(_ snapshot: NourloSnapshot, to defaults: UserDefaults? = NourloAppGroup.defaults,
                     calendar: Calendar = .current) -> Bool {
        // Compare values, not bytes: JSON key order isn't guaranteed to be stable.
        guard let defaults else { return false }
        var stored = snapshot
        stored.date = calendar.startOfDay(for: snapshot.date)
        if let saved = load(from: defaults), sameContent(saved, stored, calendar: calendar) { return false }
        guard let data = try? JSONEncoder().encode(stored) else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    /// Whether two snapshots show the same thing: same day, same numbers and meals.
    static func sameContent(_ a: NourloSnapshot, _ b: NourloSnapshot, calendar: Calendar = .current) -> Bool {
        guard calendar.isDate(a.date, inSameDayAs: b.date) else { return false }
        var a = a
        a.date = b.date
        return a == b
    }
}

/// Deep links the widgets and intents open (`nourlo://…`).
nonisolated enum NourloLink: String, CaseIterable, Sendable {
    case home, logFood = "log-food", meals, groceries, train, scan

    static let scheme = "nourlo"
    var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host, let link = NourloLink(rawValue: host) else { return nil }
        self = link
    }
}
