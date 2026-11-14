import Foundation
import Observation

// MARK: - On-device workout builder
//
// Builds a session from the bundled exercise catalogue. Used whenever online
// AI is off, signed out, out of credits or unreachable, so the Train tab always
// has something useful to offer.

enum WorkoutBuilder {

    static let safetyNote = "Stop if you feel pain, dizziness or chest discomfort. Check with a doctor before starting if you have a medical condition or injury."

    /// Builds a session. The choice of exercises is shuffled by a seed taken from the
    /// day and the request, so it changes from day to day but asking twice on the same
    /// day gives the same session. Pass `seed` (tests) to fix it outright.
    static func build(kind: ExerciseKind, level: ExerciseLevel, minutes: Int,
                      focus: ExerciseFocus, goal: WeightGoal,
                      date: Date = Date(), seed: UInt64? = nil) -> Workout {
        var rng = SeededGenerator(seed: seed ?? daySeed(date: date, kind: kind, level: level, minutes: minutes, focus: focus))
        switch kind {
        case .cardio:   return cardio(level: level, minutes: minutes, goal: goal, rng: &rng)
        case .mobility: return mobility(level: level, minutes: minutes, rng: &rng)
        case .gym, .home: return strength(kind: kind, level: level, minutes: minutes, focus: focus, goal: goal, rng: &rng)
        }
    }

    /// What a home session may use: no special kit (see `Exercise.needsNoKit`).
    static func pool(kind: ExerciseKind, level: ExerciseLevel) -> [Exercise] {
        Exercise.catalog.filter { $0.kind == kind && allowed($0.level, for: level) && (kind != .home || $0.needsNoKit) }
    }

    // Strength: exercises for the focus at the chosen level (topped up from the level
    // below, never above), one per movement family where possible, sets scaled with
    // experience and reps with the goal.
    private static func strength(kind: ExerciseKind, level: ExerciseLevel, minutes: Int,
                                 focus: ExerciseFocus, goal: WeightGoal, rng: inout SeededGenerator) -> Workout {
        let available = pool(kind: kind, level: level)
        // The order areas take turns in; a full-body day alternates muscle groups.
        let pattern: [ExerciseFocus]
        switch focus {
        case .fullBody: pattern = [.lower, .upper, .core, .fullBody]
        case .upper:    pattern = [.upper, .upper, .core]
        case .lower:    pattern = [.lower, .lower, .core]
        case .core:     pattern = [.core]
        }
        var areas: [ExerciseFocus] = []
        for area in pattern where !areas.contains(area) { areas.append(area) }
        var queues: [ExerciseFocus: [Exercise]] = [:]
        for area in areas { queues[area] = ranked(available.filter { $0.focus == area }, for: level, rng: &rng) }

        let total = areas.reduce(0) { $0 + (queues[$1]?.count ?? 0) }
        let working = max(minutes - 8, 5)                     // minus warm-up and cool-down
        let count = min(max(working / 5, 3), min(total, 8))
        var picked: [Exercise] = []
        var usedFamilies: Set<String> = []
        func take(_ area: ExerciseFocus, newFamily: Bool) -> Exercise? {
            guard let queue = queues[area],
                  let index = queue.firstIndex(where: { !newFamily || !usedFamilies.contains($0.family) }) else { return nil }
            queues[area]?.remove(at: index)
            return queue[index]
        }
        func takeFirst(_ order: [ExerciseFocus], newFamily: Bool) -> Exercise? {
            for area in order { if let found = take(area, newFamily: newFamily) { return found } }
            return nil
        }
        var slot = 0
        while picked.count < count {
            let area = pattern[slot % pattern.count]
            slot += 1
            let others = areas.filter { $0 != area }
            // A new movement in this area, else in another wanted area, else a repeat movement.
            guard let next = takeFirst([area] + others, newFamily: true)
                    ?? takeFirst([area] + others, newFamily: false) else { break }
            picked.append(next)
            usedFamilies.insert(next.family)
        }

        let sets = [ExerciseLevel.beginner: 2, .intermediate: 3, .advanced: 4][level] ?? 3
        let rest = kind == .gym ? (goal == .gain ? 90 : 60) : 30
        let exercises = picked.map { exercise in
            WorkoutExercise(name: exercise.name, sets: sets, reps: reps(from: exercise.prescription, goal: goal),
                            minutes: 0, restSeconds: rest, note: exercise.howTo)
        }
        let place = kind == .gym ? "gym" : "home"
        return Workout(
            title: "\(focus.title) \(place) session",
            summary: "\(exercises.count) exercises, \(sets) sets each. Pick loads that make the last two reps hard but clean.",
            kind: kind, level: level, durationMinutes: minutes,
            warmup: "5 minutes of easy movement, then one light set of the first exercise.",
            cooldown: "3 minutes of slow breathing and light stretching.",
            exercises: exercises, safetyNote: safetyNote)
    }

