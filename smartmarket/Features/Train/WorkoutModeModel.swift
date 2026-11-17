import Foundation
import Observation

/// One workout being done in workout mode: which exercise and set, the numbers
/// typed so far, and the rest and set timers. The draft is saved as it changes,
/// so closing the app mid-workout loses nothing.
@MainActor
@Observable
final class WorkoutModeModel {
    let workout: Workout
    private(set) var exercises: [LoggedExercise]
    private(set) var exerciseIndex = 0
    let startedAt: Date

    /// Rest between sets: when it ends and how long it was.
    private(set) var restEndsAt: Date?
    private(set) var restLength = 0
    /// A timed set running: when it ends; or paused with this much left.
    private(set) var timerEndsAt: Date?
    private(set) var timerPausedLeft: Int?
    /// Set when a workout is finished: the saved result, for the summary.
    private(set) var result: LoggedWorkout?
    /// Bumped when a set is done, a rest ends or a record is set (haptics).
    private(set) var setCount = 0
    private(set) var restDoneCount = 0
    private(set) var recordCount = 0

    @ObservationIgnored private let log: TrainingLogStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: WorkoutSession?
    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    static let draftKey = "workoutModeDraft_v1"

    private struct Draft: Codable {
        let workoutID: UUID
        let exercises: [LoggedExercise]
        let exerciseIndex: Int
        let startedAt: Date
    }

    /// `tracksSession` false keeps the shared live session (Live Activity, Health) out of it, for tests.
    init(workout: Workout, log: TrainingLogStore? = nil, defaults: UserDefaults = .standard,
         tracksSession: Bool = true, now: Date = Date()) {
        let log = log ?? .shared
        self.workout = workout
        self.log = log
        self.defaults = defaults
        self.session = tracksSession ? .shared : nil
        if let data = defaults.data(forKey: Self.draftKey),
           let draft = try? JSONDecoder().decode(Draft.self, from: data), draft.workoutID == workout.id {
            exercises = draft.exercises
            exerciseIndex = min(draft.exerciseIndex, max(draft.exercises.count - 1, 0))
            startedAt = draft.startedAt
        } else {
            exercises = workout.exercises.map { Self.prepare($0, log: log) }
            startedAt = now
        }
    }

    /// An exercise ready to log: its sets, filled from last time where there is one.
    static func prepare(_ step: WorkoutExercise, log: TrainingLogStore) -> LoggedExercise {
        let tracking = ExerciseTracking.guess(for: step)
        let last = log.lastSets(of: step.name)
        let count = max(step.sets, 1)
        let targetReps = Int(step.reps.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "") ?? 10
        let targetSeconds = Self.seconds(in: step)
        let sets = (0..<count).map { i -> LoggedSet in
            let previous = last.indices.contains(i) ? last[i] : last.last
            switch tracking {
            case .weightReps: return LoggedSet(weightKg: previous?.weightKg ?? step.weightKg ?? 0, reps: previous?.reps ?? targetReps)
            case .reps:       return LoggedSet(reps: previous?.reps ?? targetReps)
            case .time:       return LoggedSet(seconds: targetSeconds)
            }
        }
        return LoggedExercise(name: step.name, tracking: tracking, restSeconds: max(step.restSeconds, 0),
                              target: step.prescription, sets: sets)
    }

    /// "30 sec" → 30, "2 min" → 120, a 12-minute block → 720.
    static func seconds(in step: WorkoutExercise) -> Int {
        if step.minutes > 0 { return step.minutes * 60 }
        let text = step.reps.lowercased()
        let number = Int(text.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "") ?? 30
        return text.contains("min") ? number * 60 : number
    }

    // MARK: Where we are

    var current: LoggedExercise? { exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil }
    /// The first set of this exercise not done yet.
    var currentSetIndex: Int? { current?.sets.firstIndex { !$0.done } }
    var isLastExercise: Bool { exerciseIndex >= exercises.count - 1 }
    var allDone: Bool { exercises.allSatisfy { $0.sets.allSatisfy(\.done) } }
    var setsDone: Int { exercises.reduce(0) { $0 + $1.doneSets.count } }
    var setsTotal: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    // MARK: Editing numbers

    /// A typed number also fills the sets below it that aren't done and still had the old number.
    func setWeight(_ kg: Double, set: Int) {
        carry(from: set, \.weightKg, min(max(kg, 0), 1000))
    }
    func setReps(_ reps: Int, set: Int) { carry(from: set, \.reps, min(max(reps, 0), 999)) }
    func setSeconds(_ seconds: Int, set: Int) { carry(from: set, \.seconds, min(max(seconds, 0), 6 * 3600)) }

    private func carry<T: Equatable>(from setIndex: Int, _ field: WritableKeyPath<LoggedSet, T?>, _ value: T) {
        guard exercises.indices.contains(exerciseIndex), exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        let old = exercises[exerciseIndex].sets[setIndex][keyPath: field]
        exercises[exerciseIndex].sets[setIndex][keyPath: field] = value
        for i in exercises[exerciseIndex].sets.indices where i > setIndex {
            let later = exercises[exerciseIndex].sets[i]
            guard !later.done, later[keyPath: field] == old else { continue }
            exercises[exerciseIndex].sets[i][keyPath: field] = value
        }
        saveDraft()
    }

