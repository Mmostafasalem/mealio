import XCTest
@testable import smartmarket

/// Programmes (multi-day plans), the exercises added for them, and the catalogue by muscle.
@MainActor
final class WorkoutProgramTests: XCTestCase {

    private func defaults(_ name: String) -> UserDefaults {
        let suite = "WorkoutProgramTests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: Programme data

    func testTheAskedForProgrammesExist() {
        let ids = Set(WorkoutProgram.all.map(\.id))
        for id in ["ppl-3", "ppl-6", "upper-lower", "full-body-3", "bro-split", "arnold-split", "home-start",
                   "pilates-beginner", "pilates-intermediate", "hyrox", "five-by-five", "run-5k"] {
            XCTAssertTrue(ids.contains(id), id)
        }
        XCTAssertEqual(ids.count, WorkoutProgram.all.count, "programme ids are unique")
        XCTAssertEqual(WorkoutProgram.named(id: "bro-split")?.days.map(\.title), ["Chest", "Back", "Shoulders", "Arms", "Legs"])
        XCTAssertEqual(WorkoutProgram.named(id: "ppl-3")?.days.map(\.title), ["Push", "Pull", "Legs"])
        XCTAssertEqual(WorkoutProgram.named(id: "ppl-6")?.days.count, 6)
        XCTAssertEqual(WorkoutProgram.named(id: "upper-lower")?.days.count, 4)
    }

    func testEveryProgrammeDayUsesOnlyCatalogueExercises() {
        for program in WorkoutProgram.all {
            XCTAssertFalse(program.name.isEmpty)
            XCTAssertFalse(program.summary.isEmpty, program.id)
            XCTAssertFalse(program.equipment.isEmpty, program.id)
            XCTAssertFalse(program.days.isEmpty, program.id)
            XCTAssertTrue((2...7).contains(program.daysPerWeek), program.id)
            XCTAssertEqual(Set(program.days.map(\.id)).count, program.days.count, "\(program.id): day ids are unique")
            for day in program.days {
                XCTAssertFalse(day.steps.isEmpty, "\(program.id) \(day.id)")
                // Workout steps are told apart by name, so a day never lists one exercise twice.
                XCTAssertEqual(Set(day.steps.map(\.exercise)).count, day.steps.count, "\(program.id) \(day.id) repeats an exercise")
                for step in day.steps {
                    XCTAssertNotNil(Exercise.named(step.exercise), "\(program.id) \(day.id): \(step.exercise) is not in the catalogue")
                    XCTAssertGreaterThanOrEqual(step.sets, 1, step.exercise)
                    XCTAssertFalse(step.reps.isEmpty, step.exercise)
                    XCTAssertGreaterThanOrEqual(step.rest, 0)
                }
            }
        }
    }

    func testProgrammeDaysBecomeStableRunnableWorkouts() {
        for program in WorkoutProgram.all {
            for index in program.days.indices {
                let a = program.workout(day: index), b = program.workout(day: index)
                XCTAssertEqual(a.id, b.id, "the same day is the same workout, so a running session resumes")
                XCTAssertEqual(a.contentKey, b.contentKey)
                XCTAssertEqual(a.exercises.count, program.days[index].steps.count)
                XCTAssertTrue(a.title.contains(program.dayLabel(index)), a.title)
                XCTAssertTrue((5...180).contains(a.durationMinutes), "\(program.id) day \(index + 1): \(a.durationMinutes) min")
                XCTAssertTrue(a.exercises.allSatisfy { !$0.note.isEmpty }, "every step carries its how-to")
            }
            let keys = program.days.indices.map { program.workout(day: $0).contentKey }
            XCTAssertEqual(Set(keys).count, keys.count, "\(program.id): days are told apart")
        }
        // Different programmes never share a workout id, even with a day id in common ("legs").
        let ids = WorkoutProgram.all.flatMap { p in p.days.indices.map { p.workout(day: $0).id } }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testPilatesAndHyroxExercisesAreInTheCatalogueWithMotionAndMuscles() {
        let added = ["The hundred", "Roll-up", "Single-leg circles", "Rolling like a ball", "Single-leg stretch",
                     "Double-leg stretch", "Criss-cross", "Spine stretch forward", "Saw", "Swan", "Pilates swimming",
                     "Side kick series", "Teaser", "Shoulder bridge", "Leg pull front", "Leg pull back",
                     "Open-leg rocker", "Spine twist", "Pilates scissors", "Mermaid stretch",
                     "Sled push", "Sled pull", "Burpee broad jump", "Wall ball", "Sandbag lunge", "Long run"]
        for name in added {
            guard let exercise = Exercise.named(name) else { XCTFail("\(name) missing"); continue }
            XCTAssertNotNil(exercise.motion, "\(name) has no movement to show")
            XCTAssertFalse(exercise.muscles.isEmpty, name)
            XCTAssertFalse(exercise.howTo.isEmpty, name)
            XCTAssertFalse(exercise.equipment.isEmpty, name)
        }
        // The eight HYROX stations are all there.
        for station in ["SkiErg", "Sled push", "Sled pull", "Burpee broad jump", "Rowing machine",
                        "Dumbbell farmer carry", "Sandbag lunge", "Wall ball"] {
            XCTAssertNotNil(Exercise.named(station), station)
        }
        let hyrox = Set(WorkoutProgram.named(id: "hyrox")!.days.flatMap { $0.steps.map(\.exercise) })
        XCTAssertTrue(hyrox.isSuperset(of: ["SkiErg", "Sled push", "Sled pull", "Burpee broad jump", "Rowing machine",
                                           "Dumbbell farmer carry", "Sandbag lunge", "Wall ball", "Run intervals"]))
        // Pilates programmes use Pilates mat work.
        for id in ["pilates-beginner", "pilates-intermediate"] {
            let names = WorkoutProgram.named(id: id)!.days.flatMap { $0.steps.map(\.exercise) }
            let pilates = names.filter { Exercise.named($0)?.isPilates == true }
            XCTAssertGreaterThan(pilates.count, names.count / 2, id)
        }
    }

    // MARK: Following a programme

    func testStartingAdvancingAndWrapping() {
        let store = ProgramStore(defaults: defaults("advance"), observesWorkouts: false)
        let program = WorkoutProgram.named(id: "ppl-3")!
        XCTAssertNil(store.program)
        store.start(program)
        XCTAssertTrue(store.isCurrent(program))
        XCTAssertEqual(store.nextDayIndex, 0)
        XCTAssertEqual(store.nextDayLabel, "Day 1 · Push")
        XCTAssertEqual(store.week, 1)
        store.advance()
        XCTAssertEqual(store.nextDayLabel, "Day 2 · Pull")
        store.advance()
        XCTAssertEqual(store.nextDayIndex, 2)
        store.advance()
        XCTAssertEqual(store.nextDayIndex, 0, "after the last day it starts again from day 1")
        XCTAssertEqual(store.week, 2)
        store.setNextDay(2)
        XCTAssertEqual(store.nextDayIndex, 2)
        store.setNextDay(9)
        XCTAssertEqual(store.nextDayIndex, 2, "a day the programme doesn't have is ignored")
        store.stop()
        XCTAssertNil(store.program)
        XCTAssertNil(store.nextWorkout)
    }

    func testProgressIsRememberedAcrossLaunches() {
        let d = defaults("persist")
        let first = ProgramStore(defaults: d, observesWorkouts: false)
        first.start(WorkoutProgram.named(id: "upper-lower")!)
        first.advance()
        let again = ProgramStore(defaults: d, observesWorkouts: false)
        XCTAssertEqual(again.program?.id, "upper-lower")
        XCTAssertEqual(again.nextDayIndex, 1)
        again.stop()
        XCTAssertNil(ProgramStore(defaults: d, observesWorkouts: false).program)

        // A programme that no longer exists is dropped.
        let gone = ProgramProgress(programID: "not-a-programme", nextDay: 0, startedAt: Date())
        d.set(try? JSONEncoder().encode(gone), forKey: ProgramStore.storageKey)
        XCTAssertNil(ProgramStore(defaults: d, observesWorkouts: false).program)
    }

    func testFinishingTheNextDaysWorkoutMovesOnOnce() {
        let store = ProgramStore(defaults: defaults("reconcile"), observesWorkouts: false)
        let program = WorkoutProgram.named(id: "five-by-five")!
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        store.start(program, now: start)
        let dayA = program.workout(day: 0)
        func done(_ workout: Workout, at date: Date) -> CompletedWorkout {
            CompletedWorkout(workoutID: workout.id, contentKey: workout.contentKey, title: workout.title,
                             kind: workout.kind, minutes: workout.durationMinutes, calories: 100, date: date)
        }
        // A session from before the programme started, or another workout, doesn't count.
        store.reconcile(with: [done(dayA, at: start.addingTimeInterval(-3600)),
                               done(WorkoutBuilder.build(kind: .gym, level: .beginner, minutes: 30, focus: .fullBody,
                                                         goal: .maintain, seed: 1), at: start.addingTimeInterval(60))])
        XCTAssertEqual(store.nextDayIndex, 0)

        let finished = done(dayA, at: start.addingTimeInterval(3600))
        store.reconcile(with: [finished])
        XCTAssertEqual(store.nextDayIndex, 1)
        store.reconcile(with: [finished])
        XCTAssertEqual(store.nextDayIndex, 1, "the same session moves on only once")

        // Two days later, workout B: wraps back round to A (a two-day programme).
        store.reconcile(with: [done(program.workout(day: 1), at: start.addingTimeInterval(2 * 86_400)), finished])
        XCTAssertEqual(store.nextDayIndex, 0)
        XCTAssertEqual(store.progress?.daysDone, 2)
    }

    func testMarkingAProgrammeDayDoneInTheWorkoutStoreAdvancesIt() {
        let d = defaults("store")
        let workouts = WorkoutStore(defaults: d)
        let store = ProgramStore(defaults: d, observesWorkouts: false)
        let program = WorkoutProgram.named(id: "home-start")!
        store.start(program, now: Date().addingTimeInterval(-60))
        XCTAssertTrue(workouts.complete(program.workout(day: 0), weightKg: 70))
        store.reconcile(with: workouts.completed)
        XCTAssertEqual(store.nextDayLabel, "Day 2 · Pull and core")
    }

    // MARK: Catalogue by muscle

    func testEveryExerciseIsInExactlyOneMuscleGroup() {
        var seen: [String: MuscleGroup] = [:]
        for group in MuscleGroup.allCases {
            for exercise in Exercise.catalog where exercise.muscleGroup == group {
                XCTAssertNil(seen[exercise.id], "\(exercise.id) is in two groups")
                seen[exercise.id] = group
            }
        }
        XCTAssertEqual(seen.count, Exercise.catalog.count, "every exercise has a group")
        // Strength work is placed by its own muscles, not by the fallback.
        for exercise in Exercise.catalog where exercise.kind == .gym || exercise.kind == .home {
            if exercise.focus == .fullBody || exercise.isPilates { continue }
            XCTAssertNotNil(exercise.groupFromMuscles, "\(exercise.id): \(exercise.muscles)")
        }
        // Every group the browser shows has something in it.
        for group in MuscleGroup.allCases {
            XCTAssertTrue(Exercise.catalog.contains { $0.muscleGroup == group }, "\(group) is empty")
        }
    }

    func testMuscleGroupsAreSensible() {
        let expected: [String: MuscleGroup] = [
            "Bench press": .chest, "Lat pulldown": .back, "Lateral raise": .shoulders, "Biceps curl": .biceps,
            "Triceps pushdown": .triceps, "Wrist curl": .forearms, "Crunch": .core, "Hip thrust": .glutes,
            "Back squat": .quads, "Lying leg curl": .hamstrings, "Standing calf raise": .calves,
            "Burpee": .fullBody, "Easy run": .cardio, "Cat-cow": .mobility, "The hundred": .mobility,
            "Wall ball": .fullBody, "Sled pull": .back, "Superman hold": .back, "Copenhagen plank": .core,
        ]
        for (name, group) in expected {
            XCTAssertEqual(Exercise.named(name)?.muscleGroup, group, name)
        }
    }
}