    private static func cardio(level: ExerciseLevel, minutes: Int, goal: WeightGoal, rng: inout SeededGenerator) -> Workout {
        let warm = max(3, minutes / 6), cool = max(3, minutes / 8)
        let main = max(minutes - warm - cool, 5)
        let cardioPool = pool(kind: .cardio, level: level)
        // Steady work: something you can keep going for a while ("30 min", not "4 × 30 sec").
        let steadyChoices = cardioPool.filter { exercise in
            !exercise.prescription.contains("×")
                && (Int(exercise.prescription.replacingOccurrences(of: " min", with: "")) ?? 0) >= 10
        }
        let steady = steadyChoices.shuffled(using: &rng).first
        func steadyBlock(_ minutes: Int, note: String) -> WorkoutExercise {
            WorkoutExercise(name: steady?.name ?? "Steady effort", sets: 1, reps: "conversational pace", minutes: minutes,
                            restSeconds: 0, note: steady.map { $0.howTo + " " + note } ?? note)
        }
        var blocks = [WorkoutExercise(name: "Easy warm-up", sets: 1, reps: "walk or very easy pace", minutes: warm,
                                      restSeconds: 0, note: "Build up gradually; you should be able to chat.")]
        if level == .beginner {
            blocks.append(steadyBlock(main, note: "Take short breaks whenever you need them."))
        } else {
            let steadyMinutes = main / 2, rounds = max((main - steadyMinutes) / 3, 2)
            blocks.append(steadyBlock(steadyMinutes, note: "Keep an effort you could hold for an hour."))
            // Intervals: a short, hard drill at the chosen level (or the one below).
            let drills = ranked(cardioPool.filter { $0.prescription.contains("×") }, for: level, rng: &rng)
            let drill = drills.first
            let cue = "Hard means you could only say a few words. Recover fully in the easy part."
            blocks.append(WorkoutExercise(name: drill.map { "\($0.name) intervals" } ?? "Intervals", sets: rounds,
                                          reps: "1 min hard, 2 min easy", minutes: rounds * 3, restSeconds: 0,
                                          note: drill.map { $0.howTo + " " + cue } ?? cue))
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

    private static func mobility(level: ExerciseLevel, minutes: Int, rng: inout SeededGenerator) -> Workout {
        let candidates = ranked(pool(kind: .mobility, level: level), for: level, rng: &rng)
        let count = min(max(minutes / 4, 4), candidates.count)
        // One of each kind of stretch first, then repeats only if the session is long.
        var picked: [Exercise] = []
        var families: Set<String> = []
        for exercise in candidates where picked.count < count && !families.contains(exercise.family) {
            picked.append(exercise); families.insert(exercise.family)
        }
        for exercise in candidates where picked.count < count && !picked.contains(exercise) { picked.append(exercise) }
        let exercises = picked.map { exercise in
            WorkoutExercise(name: exercise.name, sets: 0, reps: exercise.prescription, minutes: 0,
                            restSeconds: 0, note: exercise.howTo)
        }
        return Workout(
            title: "Mobility and stretch",
            summary: "Slow, comfortable ranges. Nothing here should hurt.",
            kind: .mobility, level: level, durationMinutes: minutes,
            warmup: "A minute of easy walking or marching on the spot.",
            cooldown: "Finish lying down with a few slow breaths.",
            exercises: exercises, safetyNote: safetyNote)
    }

    // MARK: Choosing

    private static let levels: [ExerciseLevel] = [.beginner, .intermediate, .advanced]

    private static func allowed(_ exercise: ExerciseLevel, for person: ExerciseLevel) -> Bool {
        (levels.firstIndex(of: exercise) ?? 0) <= (levels.firstIndex(of: person) ?? 0)
    }

    /// The person's own level first, then each level below it; shuffled within a level.
    private static func ranked(_ exercises: [Exercise], for level: ExerciseLevel, rng: inout SeededGenerator) -> [Exercise] {
        let top = levels.firstIndex(of: level) ?? 0
        var result: [Exercise] = []
        for index in stride(from: top, through: 0, by: -1) {
            result += exercises.filter { $0.level == levels[index] }.shuffled(using: &rng)
        }
        return result
    }

    /// Same day and same request give the same number; a new day gives a new one.
    static func daySeed(date: Date, kind: ExerciseKind, level: ExerciseLevel, minutes: Int, focus: ExerciseFocus,
                        calendar: Calendar = .current) -> UInt64 {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let key = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)|\(kind.rawValue)|\(level.rawValue)|\(minutes)|\(focus.rawValue)"
        // FNV-1a: stable across launches, unlike `Hasher`.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    /// Adjusts plain rep counts for the goal. Heavy low-rep work (8 or fewer) stays as
    /// it is; moderate sets (9–15) go a little heavier for gaining and a little longer
    /// for losing; high-rep, timed and per-side prescriptions are kept intact.
    static func reps(from prescription: String, goal: WeightGoal) -> String {
        let part = prescription.split(separator: "×").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? prescription
        guard let plain = Int(part), (9...15).contains(plain) else { return part }
        switch goal {
        case .gain:     return "\(max(plain - 2, 8))"
        case .lose:     return "\(min(plain + 2, 15))"
        case .maintain: return "\(plain)"
        }
    }
}

/// A small, fast, repeatable random number generator (SplitMix64), so a given
/// seed always shuffles the catalogue the same way.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Store

/// Saved workouts and completed sessions. UserDefaults, like the rest of the app.
@MainActor
@Observable
final class WorkoutStore {

    static let shared = WorkoutStore()
    private let defaults: UserDefaults

    /// `defaults` is for tests; the app uses the shared store.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    private(set) var saved: [Workout] = []
    private(set) var completed: [CompletedWorkout] = []

    private let savedKey = "savedWorkouts_v1"
    private let completedKey = "completedWorkouts_v1"

    func reload() {
        saved = ResilientStorage.loadArray(Workout.self, key: savedKey, defaults: defaults)
        completed = ResilientStorage.loadArray(CompletedWorkout.self, key: completedKey, defaults: defaults)
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

    /// True when this session was already marked as done today: the same workout, or an
    /// identical one built again (same kind, level, length, title and exercises in order).
    func isCompletedToday(_ workout: Workout, now: Date = Date()) -> Bool {
        let key = workout.contentKey
        return completed.contains { session in
            Calendar.current.isDate(session.date, inSameDayAs: now)
                && (session.workoutID == workout.id || session.contentKey == key)
        }
    }

    /// Logs the session once per day: marking the same session again the same day does
    /// nothing, even if it was generated again. Returns whether a session was added.
    @discardableResult
    func complete(_ workout: Workout, weightKg: Double, now: Date = Date()) -> Bool {
        guard !isCompletedToday(workout, now: now) else { return false }
        completed.insert(CompletedWorkout(workoutID: workout.id, contentKey: workout.contentKey,
                                          title: workout.title, kind: workout.kind,
                                          minutes: workout.durationMinutes,
                                          calories: workout.estimatedCalories(weightKg: weightKg), date: now), at: 0)
        completed = Array(completed.prefix(200))
        persist()
        return true
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
        if let data = try? encoder.encode(saved) { defaults.set(data, forKey: savedKey) }
        if let data = try? encoder.encode(completed) { defaults.set(data, forKey: completedKey) }
    }
}
