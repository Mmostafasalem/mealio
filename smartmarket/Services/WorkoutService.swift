import Foundation
import Observation

// MARK: - On-device workout builder
//
// Builds a session from the bundled exercise catalogue. Used whenever online
// AI is off, signed out, out of credits or unreachable, so the Train tab always
// has something useful to offer.

enum WorkoutBuilder {

    static let safetyNote = "Stop if you feel pain, dizziness or chest discomfort. Check with a doctor before starting if you have a medical condition or injury."

    static func build(kind: ExerciseKind, level: ExerciseLevel, minutes: Int,
                      focus: ExerciseFocus, goal: WeightGoal) -> Workout {
        switch kind {
        case .cardio:   return cardio(level: level, minutes: minutes, goal: goal)
        case .mobility: return mobility(level: level, minutes: minutes)
        case .gym, .home: return strength(kind: kind, level: level, minutes: minutes, focus: focus, goal: goal)
        }
    }

    // Strength: pick exercises for the focus, easiest first for beginners,
    // and scale sets with experience and reps with the goal.
    private static func strength(kind: ExerciseKind, level: ExerciseLevel, minutes: Int,
                                 focus: ExerciseFocus, goal: WeightGoal) -> Workout {
        let pool = Exercise.catalog.filter { $0.kind == kind && allowed($0.level, for: level) }
        let wanted: [ExerciseFocus] = focus == .fullBody ? [.lower, .upper, .core, .fullBody] : [focus, .core]
        // Interleave the focus areas so a full-body day alternates muscle groups.
        var buckets = wanted.map { area in pool.filter { $0.focus == area } }
        var ordered: [Exercise] = []
        while buckets.contains(where: { !$0.isEmpty }) {
            for index in buckets.indices where !buckets[index].isEmpty {
                ordered.append(buckets[index].removeFirst())
            }
        }
        let working = max(minutes - 8, 5)                     // minus warm-up and cool-down
        let count = min(max(working / 5, 3), min(ordered.count, 8))
        let sets = [ExerciseLevel.beginner: 2, .intermediate: 3, .advanced: 4][level] ?? 3
        let rest = kind == .gym ? (goal == .gain ? 90 : 60) : 30
        let exercises = ordered.prefix(count).map { exercise in
            WorkoutExercise(name: exercise.name, sets: sets, reps: reps(from: exercise.prescription, goal: goal),
                            minutes: 0, restSeconds: rest, note: exercise.howTo)
        }
        let place = kind == .gym ? "gym" : "home"
        return Workout(
            title: "\(focus.title) \(place) session",
            summary: "\(count) exercises, \(sets) sets each. Pick loads that make the last two reps hard but clean.",
            kind: kind, level: level, durationMinutes: minutes,
            warmup: "5 minutes of easy movement, then one light set of the first exercise.",
            cooldown: "3 minutes of slow breathing and light stretching.",
            exercises: Array(exercises), safetyNote: safetyNote)
    }

    private static func cardio(level: ExerciseLevel, minutes: Int, goal: WeightGoal) -> Workout {
        let warm = max(3, minutes / 6), cool = max(3, minutes / 8)
        let main = max(minutes - warm - cool, 5)
        var blocks = [WorkoutExercise(name: "Easy warm-up", sets: 1, reps: "walk or very easy pace", minutes: warm,
                                      restSeconds: 0, note: "Build up gradually; you should be able to chat.")]
        if level == .beginner {
            blocks.append(WorkoutExercise(name: "Steady effort", sets: 1, reps: "conversational pace", minutes: main,
                                          restSeconds: 0, note: "Walk, jog, cycle or row. Take short breaks whenever you need them."))
        } else {
            let steady = main / 2, rounds = max((main - steady) / 3, 2)
            blocks.append(WorkoutExercise(name: "Steady effort", sets: 1, reps: "conversational pace", minutes: steady,
                                          restSeconds: 0, note: "Run, cycle or row at an effort you could hold for an hour."))
            blocks.append(WorkoutExercise(name: "Intervals", sets: rounds, reps: "1 min hard, 2 min easy", minutes: rounds * 3,
                                          restSeconds: 0, note: "Hard means you could only say a few words. Recover fully in the easy part."))
        }
        blocks.append(WorkoutExercise(name: "Cool-down", sets: 1, reps: "easy walk", minutes: cool, restSeconds: 0,
                                      note: "Let your breathing settle before you stop."))
        return Workout(
            title: level == .beginner ? "Steady cardio" : "Steady cardio with intervals",
            summary: goal == .lose ? "Mostly easy effort, which is what you can repeat often." : "Builds your base, with a short push at the end.",
            kind: .cardio, level: level, durationMinutes: minutes,
            warmup: "Included as the first block.", cooldown: "Included as the last block.",
            exercises: blocks, safetyNote: safetyNote)
    }

