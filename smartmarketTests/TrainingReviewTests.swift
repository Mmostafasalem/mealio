import XCTest
@testable import smartmarket

/// Fixes from the training review: honest session lengths, formatting, records, clamps.
@MainActor
final class TrainingReviewTests: XCTestCase {

    private func defaults(_ name: String) -> UserDefaults {
        let suite = "TrainingReviewTests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func workout(_ steps: [WorkoutExercise], minutes: Int = 30) -> Workout {
        Workout(title: "Review", summary: "", kind: .gym, level: .beginner, durationMinutes: minutes,
                warmup: "", cooldown: "", exercises: steps, safetyNote: "")
    }

    // MARK: Generated time

    func testStrengthSessionsFillTheTimeAskedFor() {
        for kind in [ExerciseKind.gym, .home] {
            for level in ExerciseLevel.allCases {
                for minutes in [20, 30, 45, 60] {
                    let w = WorkoutBuilder.build(kind: kind, level: level, minutes: minutes, focus: .fullBody,
                                                 goal: .maintain, seed: 7)
                    XCTAssertLessThanOrEqual(abs(w.durationMinutes - minutes), 2, "\(kind) \(level) \(minutes): \(w.durationMinutes)")
                    XCTAssertTrue(w.exercises.allSatisfy { (1...5).contains($0.sets) }, "\(kind) \(level) \(minutes)")
                    // The label is what the steps add up to, plus a warm-up and cool-down of at most 8 minutes.
                    let work = Workout.estimatedMinutes(of: w.exercises)
                    XCTAssertTrue((work...work + 8).contains(w.durationMinutes), "\(kind) \(level) \(minutes)")
                }
            }
        }
    }

    func testCardioBlocksSumToTheMinutesEvenWhenShort() {
        for level in ExerciseLevel.allCases {
            for minutes in [10, 15, 40] {
                let w = WorkoutBuilder.build(kind: .cardio, level: level, minutes: minutes, focus: .fullBody,
                                             goal: .maintain, seed: 3)
                XCTAssertEqual(w.exercises.reduce(0) { $0 + $1.minutes }, minutes, "\(level) \(minutes)")
                XCTAssertEqual(w.durationMinutes, minutes)
            }
        }
    }

    func testMobilityIsLabelledWithItsRealLength() {
        let long = WorkoutBuilder.build(kind: .mobility, level: .beginner, minutes: 90, focus: .fullBody, goal: .maintain, seed: 5)
        XCTAssertEqual(long.durationMinutes, Workout.estimatedMinutes(of: long.exercises, extraSeconds: 120))
        XCTAssertLessThanOrEqual(long.durationMinutes, 90)
        XCTAssertEqual(Set(long.exercises.map(\.name)).count, long.exercises.count, "capped by the catalogue, no repeats")
    }

    func testAStepsTimeCountsSetsRepsAndRests() {
        let step = WorkoutExercise(name: "Squat", sets: 3, reps: "10", minutes: 0, restSeconds: 60, note: "")
        XCTAssertEqual(step.estimatedSeconds, 3 * 30 + 2 * 60 + 45)
        let sides = WorkoutExercise(name: "Lunge", sets: 2, reps: "10 each side", minutes: 0, restSeconds: 30, note: "")
        XCTAssertEqual(sides.secondsPerSet, 60)
        let block = WorkoutExercise(name: "Run", sets: 1, reps: "easy", minutes: 12, restSeconds: 0, note: "")
        XCTAssertEqual(block.estimatedSeconds, 720)
    }

    // MARK: Names

    func testIntervalNamesDontDouble() {
        XCTAssertEqual(WorkoutBuilder.intervalName("Run intervals"), "Run intervals")
        XCTAssertEqual(WorkoutBuilder.intervalName("Jump rope"), "Jump rope intervals")
        XCTAssertEqual(ExerciseGuide.catalogueEntry(named: "Jump rope intervals")?.name, "Jump rope")
        XCTAssertEqual(ExerciseGuide.catalogueEntry(named: "Run intervals")?.name, "Run intervals")
    }

    // MARK: Formatting

    func testWholePoundsHaveNoDecimal() {
        let kg = 185 * WeightUnit.kgPerPound
        XCTAssertEqual(TrainingFormat.weightNumber(kg, .lb), "185")
        XCTAssertEqual(TrainingFormat.weight(kg, .lb), "185 \(WeightUnit.lb.suffix)")
        XCTAssertEqual(TrainingFormat.weightNumber(62.5, .kg), "62.5")
        XCTAssertEqual(TrainingFormat.weightNumber(60, .kg), "60")
        XCTAssertEqual(TrainingFormat.weightNumber(59.96, .kg), "60", "rounded first, then the .0 dropped")
    }

