import Foundation
import Observation

// MARK: - What was really lifted
//
// Workout mode records every set (weight, reps or time) and keeps the finished
// workouts here, on the phone. Personal records are worked out against
// everything logged before. Weights are always stored in kilograms.

/// How an exercise is measured.
enum ExerciseTracking: String, Codable, CaseIterable {
    case weightReps, reps, time

    var title: String {
        switch self {
        case .weightReps: return "Weight and reps"
        case .reps:       return "Reps only"
        case .time:       return "Time"
        }
    }

    /// A good guess from the step and the catalogue: timed steps are timed, kit with a weight is weighed.
    static func guess(for step: WorkoutExercise) -> ExerciseTracking {
        if let chosen = step.tracking { return chosen }
        if let custom = CustomExerciseStore.shared.exercise(named: step.name) { return custom.tracking }
        let reps = step.reps.lowercased()
        if step.minutes > 0 || reps.contains("sec") || reps.contains("min") { return .time }
        let equipment = (Exercise.closestMatch(name: step.name)?.equipment ?? "").lowercased()
        let weighted = ["barbell", "dumbbell", "kettlebell", "machine", "cable", "plate", "ez bar", "smith", "weight"]
        return weighted.contains(where: equipment.contains) ? .weightReps : .reps
    }
}

struct LoggedSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var weightKg: Double? = nil
    var reps: Int? = nil
    var seconds: Int? = nil
    var done = false
    var completedAt: Date? = nil
}

struct LoggedExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    let name: String
    let tracking: ExerciseTracking
    var restSeconds: Int
    /// What the workout asked for, e.g. "3 × 10".
    var target: String
    var sets: [LoggedSet]

    var doneSets: [LoggedSet] { sets.filter(\.done) }
    /// Weight × reps over the done sets, in kg.
    var volumeKg: Double { doneSets.reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) } }
}

struct PersonalRecord: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case heaviest, oneRepMax, reps, time }
    var id = UUID()
    let exercise: String
    let kind: Kind
    let value: Double
    let date: Date

    /// "Heaviest: 62.5 kg", "Most reps: 15", in the person's weight unit.
    func text(unit: WeightUnit) -> String {
        switch kind {
        case .heaviest:  return "Heaviest \(TrainingFormat.weight(value, unit))"
        case .oneRepMax: return "Best estimated 1-rep max \(TrainingFormat.weight(value, unit))"
        case .reps:      return "Most reps: \(Int(value))"
        case .time:      return "Longest: \(TrainingFormat.duration(Int(value)))"
        }
    }
}

struct LoggedWorkout: Codable, Hashable, Identifiable {
    var id = UUID()
    let title: String
    let kind: ExerciseKind
    let startedAt: Date
    var finishedAt: Date
    var exercises: [LoggedExercise]
    var records: [PersonalRecord] = []

    var setsDone: Int { exercises.reduce(0) { $0 + $1.doneSets.count } }
    var volumeKg: Double { exercises.reduce(0) { $0 + $1.volumeKg } }
    var duration: TimeInterval { max(0, finishedAt.timeIntervalSince(startedAt)) }
}

/// The best an exercise has reached.
struct ExerciseBests: Equatable {
    var heaviest: Double?
    var oneRepMax: Double?
    var reps: Int?
    var seconds: Int?
}

enum TrainingFormat {
    static func weight(_ kg: Double, _ unit: WeightUnit) -> String {
        let value = unit == .kg ? kg : kg / WeightUnit.kgPerPound
        let text = value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(text) \(unit.suffix)"
    }

    static func duration(_ seconds: Int) -> String {
        seconds >= 60 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "\(seconds) s"
    }

    /// One set as text: "60 kg × 8", "12 reps", "0:45".
    static func set(_ set: LoggedSet, tracking: ExerciseTracking, unit: WeightUnit) -> String {
        switch tracking {
        case .weightReps: return "\(weight(set.weightKg ?? 0, unit)) × \(set.reps ?? 0)"
        case .reps:       return "\(set.reps ?? 0) reps"
        case .time:       return duration(set.seconds ?? 0)
        }
    }
}

@MainActor
@Observable
final class TrainingLogStore {
    static let shared = TrainingLogStore()

    /// Finished workouts, newest first.
    private(set) var workouts: [LoggedWorkout] = []

