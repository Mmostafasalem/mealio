import Foundation
import HealthKit

// MARK: - Apple Health sync rules
//
// The pure part of the Apple Health integration: which log entries and
// workouts to write or remove, what values a food entry becomes, which Health
// workout type a session is, and when to suggest Health's weight. No
// HealthKit store access here, so tests run without entitlements.

enum HealthSync {

    /// How far back food and workouts are written. Older entries are left
    /// alone: never written on first sync, never removed later.
    static let window: TimeInterval = 7 * 24 * 3600

    /// Bumped if the shape of written samples ever changes.
    static let syncVersion = 1

    /// Metadata key carried by every sample Nourlo writes, holding the food
    /// log entry id or the workout session id, so removals find every part.
    static let entryKey = "NourloEntryID"

    // MARK: Diff

    struct Plan: Equatable {
        /// Ids to write now.
        var add: Set<String>
        /// Ids written earlier whose entry is gone: remove from Health.
        var remove: Set<String>
        /// The bookkeeping to keep once `add` and `remove` succeed, minus
        /// ids that fell out of the window (left in Health, no longer tracked).
        var keep: [String: Date]
    }

    /// - Parameters:
    ///   - current: every entry the app has now, id → date.
    ///   - written: what was already written to Health, id → entry date.
    ///   - now: the moment of the sync.
    static func plan(current: [String: Date], written: [String: Date], now: Date) -> Plan {
        let start = now.addingTimeInterval(-window)
        let inWindow = current.filter { $0.value >= start }
        let add = Set(inWindow.keys).subtracting(written.keys)
        let recentWritten = written.filter { $0.value >= start }
        let remove = Set(recentWritten.keys).subtracting(current.keys)
        let keep = recentWritten.filter { !remove.contains($0.key) }
        return Plan(add: add, remove: remove, keep: keep)
    }

    // MARK: Food

    /// What one food log entry becomes in Apple Health.
    struct FoodValues: Equatable {
        let syncID: String
        let name: String
        let date: Date
        let kcal: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
    }

    static func foodValues(for entry: FoodLogEntry) -> FoodValues {
        FoodValues(syncID: entry.id,
                   name: entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Food" : entry.name,
                   date: entry.loggedAt,
                   kcal: max(0, Double(entry.calories)),
                   proteinG: clean(entry.proteinG),
                   carbsG: clean(entry.carbsG),
                   fatG: clean(entry.fatG))
    }

    private static func clean(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    // MARK: Workouts

    static func activityType(for kind: ExerciseKind) -> HKWorkoutActivityType {
        switch kind {
        case .gym:      return .traditionalStrengthTraining
        case .cardio:   return .mixedCardio
        case .home:     return .functionalStrengthTraining
        case .mobility: return .flexibility
        }
    }

    /// The real start and finish of a workout tracked with Start workout; `nil`
    /// for one only marked as done (those stay in Nourlo, not in Apple Health).
    static func interval(for workout: CompletedWorkout) -> DateInterval? {
        guard let start = workout.trackedStart, let end = workout.trackedEnd else { return nil }
        // HealthKit needs a workout to end after it starts.
        return DateInterval(start: start, end: max(end, start.addingTimeInterval(1)))
    }

    /// Only tracked workouts are written to Apple Health.
    static func isTracked(_ workout: CompletedWorkout) -> Bool { interval(for: workout) != nil }

    /// The workouts the diff should know about: tracked ones only, id → when they finished.
    static func trackedWorkouts(_ completed: [CompletedWorkout]) -> [String: CompletedWorkout] {
        var byID: [String: CompletedWorkout] = [:]
        for workout in completed where isTracked(workout) { byID[workout.id.uuidString] = workout }
        return byID
    }

    /// Most the estimate is scaled up for a session longer than planned.
    static let maxEnergyScale = 1.5

    /// Active energy written with a tracked workout: the plan's estimate scaled to
    /// the minutes actually trained (tracked / planned), at most 1.5×. `nil` when
    /// untracked or there's nothing to write.
    static func trackedEnergyKcal(for workout: CompletedWorkout) -> Double? {
        guard let interval = interval(for: workout), workout.calories > 0 else { return nil }
        let planned = Double(max(1, workout.minutes))
        let scale = min(interval.duration / 60 / planned, maxEnergyScale)
        let kcal = (Double(workout.calories) * scale).rounded()
        return kcal > 0 ? kcal : nil
    }

    // MARK: Weight

    /// Health's latest weight, offered only when it differs from the profile
    /// by at least 0.1 kg and was measured after the profile weight was last
    /// set (`nil` edit date: never recorded, so any reading counts).
    static func weightSuggestion(healthKg: Double?, measuredAt: Date?, profileKg: Double,
                                 profileEditedAt: Date?,
                                 range: ClosedRange<Double> = WeightRuler.defaultRange) -> Double? {
        guard let healthKg, let measuredAt, healthKg.isFinite else { return nil }
        let rounded = (healthKg * 10).rounded() / 10
        // Outside what the profile accepts: a stray reading, not a suggestion.
        guard range.contains(rounded) else { return nil }
        guard abs(rounded - profileKg) >= 0.1 - 1e-9 else { return nil }
        if let profileEditedAt, measuredAt <= profileEditedAt { return nil }
        return rounded
    }
}