    // MARK: Workout mode

    func testARecordIsMarkedOncePerExercise() {
        let d = defaults("pr")
        let log = TrainingLogStore(defaults: d)
        let bench = WorkoutExercise(name: "Bench press", sets: 3, reps: "8", minutes: 0, restSeconds: 0, note: "")
        let w = workout([bench])
        let first = WorkoutModeModel(workout: w, log: log, defaults: d, tracksSession: false, now: Date(timeIntervalSinceNow: -86_400))
        first.setWeight(60, set: 0)
        first.completeSet()
        first.finish(now: Date(timeIntervalSinceNow: -80_000))

        let second = WorkoutModeModel(workout: w, log: log, defaults: d, tracksSession: false)
        second.setWeight(65, set: 0)
        for _ in 0..<3 { second.completeSet() }
        let ex = second.exercises[0]
        XCTAssertEqual(ex.sets.filter { second.isRecord($0, in: ex) }.count, 1, "three sets at the new best are one record")
        XCTAssertTrue(second.isRecord(ex.sets[0], in: ex))
        XCTAssertEqual(second.recordCount, 1)
    }

    func testZeroRepsAndSecondsAreClamped() {
        let d = defaults("clamp")
        let steps = [WorkoutExercise(name: "Push-up", sets: 2, reps: "10", minutes: 0, restSeconds: 0, note: "", tracking: .reps),
                     WorkoutExercise(name: "Plank", sets: 1, reps: "30 sec", minutes: 0, restSeconds: 0, note: "", tracking: .time)]
        let model = WorkoutModeModel(workout: workout(steps), log: TrainingLogStore(defaults: d), defaults: d, tracksSession: false)
        model.setReps(0, set: 0)
        XCTAssertEqual(model.exercises[0].sets[0].reps, 1)
        model.go(to: 1)
        model.setSeconds(0, set: 0)
        XCTAssertEqual(model.exercises[1].sets[0].seconds, 1)
    }

    func testAnEarlyStopKeepsTheTargetAndAPausedEditTakesEffect() {
        let d = defaults("timer")
        let plank = WorkoutExercise(name: "Plank", sets: 2, reps: "60 sec", minutes: 0, restSeconds: 0, note: "", tracking: .time)
        let model = WorkoutModeModel(workout: workout([plank]), log: TrainingLogStore(defaults: d), defaults: d, tracksSession: false)
        let start = Date()
        model.startTimer(now: start)
        model.completeSet(now: start.addingTimeInterval(20))
        XCTAssertEqual(model.exercises[0].sets[0].seconds ?? 0, 20, accuracy: 1)
        XCTAssertEqual(model.exercises[0].sets[0].targetSeconds, 60)
        model.addSet()
        XCTAssertEqual(model.exercises[0].sets.last?.seconds, 60, "a new set copies what was asked for")

        // Paused, then edited: the pause is dropped so the new time counts.
        model.startTimer(now: start)
        model.pauseTimer(now: start.addingTimeInterval(10))
        XCTAssertEqual(model.timerPausedLeft, 50)
        model.setSeconds(90, set: 1)
        XCTAssertNil(model.timerPausedLeft)

        // Reopening an earlier set stops a running timer, so it can't complete the wrong set.
        model.startTimer(now: start)
        model.reopen(0)
        XCTAssertFalse(model.timerRunning)
        XCTAssertEqual(model.exercises[0].sets[0].seconds, 60, "back to its target")
    }

    func testADraftIsSavedBeforeTheFirstSet() {
        let d = defaults("draft")
        let w = workout([WorkoutExercise(name: "Push-up", sets: 2, reps: "10", minutes: 0, restSeconds: 0, note: "")])
        let started = Date(timeIntervalSinceNow: -600)
        _ = WorkoutModeModel(workout: w, log: TrainingLogStore(defaults: d), defaults: d, tracksSession: false, now: started)
        XCTAssertEqual(WorkoutModeModel.draftSetsDone(for: w, defaults: d), 0)
        let reopened = WorkoutModeModel(workout: w, log: TrainingLogStore(defaults: d), defaults: d, tracksSession: false)
        XCTAssertEqual(reopened.startedAt.timeIntervalSince(started), 0, accuracy: 1)
    }