    private func edit(_ setIndex: Int, _ change: (inout LoggedSet) -> Void) {
        guard exercises.indices.contains(exerciseIndex), exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        change(&exercises[exerciseIndex].sets[setIndex])
        saveDraft()
    }

    func addSet() {
        guard var ex = current else { return }
        var copy = ex.sets.last ?? LoggedSet()
        copy.id = UUID(); copy.done = false; copy.completedAt = nil
        ex.sets.append(copy)
        exercises[exerciseIndex] = ex
        saveDraft()
    }

    func removeSet(_ setIndex: Int) {
        guard var ex = current, ex.sets.count > 1, ex.sets.indices.contains(setIndex) else { return }
        ex.sets.remove(at: setIndex)
        exercises[exerciseIndex] = ex
        saveDraft()
    }

    /// Opens a done set again to fix its numbers.
    func reopen(_ setIndex: Int) { edit(setIndex) { $0.done = false; $0.completedAt = nil } }

    // MARK: Moving on

    /// Marks the current set done, then rests, then moves on (to the next exercise after the last set).
    func completeSet(now: Date = Date()) {
        guard let i = currentSetIndex, var ex = current else { return }
        stopTimer()
        ex.sets[i].done = true
        ex.sets[i].completedAt = now
        let record = log.isRecord(ex.sets[i], exercise: ex.name, tracking: ex.tracking)
        exercises[exerciseIndex] = ex
        setCount &+= 1
        if record { recordCount &+= 1 }
        let exerciseFinished = !ex.sets.contains { !$0.done }
        if exerciseFinished && !isLastExercise { go(to: exerciseIndex + 1) }
        if !allDone, ex.restSeconds > 0 { startRest(ex.restSeconds, now: now) }
        saveDraft()
    }

    /// Whether a done set beat the history (for the "PR" mark).
    func isRecord(_ set: LoggedSet, in exercise: LoggedExercise) -> Bool {
        set.done && log.isRecord(set, exercise: exercise.name, tracking: exercise.tracking)
    }

    func go(to index: Int) {
        guard exercises.indices.contains(index) else { return }
        stopTimer()
        exerciseIndex = index
        session?.syncStep(to: index)
        saveDraft()
    }

    // MARK: Rest

    func startRest(_ seconds: Int, now: Date = Date()) {
        restLength = seconds
        restEndsAt = now.addingTimeInterval(TimeInterval(seconds))
        scheduleRestEnd()
    }

    func addRest(_ seconds: Int) {
        guard let end = restEndsAt else { return }
        restEndsAt = end.addingTimeInterval(TimeInterval(seconds))
        restLength += seconds
        scheduleRestEnd()
    }

    func skipRest() {
        restTask?.cancel()
        restEndsAt = nil
    }

    private func scheduleRestEnd() {
        restTask?.cancel()
        guard let end = restEndsAt else { return }
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, self.restEndsAt == end else { return }
            self.restEndsAt = nil
            self.restDoneCount &+= 1
        }
    }

    // MARK: Timed sets

    var timerRunning: Bool { timerEndsAt != nil }

    func startTimer(now: Date = Date()) {
        guard let i = currentSetIndex, let ex = current, ex.tracking == .time else { return }
        let length = timerPausedLeft ?? ex.sets[i].seconds ?? 30
        timerPausedLeft = nil
        let end = now.addingTimeInterval(TimeInterval(length))
        timerEndsAt = end
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, self.timerEndsAt == end else { return }
            self.timerEndsAt = nil
            self.completeSet()
        }
    }

    func pauseTimer(now: Date = Date()) {
        guard let end = timerEndsAt else { return }
        timerTask?.cancel()
        timerPausedLeft = max(0, Int(end.timeIntervalSince(now).rounded()))
        timerEndsAt = nil
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerEndsAt = nil
        timerPausedLeft = nil
    }

    // MARK: Finish

    /// Saves the sets done (exercises with none are left out), logs the workout, and ends the session.
    func finish(now: Date = Date()) {
        restTask?.cancel(); stopTimer(); restEndsAt = nil
        let done = exercises.compactMap { ex -> LoggedExercise? in
            var kept = ex
            kept.sets = ex.doneSets
            return kept.sets.isEmpty ? nil : kept
        }
        let logged = LoggedWorkout(title: workout.title, kind: workout.kind, startedAt: startedAt,
                                   finishedAt: now, exercises: done)
        result = log.save(logged)
        session?.finish(now: now)
        defaults.removeObject(forKey: Self.draftKey)
    }

    /// Leaves without saving anything.
    func discard() {
        restTask?.cancel(); stopTimer()
        session?.cancel()
        defaults.removeObject(forKey: Self.draftKey)
    }

    private func saveDraft() {
        let draft = Draft(workoutID: workout.id, exercises: exercises, exerciseIndex: exerciseIndex, startedAt: startedAt)
        if let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: Self.draftKey) }
    }
}