    private static func mobility(level: ExerciseLevel, minutes: Int) -> Workout {
        let pool = Exercise.catalog.filter { $0.kind == .mobility }
        let count = min(max(minutes / 4, 4), pool.count)
        let exercises = pool.prefix(count).map { exercise in
            WorkoutExercise(name: exercise.name, sets: 0, reps: exercise.prescription, minutes: 0,
                            restSeconds: 0, note: exercise.howTo)
        }
        return Workout(
            title: "Mobility and stretch",
            summary: "Slow, comfortable ranges. Nothing here should hurt.",
            kind: .mobility, level: level, durationMinutes: minutes,
            warmup: "A minute of easy walking or marching on the spot.",
            cooldown: "Finish lying down with a few slow breaths.",
            exercises: Array(exercises), safetyNote: safetyNote)
    }

    private static func allowed(_ exercise: ExerciseLevel, for person: ExerciseLevel) -> Bool {
        let order: [ExerciseLevel] = [.beginner, .intermediate, .advanced]
        return (order.firstIndex(of: exercise) ?? 0) <= (order.firstIndex(of: person) ?? 0)
    }

    /// Keeps holds and per-side cues; shifts plain rep counts with the goal.
    private static func reps(from prescription: String, goal: WeightGoal) -> String {
        let part = prescription.split(separator: "×").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? prescription
        guard let plain = Int(part) else { return part }
        switch goal {
        case .gain:     return "\(max(plain - 2, 6))"
        case .lose:     return "\(plain + 2)"
        case .maintain: return "\(plain)"
        }
    }
}

// MARK: - Store

/// Saved workouts and completed sessions. UserDefaults, like the rest of the app.
@MainActor
@Observable
final class WorkoutStore {

    static let shared = WorkoutStore()
    private init() { reload() }

    private(set) var saved: [Workout] = []
    private(set) var completed: [CompletedWorkout] = []

    private let savedKey = "savedWorkouts_v1"
    private let completedKey = "completedWorkouts_v1"

    func reload() {
        saved = ResilientStorage.loadArray(Workout.self, key: savedKey)
        completed = ResilientStorage.loadArray(CompletedWorkout.self, key: completedKey)
    }

    func isSaved(_ workout: Workout) -> Bool { saved.contains { $0.id == workout.id } }

    func save(_ workout: Workout) {
        guard !isSaved(workout) else { return }
        saved.insert(workout, at: 0)
        saved = Array(saved.prefix(30))
        persist()
    }

    func remove(_ workout: Workout) {
        saved.removeAll { $0.id == workout.id }
        persist()
    }

    func complete(_ workout: Workout, weightKg: Double) {
        completed.insert(CompletedWorkout(title: workout.title, kind: workout.kind, minutes: workout.durationMinutes,
                                          calories: workout.estimatedCalories(weightKg: weightKg)), at: 0)
        completed = Array(completed.prefix(200))
        persist()
    }

    func removeCompleted(_ session: CompletedWorkout) {
        completed.removeAll { $0.id == session.id }
        persist()
    }

    /// Sessions done in the last seven days, including today.
    var thisWeek: [CompletedWorkout] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return completed.filter { $0.date >= start }
    }

    private func persist() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(saved) { UserDefaults.standard.set(data, forKey: savedKey) }
        if let data = try? encoder.encode(completed) { UserDefaults.standard.set(data, forKey: completedKey) }
    }
}
