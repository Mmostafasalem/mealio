import ActivityKit
import AppIntents
import Foundation

// MARK: - Workout Live Activity: shared types
//
// The app (`WorkoutSession`) starts the activity; the widget extension draws it
// on the lock screen and in the Dynamic Island. The Next and Finish buttons are
// `LiveActivityIntent`s, which the system runs in the app's process (they're
// compiled into both targets), so they read and write the same session record
// the app uses and then tell the app through `WorkoutActivityControl.didChange`.

/// What the Live Activity shows. Static: the workout. Changing: where you are in it.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var exerciseName: String
        /// The set/rep text, e.g. "3 × 10" or "12 min".
        var detail: String
        var index: Int
        var total: Int
        var startDate: Date
        var isFinished: Bool
        /// Set once finished, for "Done in 24 min".
        var endDate: Date? = nil

        var isLastStep: Bool { index >= total - 1 }
    }

    var title: String
    /// Ties the activity to one session, so a stale activity's buttons do nothing.
    var sessionID: String
}

/// One workout in progress. Pure value type: the transitions are tested.
nonisolated struct WorkoutSessionState: Codable, Equatable, Sendable {
    struct Step: Codable, Hashable, Sendable {
        var name: String
        var detail: String
    }

    var id: String
    var title: String
    var steps: [Step]
    var index: Int = 0
    var startDate: Date
    var finishedAt: Date? = nil

    var isFinished: Bool { finishedAt != nil }
    var current: Step? { steps.indices.contains(index) ? steps[index] : nil }
    var isLastStep: Bool { index >= steps.count - 1 }
    /// Next is possible until the last exercise, and not after finishing.
    var canAdvance: Bool { !isFinished && index < steps.count - 1 }

    /// Moves to the next exercise. Returns false at the last one or once finished.
    @discardableResult
    mutating func advance() -> Bool {
        guard canAdvance else { return false }
        index += 1
        return true
    }

    /// Finishes the session (at any exercise). Returns false if it already was.
    @discardableResult
    mutating func finish(at date: Date = Date()) -> Bool {
        guard !isFinished else { return false }
        finishedAt = max(date, startDate)
        return true
    }

    /// Older than this, a session left running is dropped on launch (not marked done).
    static let maxAge: TimeInterval = 6 * 3600

    func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(startDate) > Self.maxAge }

    var attributes: WorkoutActivityAttributes { WorkoutActivityAttributes(title: title, sessionID: id) }

    var contentState: WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            exerciseName: current?.name ?? title, detail: current?.detail ?? "",
            index: min(index, max(steps.count - 1, 0)), total: steps.count,
            startDate: startDate, isFinished: isFinished, endDate: finishedAt)
    }
}

/// The session record in the app's own defaults (the intents run in the app's process).
nonisolated enum WorkoutSessionStore {
    static let key = "workoutSessionState_v1"

    static func load(from defaults: UserDefaults = .standard) -> WorkoutSessionState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WorkoutSessionState.self, from: data)
    }

    static func save(_ state: WorkoutSessionState, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }

    static func clear(in defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}

/// Applies a Next/Finish command to the stored session and its Live Activity.
nonisolated enum WorkoutActivityControl {
    /// Posted (main thread) after a Live Activity button changed the session.
    static let didChange = Notification.Name("workoutActivityDidChange")

    enum Command: String, Sendable { case next, finish }

    /// How long a finished workout stays on the lock screen.
    static let finishedDismissal: TimeInterval = 10 * 60

    @MainActor
    static func handle(_ command: Command, sessionID: String, defaults: UserDefaults = .standard) async {
        guard var state = WorkoutSessionStore.load(from: defaults), state.id == sessionID, !state.isFinished else {
            // A button on an activity whose session is gone: just take it away.
            await end(sessionID: sessionID)
            return
        }
        let changed: Bool
        switch command {
        case .next: changed = state.advance()
        case .finish: changed = state.finish(at: Date())
        }
        guard changed else { return }
        WorkoutSessionStore.save(state, to: defaults)
        await push(state)
        NotificationCenter.default.post(name: didChange, object: nil, userInfo: ["command": command.rawValue])
    }

    /// Shows `state` on its activity: updates it, or ends it once finished.
    static func push(_ state: WorkoutSessionState) async {
        let content = ActivityContent(state: state.contentState, staleDate: nil)
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.attributes.sessionID == state.id {
            if state.isFinished {
                await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(finishedDismissal)))
            } else {
                await activity.update(content)
            }
        }
    }

    /// Ends the activities for one session at once.
    static func end(sessionID: String) async {
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// What launch clean-up does with one activity.
    enum LaunchCleanup: Equatable {
        case keep
        case endNow
        /// Finished but still showing "Workout done": end it, dismissed at this time.
        case endShowingDone(until: Date)
    }

    /// Pure launch rule: keep the running session's activity and ones already ended
    /// (their dismissal time is set); let a finished one keep its "Workout done"
    /// card until its dismissal time; end stale or unknown ones at once.
    static func launchCleanup(sessionID: String, content: WorkoutActivityAttributes.ContentState,
                              isEnded: Bool, keeping: String?, now: Date) -> LaunchCleanup {
        if sessionID == keeping || isEnded { return .keep }
        if content.isFinished, let endDate = content.endDate {
            let until = endDate.addingTimeInterval(finishedDismissal)
            return until > now ? .endShowingDone(until: until) : .endNow
        }
        return .endNow
    }

    /// Launch clean-up: applies `launchCleanup` to every workout activity.
    static func cleanUpAtLaunch(keeping: String?, now: Date = Date()) async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            let isEnded: Bool
            switch activity.activityState {
            case .ended, .dismissed: isEnded = true
            default: isEnded = false
            }
            switch launchCleanup(sessionID: activity.attributes.sessionID, content: activity.content.state,
                                 isEnded: isEnded, keeping: keeping, now: now) {
            case .keep:
                continue
            case .endNow:
                await activity.end(nil, dismissalPolicy: .immediate)
            case .endShowingDone(let until):
                await activity.end(activity.content, dismissalPolicy: .after(until))
            }
        }
    }
}

/// The Live Activity's "Next" button.
struct NextExerciseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Next exercise" }
    static var description: IntentDescription { IntentDescription("Moves your workout on to the next exercise.") }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Session")
    var sessionID: String

    init() {}
    init(sessionID: String) { self.sessionID = sessionID }

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutActivityControl.handle(.next, sessionID: sessionID)
        return .result()
    }
}

/// The Live Activity's "Finish" button: logs the workout as done for today.
struct FinishWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Finish workout" }
    static var description: IntentDescription { IntentDescription("Finishes your workout and logs it as done.") }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Session")
    var sessionID: String

    init() {}
    init(sessionID: String) { self.sessionID = sessionID }

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutActivityControl.handle(.finish, sessionID: sessionID)
        return .result()
    }
}