    // MARK: Logging

    func testFinishingEarlyLogsTheMinutesTrained() {
        let d = defaults("early")
        let store = WorkoutStore(defaults: d)
        let w = workout([WorkoutExercise(name: "Squat", sets: 3, reps: "10", minutes: 0, restSeconds: 60, note: "")], minutes: 30)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let logID = UUID()
        XCTAssertTrue(store.complete(w, weightKg: 70, now: start.addingTimeInterval(600),
                                     tracked: DateInterval(start: start, duration: 600), logID: logID))
        let entry = store.completed.first
        XCTAssertEqual(entry?.minutes, 10)
        XCTAssertEqual(entry?.calories ?? 0, w.estimatedCalories(weightKg: 70) / 3, accuracy: 1)
        XCTAssertEqual(entry?.logID, logID)
        store.removeCompleted(logID: logID)
        XCTAssertTrue(store.completed.isEmpty, "deleted with its log")

        // Longer than planned still counts the plan; a few seconds counts one minute.
        let other = WorkoutStore(defaults: defaults("early2"))
        other.complete(w, weightKg: 70, now: start, tracked: DateInterval(start: start, duration: 3600))
        XCTAssertEqual(other.completed.first?.minutes, 30)
        let brief = WorkoutStore(defaults: defaults("early3"))
        brief.complete(w, weightKg: 70, now: start, tracked: DateInterval(start: start, duration: 5))
        XCTAssertEqual(brief.completed.first?.minutes, 1)
    }

    func testALockScreenFinishWithNothingDoneLogsNothing() {
        let d = defaults("lock")
        let store = WorkoutStore(defaults: d)
        let w = workout([WorkoutExercise(name: "Squat", sets: 3, reps: "10", minutes: 0, restSeconds: 60, note: "")])
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = WorkoutSession(defaults: d, store: store, weightKg: { 70 }, usesLiveActivities: false,
                                     onFinishedOutsideApp: {})
        session.start(w, now: start)
        // Workout mode was open (a draft with no set done), then Finish on the lock screen.
        _ = WorkoutModeModel(workout: w, log: TrainingLogStore(defaults: d), defaults: d, tracksSession: false, now: start)
        var stored = WorkoutSessionStore.load(from: d)
        stored?.finish(at: start.addingTimeInterval(900))
        if let stored { WorkoutSessionStore.save(stored, to: d) }
        session.syncFromStore(now: start.addingTimeInterval(901))
        XCTAssertNil(session.state)
        XCTAssertTrue(store.completed.isEmpty)
        XCTAssertNil(d.data(forKey: WorkoutModeModel.draftKey))
    }

    func testSavedCustomWorkoutsAreNeverEvicted() {
        let store = WorkoutStore(defaults: defaults("saved"))
        var mine = workout([WorkoutExercise(name: "Squat", sets: 3, reps: "10", minutes: 0, restSeconds: 60, note: "")])
        mine.source = "custom"
        store.save(mine)
        for _ in 0..<35 { store.save(workout([WorkoutExercise(name: "Lunge", sets: 3, reps: "10", minutes: 0, restSeconds: 60, note: "")])) }
        XCTAssertTrue(store.isSaved(mine))
        XCTAssertEqual(store.saved.filter { $0.source != "custom" }.count, 30)
    }

    // MARK: Builder

    func testEditingKeepsNotesAndSuffixes() {
        let lunge = WorkoutExercise(name: "Reverse lunge", sets: 3, reps: "10 each side", minutes: 0, restSeconds: 30, note: "Step back.")
        var item = BuilderItem(step: lunge)
        XCTAssertEqual(item.step, lunge, "untouched steps go back as they were")
        item.sets = 4
        XCTAssertEqual(item.step.reps, "10 each side")
        XCTAssertEqual(item.step.sets, 4)
        XCTAssertEqual(item.step.note, "Step back.")

        let steady = WorkoutExercise(name: "Brisk walk", sets: 1, reps: "conversational pace", minutes: 12, restSeconds: 0, note: "Easy.")
        var block = BuilderItem(step: steady)
        XCTAssertEqual(block.step, steady)
        block.seconds = 900
        XCTAssertEqual(block.step.minutes, 15)
        XCTAssertEqual(block.step.reps, "conversational pace")
        XCTAssertEqual(BuilderItem.suffix(of: "30 sec each side"), " each side")
        XCTAssertEqual(BuilderItem.suffix(of: "10"), "")
    }
}
