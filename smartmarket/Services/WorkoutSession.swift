import ActivityKit
import Foundation

/// The workout being done right now: the in-app strip on the workout screen and
/// its Live Activity (lock screen and Dynamic Island) show the same session.
///
/// The session record lives in `WorkoutSessionStore` so the Live Activity's
/// Next / Finish buttons (`LiveActivityIntent`s, run in this process even when
/// the app was in the background) change it the same way the in-app buttons do.
/// Finishing logs the workout through `WorkoutStore.complete`, once per day.
/// With Live Activities turned off, everything but the lock-screen view still works.
@MainActor
@Observable
final class WorkoutSession {
    static let shared = WorkoutSession()

    /// The running (unfinished) session, if any.
    private(set) var state: WorkoutSessionState?
    /// The workout it belongs to.
    private(set) var workout: Workout?
    /// Bumped when a session finishes and is logged (for haptics).
    private(set) var finishCount = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: WorkoutStore
    @ObservationIgnored private let weightKg: @MainActor () -> Double
    @ObservationIgnored private let usesLiveActivities: Bool
    /// Runs after a session finished outside the app's own buttons (the lock
    /// screen's Finish, or found finished at launch) was logged.
    @ObservationIgnored private let onFinishedOutsideApp: @MainActor () -> Void
    @ObservationIgnored nonisolated(unsafe) private var observer: NSObjectProtocol?

    static let workoutKey = "workoutSessionWorkout_v1"

    /// Tests pass their own defaults and store and turn Live Activities off.
    init(defaults: UserDefaults = .standard, store: WorkoutStore? = nil,
         weightKg: (@MainActor () -> Double)? = nil,
         usesLiveActivities: Bool = true,
         onFinishedOutsideApp: (@MainActor () -> Void)? = nil) {
        self.defaults = defaults
        self.store = store ?? .shared
        self.weightKg = weightKg ?? { AppState.shared.userProfile.weight }
        self.usesLiveActivities = usesLiveActivities
        self.onFinishedOutsideApp = onFinishedOutsideApp ?? { HealthService.shared.syncPromptlyInBackground() }
        observer = NotificationCenter.default.addObserver(forName: WorkoutActivityControl.didChange, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncFromStore() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func isRunning(_ workout: Workout) -> Bool { state != nil && self.workout?.id == workout.id }

    /// Whether the system lets this app show Live Activities right now.
    var liveActivitiesEnabled: Bool { usesLiveActivities && ActivityAuthorizationInfo().areActivitiesEnabled }

    // MARK: - Launch

    /// Call once at launch: picks up a session left running (or finished from the
    /// lock screen while the app was closed) and ends Live Activities that no
    /// longer belong to one. A finished workout's "Workout done" card stays until
    /// its own dismissal time.
    func restore(now: Date = Date()) {
        syncFromStore(now: now)
        guard usesLiveActivities else { return }
        let keep = state?.id
        Task { await WorkoutActivityControl.cleanUpAtLaunch(keeping: keep, now: now) }
    }

    // MARK: - Actions

    /// Starts `workout` from its first exercise. Replaces any other session (not logged).
    func start(_ workout: Workout, now: Date = Date()) {
        guard !workout.exercises.isEmpty else { return }
        if let old = state { endActivity(old.id) }
        let steps = workout.exercises.map { WorkoutSessionState.Step(name: $0.name, detail: $0.prescription) }
        let new = WorkoutSessionState(id: UUID().uuidString, title: workout.title, steps: steps, startDate: now)
        state = new
        self.workout = workout
        persist()
        requestActivity(for: new)
    }

    /// Moves to the next exercise (does nothing on the last one).
    func next() {
        guard var s = state, s.advance() else { return }
        state = s
        persist()
        pushActivity(s)
    }

    /// Shows `index` as the current exercise (workout mode moves forwards and back).
    func syncStep(to index: Int) {
        guard var s = state, !s.isFinished, s.steps.indices.contains(index), s.index != index else { return }
        s.index = index
        state = s
        persist()
        pushActivity(s)
    }

    /// Finishes and logs the workout (once per day), and ends the Live Activity.
    /// `logID` is the workout-mode log saved for it, so the two can be deleted together.
    func finish(now: Date = Date(), logID: UUID? = nil) {
        guard var s = state, s.finish(at: now) else { return }
        pushActivity(s)
        complete(s, logID: logID)
    }

    /// Stops without logging anything.
    func cancel() {
        guard let s = state else { return }
        endActivity(s.id)
        clear()
    }

    // MARK: - Internals

    /// Re-reads the stored session (a Live Activity button may have changed it).
    func syncFromStore(now: Date = Date()) {
        guard let saved = WorkoutSessionStore.load(from: defaults),
              let workout = loadWorkout() else {
            clear()
            return
        }
        if saved.isFinished {
            self.workout = workout
            var finished = saved
            if finished.finishedAt == nil { finished.finish(at: now) }
            let end = finished.finishedAt ?? now
            // Finish with nothing done (no set ticked in workout mode, or under a minute
            // without it) is a stop, not a workout: nothing is logged.
            let setsDone = WorkoutModeModel.draftSetsDone(for: workout, defaults: defaults)
            if setsDone == 0 || (setsDone == nil && end.timeIntervalSince(finished.startDate) < 60) {
                if setsDone != nil { defaults.removeObject(forKey: WorkoutModeModel.draftKey) }
                endActivity(finished.id)
                clear()
                return
            }
            // The sets logged in workout mode go to Progress too.
            let logged = WorkoutModeModel.saveFinishedDraft(for: workout, finishedAt: end, defaults: defaults)
            complete(finished, logID: logged?.id)
            // Finished from the lock screen: the app may be about to be suspended again.
            onFinishedOutsideApp()
        } else if saved.isStale(now: now) {
            endActivity(saved.id)
            clear()
        } else {
            state = saved
            self.workout = workout
        }
    }

    /// Logs the finished session with its real start and finish times.
    /// A session stopped early counts its real minutes (see `WorkoutStore.complete`).
    private func complete(_ finished: WorkoutSessionState, logID: UUID? = nil) {
        let end = finished.finishedAt ?? Date()
        if let workout {
            store.complete(workout, weightKg: weightKg(), now: end,
                           tracked: DateInterval(start: finished.startDate, end: max(end, finished.startDate)),
                           logID: logID)
        }
        finishCount &+= 1
        clear()
    }

    private func clear() {
        state = nil
        workout = nil
        WorkoutSessionStore.clear(in: defaults)
        defaults.removeObject(forKey: Self.workoutKey)
    }

    private func persist() {
        guard let state, let workout else { return }
        WorkoutSessionStore.save(state, to: defaults)
        if let data = try? JSONEncoder().encode(workout) { defaults.set(data, forKey: Self.workoutKey) }
    }

    private func loadWorkout() -> Workout? {
        guard let data = defaults.data(forKey: Self.workoutKey) else { return nil }
        return try? JSONDecoder().decode(Workout.self, from: data)
    }

    private func requestActivity(for s: WorkoutSessionState) {
        guard liveActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: s.attributes,
                                     content: ActivityContent(state: s.contentState, staleDate: nil),
                                     pushType: nil)
        } catch {
            // Not allowed or too many activities: the in-app session carries on alone.
        }
    }

    private func pushActivity(_ s: WorkoutSessionState) {
        guard usesLiveActivities else { return }
        Task { await WorkoutActivityControl.push(s) }
    }

    private func endActivity(_ id: String) {
        guard usesLiveActivities else { return }
        Task { await WorkoutActivityControl.end(sessionID: id) }
    }
}
