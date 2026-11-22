import Foundation
import Observation

/// Where someone is in the programme they follow. Saved in UserDefaults.
struct ProgramProgress: Codable, Equatable {
    var programID: String
    /// Index into the programme's days of the day to do next.
    var nextDay: Int
    var startedAt: Date
    /// Programme days done since it was started (finished or marked as done, or skipped).
    var daysDone: Int = 0
    /// When the last day was done; sessions logged before this don't count again.
    var lastDoneAt: Date? = nil
}

/// The programme the person follows and which day is next. A day counts as done when
/// its workout is finished in workout mode or marked as done (`WorkoutStore` posts
/// `.workoutsDidChange`); the next day then follows, wrapping round to day 1.
@MainActor
@Observable
final class ProgramStore {

    static let shared = ProgramStore()

    static let storageKey = "currentProgram_v1"
    private let defaults: UserDefaults
    @ObservationIgnored private var observer: NSObjectProtocol?

    private(set) var progress: ProgramProgress?

    /// `defaults` and `observesWorkouts` are for tests; the app uses the shared store.
    init(defaults: UserDefaults = .standard, observesWorkouts: Bool = true) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(ProgramProgress.self, from: data) {
            progress = saved
        }
        // A programme that's no longer offered is dropped rather than shown broken.
        if let saved = progress, WorkoutProgram.named(id: saved.programID) == nil { progress = nil; persist() }
        clampDay()
        guard observesWorkouts else { return }
        observer = NotificationCenter.default.addObserver(forName: .workoutsDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ProgramStore.shared.reconcile(with: WorkoutStore.shared.completed) }
        }
        reconcile(with: WorkoutStore.shared.completed)
    }

    // MARK: Reading

    var program: WorkoutProgram? { progress.flatMap { WorkoutProgram.named(id: $0.programID) } }

    var nextDayIndex: Int? { program == nil ? nil : progress?.nextDay }

    /// The next day's workout, ready for workout mode.
    var nextWorkout: Workout? {
        guard let program, let index = nextDayIndex else { return nil }
        return program.workout(day: index)
    }

    /// "Day 2 · Pull".
    var nextDayLabel: String? {
        guard let program, let index = nextDayIndex else { return nil }
        return program.dayLabel(index)
    }

    /// Which week of the programme this is, counted from its start (1 for the first).
    var week: Int {
        guard let program, let progress else { return 1 }
        return progress.daysDone / max(program.daysPerWeek, 1) + 1
    }

    func isCurrent(_ program: WorkoutProgram) -> Bool { progress?.programID == program.id }

    // MARK: Changing

    /// Starts following `program` from `day` (day 1 by default), replacing any other.
    func start(_ program: WorkoutProgram, day: Int = 0, now: Date = Date()) {
        progress = ProgramProgress(programID: program.id, nextDay: day, startedAt: now)
        clampDay()
        persist()
    }

    func stop() {
        progress = nil
        persist()
    }

    /// Makes `index` the next day (to skip ahead or repeat a day).
    func setNextDay(_ index: Int) {
        guard var current = progress, let program, program.days.indices.contains(index) else { return }
        current.nextDay = index
        progress = current
        persist()
    }

    /// The next day is done: move on, wrapping round to day 1 after the last.
    func advance(now: Date = Date()) {
        guard var current = progress, let program else { return }
        current.nextDay = (current.nextDay + 1) % max(program.days.count, 1)
        current.daysDone += 1
        current.lastDoneAt = now
        progress = current
        persist()
    }

    /// Moves on for each logged session of the next day's workout done since the
    /// programme started (or since the last day was done), oldest first.
    func reconcile(with completed: [CompletedWorkout]) {
        for session in completed.sorted(by: { $0.date < $1.date }) {
            guard let current = progress, let key = nextWorkout?.contentKey else { return }
            if session.date > (current.lastDoneAt ?? current.startedAt), session.contentKey == key {
                advance(now: session.date)
            }
        }
    }

    // MARK: Saving

    private func clampDay() {
        guard var current = progress, let program else { return }
        if !program.days.indices.contains(current.nextDay) {
            current.nextDay = 0
            progress = current
        }
    }

    private func persist() {
        if let progress, let data = try? JSONEncoder().encode(progress) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}
