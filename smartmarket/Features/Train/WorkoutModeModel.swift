import Foundation
import UserNotifications
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
    /// Set once the workout was finished or discarded here, or found ended outside.
    @ObservationIgnored private(set) var isClosed = false
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
            // Saved at once, so the start time survives the app closing before the first set.
            saveDraft()
        }
    }

    /// Whether this follows the shared live session (false in tests).
    var tracksSession: Bool { session != nil }

    /// An exercise ready to log: its sets, filled from last time where there is one.
    static func prepare(_ step: WorkoutExercise, log: TrainingLogStore) -> LoggedExercise {
        let tracking = ExerciseTracking.guess(for: step)
        let last = log.lastSets(of: step.name)
        let parsed = Self.prescription(step)
        let count = max(parsed.sets, 1)
        let targetReps = Int(parsed.each.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "") ?? 10
        let targetSeconds = Self.seconds(in: step)
        let sets = (0..<count).map { i -> LoggedSet in
            let previous = last.indices.contains(i) ? last[i] : last.last
            switch tracking {
            // A weight set in the builder wins; otherwise start from last time.
            case .weightReps:
                if let planned = step.weightKg, planned > 0 { return LoggedSet(weightKg: planned, reps: targetReps) }
                return LoggedSet(weightKg: previous?.weightKg ?? 0, reps: previous?.reps ?? targetReps)
            case .reps:       return LoggedSet(reps: previous?.reps ?? targetReps)
            case .time:       return LoggedSet(seconds: targetSeconds)
            }
        }
        return LoggedExercise(name: step.name, tracking: tracking, restSeconds: max(step.restSeconds, 0),
                              target: step.prescription, sets: sets)
    }

    /// Sets and what each set is: a step with `sets: 0` and reps "2 × 30 sec each side"
    /// (how mobility stretches are written) is 2 sets of "30 sec each side".
    static func prescription(_ step: WorkoutExercise) -> (sets: Int, each: String) {
        let text = step.reps.trimmingCharacters(in: .whitespaces)
        if let m = text.range(of: #"^\d+\s*[×xX]\s*"#, options: .regularExpression) {
            let n = Int(text[m].filter(\.isNumber)) ?? 1
            let rest = String(text[m.upperBound...])
            if step.sets <= 1 { return (n, rest) }
            return (step.sets, rest)
        }
        return (max(step.sets, 1), text)
    }

    /// One set's time: "30 sec" → 30, "2 min" → 120. A timed block's minutes are shared
    /// by its sets (3 interval rounds in a 9-minute block are 3 minutes each).
    static func seconds(in step: WorkoutExercise) -> Int {
        let parsed = prescription(step)
        if step.minutes > 0 { return step.minutes * 60 / max(parsed.sets, 1) }
        let text = parsed.each.lowercased()
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
    /// Reps and seconds are 1 at least: a set of nothing isn't a set.
    func setReps(_ reps: Int, set: Int) { carry(from: set, \.reps, min(max(reps, 1), 999)) }
    func setSeconds(_ seconds: Int, set: Int) {
        // A paused timer starts again from the new time.
        if set == currentSetIndex, timerPausedLeft != nil { timerPausedLeft = nil }
        carry(from: set, \.seconds, min(max(seconds, 1), 6 * 3600))
    }

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

    // Adding, removing or reopening a set can change which set is current, so a
    // running or paused timer is stopped first: it must never complete another set.

    func addSet() {
        guard var ex = current else { return }
        stopTimer()
        var copy = ex.sets.last ?? LoggedSet()
        copy.id = UUID(); copy.done = false; copy.completedAt = nil
        // A timed set stopped early: the new one gets what was asked for, not the time done.
        if let target = copy.targetSeconds { copy.seconds = target }
        copy.targetSeconds = nil
        ex.sets.append(copy)
        exercises[exerciseIndex] = ex
        saveDraft()
    }

    func removeSet(_ setIndex: Int) {
        guard var ex = current, ex.sets.count > 1, ex.sets.indices.contains(setIndex) else { return }
        stopTimer()
        ex.sets.remove(at: setIndex)
        exercises[exerciseIndex] = ex
        saveDraft()
    }

    /// Opens a done set again to fix its numbers (a timed set goes back to its target).
    func reopen(_ setIndex: Int) {
        stopTimer()
        edit(setIndex) { set in
            set.done = false
            set.completedAt = nil
            if let target = set.targetSeconds { set.seconds = target }
            set.targetSeconds = nil
        }
    }

    // MARK: Moving on

    /// Marks the current set done, then rests, then moves on (to the next exercise after the last set).
    func completeSet(now: Date = Date()) {
        guard let i = currentSetIndex, var ex = current else { return }
        // A timed set stopped early counts the time really done; its target is kept beside it.
        if ex.tracking == .time, let target = ex.sets[i].seconds {
            let left = timerEndsAt.map { Int($0.timeIntervalSince(now).rounded()) } ?? timerPausedLeft
            if let left, left > 0 {
                ex.sets[i].targetSeconds = target
                ex.sets[i].seconds = max(1, target - left)
            }
        }
        stopTimer()
        ex.sets[i].done = true
        ex.sets[i].completedAt = now
        let record = log.isRecord(ex.sets[i], exercise: ex.name, tracking: ex.tracking,
                                  earlier: ex.sets[..<i].filter(\.done))
        exercises[exerciseIndex] = ex
        setCount &+= 1
        if record { recordCount &+= 1 }
        let exerciseFinished = !ex.sets.contains { !$0.done }
        // On to the next exercise with work left (after this one, else from the top).
        if exerciseFinished, let next = nextUnfinished(after: exerciseIndex) { go(to: next) }
        if !allDone, ex.restSeconds > 0 { startRest(ex.restSeconds, now: now) }
        saveDraft()
    }

    private func nextUnfinished(after index: Int) -> Int? {
        let unfinished = exercises.indices.filter { exercises[$0].sets.contains { !$0.done } }
        return unfinished.first { $0 > index } ?? unfinished.first
    }

    /// Whether a done set beat the history and the sets done before it today (for the
    /// "PR" mark): one mark per new best, not one on every set above the old best.
    func isRecord(_ set: LoggedSet, in exercise: LoggedExercise) -> Bool {
        guard set.done else { return false }
        let position = exercise.sets.firstIndex { $0.id == set.id } ?? 0
        return log.isRecord(set, exercise: exercise.name, tracking: exercise.tracking,
                            earlier: exercise.sets[..<position].filter(\.done))
    }

    func go(to index: Int) {
        guard exercises.indices.contains(index) else { return }
        stopTimer()
        exerciseIndex = index
        session?.syncStep(to: index)
        saveDraft()
    }

    // MARK: Following the session

    /// The Live Activity's Next moved the session on: show that exercise (the session
    /// already has it, so nothing is sent back).
    func follow(sessionIndex index: Int) {
        guard session != nil, !isClosed, result == nil, index != exerciseIndex else { return }
        go(to: index)
    }

    /// The session ended outside workout mode (the Live Activity's Finish, or another
    /// workout started). Shows the summary of what the session saved; returns false
    /// when nothing was logged, so the screen can close.
    @discardableResult
    func sessionEndedOutside() -> Bool {
        guard session != nil, !isClosed else { return result != nil }
        isClosed = true
        restTask?.cancel(); stopTimer(); restEndsAt = nil; Self.cancelRestNotice()
        // Already saved by the session from the draft: shown, not saved again.
        result = log.saved(title: workout.title, startedAt: startedAt)
        return result != nil
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
        if session != nil { Self.cancelRestNotice() }
    }

    static let restNoticeID = "workout_rest_end"
    /// The end of a timed set, for a locked phone. On screen the timer itself shows it,
    /// so it is silenced in the foreground like the rest notice.
    static let timerNoticeID = "workout_timer_end"
    /// The end each asked-for notice waits for, so one cancelled meanwhile isn't added late.
    private static var noticeEnds: [String: Date] = [:]

    /// The rest's end also as a notification, for a locked phone between sets.
    private static func scheduleRestNotice(at end: Date) {
        scheduleNotice(id: restNoticeID, title: "Rest's over", body: "Time for your next set.", at: end)
    }

    /// Adds a notice for `end`. Asks for permission the first time one is wanted;
    /// with notifications denied nothing is scheduled.
    private static func scheduleNotice(id: String, title: String, body: String, at end: Date) {
        noticeEnds[id] = end
        Task {
            let center = UNUserNotificationCenter.current()
            var status = await center.notificationSettings().authorizationStatus
            // UI tests are never shown the system's question.
            if status == .notDetermined, !NourloTips.isUITesting() {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                status = await center.notificationSettings().authorizationStatus
            }
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
            let wait = end.timeIntervalSinceNow
            guard noticeEnds[id] == end, wait >= 1 else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: id, content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false))
            try? await center.add(request)
        }
    }

    private static func cancelNotice(id: String) {
        noticeEnds[id] = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    static func cancelRestNotice() { cancelNotice(id: restNoticeID) }
    static func cancelTimerNotice() { cancelNotice(id: timerNoticeID) }

    private func scheduleRestEnd() {
        restTask?.cancel()
        if session != nil { Self.cancelRestNotice() }
        guard let end = restEndsAt else { return }
        if session != nil { Self.scheduleRestNotice(at: end) }
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
        if session != nil {
            Self.scheduleNotice(id: Self.timerNoticeID, title: "Time's up", body: "That set is done.", at: end)
        }
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, self.timerEndsAt == end else { return }
            self.timerEndsAt = nil
            // On a locked phone this runs late, when the app is back: the set still
            // ended at `end`, and its rest counts from then.
            self.completeSet(now: end)
        }
    }

    func pauseTimer(now: Date = Date()) {
        guard let end = timerEndsAt else { return }
        timerTask?.cancel()
        if session != nil { Self.cancelTimerNotice() }
        timerPausedLeft = max(0, Int(end.timeIntervalSince(now).rounded()))
        timerEndsAt = nil
    }

    private func stopTimer() {
        timerTask?.cancel()
        if session != nil, timerEndsAt != nil { Self.cancelTimerNotice() }
        timerEndsAt = nil
        timerPausedLeft = nil
    }

    // MARK: Finish

    /// Saves the sets done (exercises with none are left out), logs the workout, and ends the session.
    func finish(now: Date = Date()) {
        isClosed = true
        restTask?.cancel(); stopTimer(); restEndsAt = nil
        if session != nil { Self.cancelRestNotice() }
        let done = exercises.compactMap { ex -> LoggedExercise? in
            var kept = ex
            kept.sets = ex.doneSets
            return kept.sets.isEmpty ? nil : kept
        }
        let logged = LoggedWorkout(title: workout.title, kind: workout.kind, startedAt: startedAt,
                                   finishedAt: now, exercises: done)
        let saved = log.save(logged)
        result = saved
        // The completed session points at this log, so deleting one deletes the other.
        session?.finish(now: now, logID: saved.id)
        defaults.removeObject(forKey: Self.draftKey)
    }

    /// The sets ticked off in the saved draft for `workout`; nil when it has no draft.
    static func draftSetsDone(for workout: Workout, defaults: UserDefaults = .standard) -> Int? {
        guard let data = defaults.data(forKey: draftKey),
              let draft = try? JSONDecoder().decode(Draft.self, from: data), draft.workoutID == workout.id else { return nil }
        return draft.exercises.reduce(0) { $0 + $1.doneSets.count }
    }

    /// The workout was finished outside workout mode (the Live Activity's Finish): the sets
    /// already done in its draft are saved to Progress, as `finish` would have. Returns what was saved.
    @discardableResult
    static func saveFinishedDraft(for workout: Workout, finishedAt: Date, defaults: UserDefaults = .standard) -> LoggedWorkout? {
        guard let data = defaults.data(forKey: draftKey),
              let draft = try? JSONDecoder().decode(Draft.self, from: data), draft.workoutID == workout.id else { return nil }
        defaults.removeObject(forKey: draftKey)
        let done = draft.exercises.compactMap { ex -> LoggedExercise? in
            var kept = ex
            kept.sets = ex.doneSets
            return kept.sets.isEmpty ? nil : kept
        }
        guard !done.isEmpty else { return nil }
        let log = defaults === UserDefaults.standard ? TrainingLogStore.shared : TrainingLogStore(defaults: defaults)
        return log.save(LoggedWorkout(title: workout.title, kind: workout.kind, startedAt: draft.startedAt, finishedAt: finishedAt, exercises: done))
    }

    /// Leaves without saving anything.
    func discard() {
        isClosed = true
        restTask?.cancel(); stopTimer()
        if session != nil { Self.cancelRestNotice() }
        session?.cancel()
        defaults.removeObject(forKey: Self.draftKey)
    }

    private func saveDraft() {
        let draft = Draft(workoutID: workout.id, exercises: exercises, exerciseIndex: exerciseIndex, startedAt: startedAt)
        if let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: Self.draftKey) }
    }
}
