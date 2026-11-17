import XCTest
@testable import smartmarket

@MainActor
final class WorkoutModeTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WorkoutModeTests")
        defaults.removePersistentDomain(forName: "WorkoutModeTests")
    }

    private func workout() -> Workout {
        Workout(title: "Push day", summary: "", kind: .gym, level: .beginner, durationMinutes: 30, warmup: "", cooldown: "",
                exercises: [
                    WorkoutExercise(name: "Bench press", sets: 2, reps: "8", minutes: 0, restSeconds: 60, note: ""),
                    WorkoutExercise(name: "Plank", sets: 1, reps: "30 sec", minutes: 0, restSeconds: 0, note: ""),
                ],
                safetyNote: "")
    }

    func testTrackingIsGuessedFromTheStep() {
        let w = workout()
        XCTAssertEqual(ExerciseTracking.guess(for: w.exercises[0]), .weightReps)
        XCTAssertEqual(ExerciseTracking.guess(for: w.exercises[1]), .time)
        XCTAssertEqual(ExerciseTracking.guess(for: WorkoutExercise(name: "Push-up", sets: 3, reps: "10", minutes: 0, restSeconds: 45, note: "")), .reps)
    }

    func testCompletingSetsRestsMovesOnAndFinishesWithTheNumbers() {
        let log = TrainingLogStore(defaults: defaults)
        let model = WorkoutModeModel(workout: workout(), log: log, defaults: defaults, session: nil)
        XCTAssertEqual(model.exercises[1].sets.first?.seconds, 30)

        model.setWeight(60, set: 0)
        model.setReps(8, set: 0)
        model.completeSet()
        XCTAssertNotNil(model.restEndsAt, "a rest follows a set")
        XCTAssertEqual(model.currentSetIndex, 1)
        model.skipRest()
        model.setWeight(62.5, set: 1)
        model.completeSet()
        XCTAssertEqual(model.exerciseIndex, 1, "the last set moves on to the next exercise")
        model.completeSet()
        XCTAssertTrue(model.allDone)

        model.finish()
        let saved = try? XCTUnwrap(log.workouts.first)
        XCTAssertEqual(saved?.setsDone, 3)
        XCTAssertEqual(saved?.volumeKg ?? 0, 60 * 8 + 62.5 * 8, accuracy: 0.01)
        XCTAssertTrue(saved?.records.isEmpty ?? false, "the first time sets no records")
        XCTAssertNil(defaults.data(forKey: WorkoutModeModel.draftKey))
    }

    func testTheNextWorkoutStartsFromLastTimeAndSpotsRecords() {
        let log = TrainingLogStore(defaults: defaults)
        let first = WorkoutModeModel(workout: workout(), log: log, defaults: defaults, session: nil, now: Date(timeIntervalSinceNow: -86_400))
        first.setWeight(60, set: 0); first.completeSet(); first.skipRest()
        first.setWeight(60, set: 1); first.completeSet()
        first.finish(now: Date(timeIntervalSinceNow: -80_000))

        let second = WorkoutModeModel(workout: workout(), log: log, defaults: defaults, session: nil)
        XCTAssertEqual(second.exercises[0].sets[0].weightKg, 60, "starts from last time")
        second.setWeight(65, set: 0)
        second.completeSet()
        XCTAssertTrue(second.isRecord(second.exercises[0].sets[0], in: second.exercises[0]))
        second.finish()
        let records = log.workouts.first?.records ?? []
        XCTAssertTrue(records.contains { $0.kind == .heaviest && $0.value == 65 })
    }

    func testADraftSurvivesClosingTheApp() {
        let log = TrainingLogStore(defaults: defaults)
        let w = workout()
        let model = WorkoutModeModel(workout: w, log: log, defaults: defaults, session: nil)
        model.setWeight(70, set: 0)
        model.completeSet()
        let reopened = WorkoutModeModel(workout: w, log: log, defaults: defaults, session: nil)
        XCTAssertEqual(reopened.exercises[0].sets[0].weightKg, 70)
        XCTAssertTrue(reopened.exercises[0].sets[0].done)
    }

    func testATypedWeightCarriesToTheSetsBelow() {
        let model = WorkoutModeModel(workout: workout(), log: TrainingLogStore(defaults: defaults), defaults: defaults, session: nil)
        model.setWeight(40, set: 0)
        XCTAssertEqual(model.exercises[0].sets[1].weightKg, 40)
        model.setWeight(45, set: 1)
        XCTAssertEqual(model.exercises[0].sets[0].weightKg, 40, "only sets below change")
    }

    func testOneRepMaxIsOnlyEstimatedForLowReps() {
        XCTAssertEqual(TrainingLogStore.oneRepMax(weightKg: 100, reps: 1), 100)
        XCTAssertEqual(TrainingLogStore.oneRepMax(weightKg: 100, reps: 10) ?? 0, 133.33, accuracy: 0.01)
        XCTAssertNil(TrainingLogStore.oneRepMax(weightKg: 100, reps: 20))
    }
}