    @ObservationIgnored private let defaults: UserDefaults
    private let key = "trainingLog_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        workouts = ResilientStorage.loadArray(LoggedWorkout.self, key: key, defaults: defaults)
            .sorted { $0.finishedAt > $1.finishedAt }
    }

    /// Saves a finished workout with the records it set, and returns it.
    @discardableResult
    func save(_ workout: LoggedWorkout) -> LoggedWorkout {
        var finished = workout
        finished.records = records(in: workout)
        workouts.insert(finished, at: 0)
        persist()
        return finished
    }

    /// Re-reads storage (after Delete All Data, so nothing erased can be shown or saved back).
    func reload() {
        workouts = ResilientStorage.loadArray(LoggedWorkout.self, key: key, defaults: defaults)
            .sorted { $0.finishedAt > $1.finishedAt }
    }

    func remove(_ workout: LoggedWorkout) {
        workouts.removeAll { $0.id == workout.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(workouts) { defaults.set(data, forKey: key) }
    }

    // MARK: Reading

    static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Every logged appearance of an exercise, newest first, with its workout's date.
    func history(of name: String) -> [(date: Date, exercise: LoggedExercise)] {
        let wanted = Self.key(name)
        return workouts.flatMap { w in
            w.exercises.filter { Self.key($0.name) == wanted && !$0.doneSets.isEmpty }.map { (w.finishedAt, $0) }
        }
    }

    /// The done sets from the last time this exercise was logged, to start from.
    func lastSets(of name: String) -> [LoggedSet] { history(of: name).first?.exercise.doneSets ?? [] }

    /// The best ever reached, from workouts finished before `date` (all of them when nil).
    func bests(of name: String, before date: Date? = nil) -> ExerciseBests {
        let sets = history(of: name).filter { date == nil || $0.date < date! }.flatMap(\.exercise.doneSets)
        return Self.bests(of: sets)
    }

    static func bests(of sets: [LoggedSet]) -> ExerciseBests {
        var b = ExerciseBests()
        for s in sets {
            if let w = s.weightKg, w > 0 {
                b.heaviest = max(b.heaviest ?? 0, w)
                if let r = s.reps, let e = oneRepMax(weightKg: w, reps: r) { b.oneRepMax = max(b.oneRepMax ?? 0, e) }
            }
            if let r = s.reps, r > 0 { b.reps = max(b.reps ?? 0, r) }
            if let sec = s.seconds, sec > 0 { b.seconds = max(b.seconds ?? 0, sec) }
        }
        return b
    }

    /// Epley's estimate, only trusted up to 12 reps.
    static func oneRepMax(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, (1...12).contains(reps) else { return nil }
        return reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }

    /// The records a workout sets against everything logged before it. An exercise
    /// done for the first time sets none: there's nothing to beat yet.
    func records(in workout: LoggedWorkout) -> [PersonalRecord] {
        var found: [PersonalRecord] = []
        for exercise in workout.exercises where !exercise.doneSets.isEmpty {
            guard !history(of: exercise.name).filter({ $0.date < workout.startedAt }).isEmpty else { continue }
            let before = bests(of: exercise.name, before: workout.startedAt)
            let now = Self.bests(of: exercise.doneSets)
            found += Self.beaten(before: before, now: now, tracking: exercise.tracking)
                .map { PersonalRecord(exercise: exercise.name, kind: $0.0, value: $0.1, date: workout.finishedAt) }
        }
        return found
    }

    /// Whether one set beats the history (shown with a "PR" mark as it's done).
    func isRecord(_ set: LoggedSet, exercise name: String, tracking: ExerciseTracking) -> Bool {
        guard !history(of: name).isEmpty else { return false }
        return !Self.beaten(before: bests(of: name), now: Self.bests(of: [set]), tracking: tracking).isEmpty
    }

    private static func beaten(before: ExerciseBests, now: ExerciseBests, tracking: ExerciseTracking) -> [(PersonalRecord.Kind, Double)] {
        var out: [(PersonalRecord.Kind, Double)] = []
        switch tracking {
        case .weightReps:
            if let n = now.heaviest, n > (before.heaviest ?? 0) + 0.001 { out.append((.heaviest, n)) }
            if let n = now.oneRepMax, n > (before.oneRepMax ?? 0) + 0.05 { out.append((.oneRepMax, n)) }
        case .reps:
            if let n = now.reps, n > before.reps ?? 0 { out.append((.reps, Double(n))) }
        case .time:
            if let n = now.seconds, n > before.seconds ?? 0 { out.append((.time, Double(n))) }
        }
        return out
    }
}
