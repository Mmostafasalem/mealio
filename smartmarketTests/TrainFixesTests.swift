import XCTest
@testable import smartmarket

/// The on-device workout builder's choices, the home kit rule, rep adjustments,
/// logging a workout once a day, and free-text demo matching.
@MainActor
final class TrainFixesTests: XCTestCase {

    private let day = DateComponents(calendar: .current, year: 2026, month: 3, day: 10, hour: 9).date!
    private let levels: [ExerciseLevel] = [.beginner, .intermediate, .advanced]

    /// The catalogue entries a session uses (cardio drills are named "<exercise> intervals").
    private func catalogueEntries(_ workout: Workout) -> [Exercise] {
        workout.exercises.compactMap { step in
            Exercise.named(step.name) ?? Exercise.named(step.name.replacingOccurrences(of: " intervals", with: ""))
        }
    }

    private func everySession(_ check: (Workout, ExerciseKind, ExerciseLevel, ExerciseFocus, Int) -> Void) {
        for kind in ExerciseKind.allCases {
            for level in ExerciseLevel.allCases {
                for focus in ExerciseFocus.allCases {
                    for minutes in stride(from: 10, through: 90, by: 5) {
                        let workout = WorkoutBuilder.build(kind: kind, level: level, minutes: minutes, focus: focus,
                                                           goal: .maintain, date: day)
                        check(workout, kind, level, focus, minutes)
                    }
                }
            }
        }
    }

    // MARK: Builder

    func testNoSessionRepeatsAnExercise() {
        everySession { workout, kind, level, focus, minutes in
            let names = workout.exercises.map { $0.name.lowercased() }
            XCTAssertEqual(Set(names).count, names.count, "\(kind) \(level) \(focus) \(minutes): \(names)")
            XCTAssertGreaterThanOrEqual(workout.exercises.count, 2, "\(kind) \(level) \(focus) \(minutes)")
        }
    }

    func testCoreFocusDoesNotDoubleUp() {
        for kind in [ExerciseKind.gym, .home] {
            let workout = WorkoutBuilder.build(kind: kind, level: .advanced, minutes: 90, focus: .core, goal: .maintain, date: day)
            let names = workout.exercises.map(\.name)
            XCTAssertEqual(Set(names).count, names.count, "\(names)")
            XCTAssertTrue(catalogueEntries(workout).allSatisfy { $0.focus == .core }, "\(names)")
        }
    }

    func testLevelIsNeverAboveTheOneAskedFor() {
        everySession { workout, kind, level, focus, minutes in
            let top = self.levels.firstIndex(of: level)!
            for exercise in self.catalogueEntries(workout) {
                XCTAssertLessThanOrEqual(self.levels.firstIndex(of: exercise.level)!, top,
                                         "\(exercise.name) (\(exercise.level)) in a \(level) \(kind) session")
            }
        }
    }

    func testTheChosenLevelComesFirst() {
        // Plenty of intermediate and advanced gym work exists, so those sessions lead with it.
        for level in [ExerciseLevel.intermediate, .advanced] {
            let workout = WorkoutBuilder.build(kind: .gym, level: level, minutes: 45, focus: .fullBody, goal: .maintain, date: day)
            XCTAssertTrue(catalogueEntries(workout).contains { $0.level == level }, "\(level): \(workout.exercises.map(\.name))")
        }
        let mobility = WorkoutBuilder.build(kind: .mobility, level: .beginner, minutes: 30, focus: .fullBody, goal: .maintain, date: day)
        XCTAssertTrue(catalogueEntries(mobility).allSatisfy { $0.level == .beginner })
    }

    func testHomeSessionsNeedNoSpecialKit() {
        everySession { workout, kind, level, focus, minutes in
            guard kind == .home else { return }
            for exercise in self.catalogueEntries(workout) {
                XCTAssertTrue(exercise.needsNoKit, "\(exercise.name) needs \(exercise.equipment)")
                XCTAssertEqual(exercise.kind, .home)
            }
        }
    }

    func testSessionsAreBalancedAcrossMovements() {
        // Enough different movements exist for these, so none should repeat.
        for (kind, focus) in [(ExerciseKind.gym, ExerciseFocus.lower), (.gym, .upper), (.gym, .fullBody), (.home, .lower)] {
            for offset in 0..<7 {
                let date = Calendar.current.date(byAdding: .day, value: offset, to: day)!
                let workout = WorkoutBuilder.build(kind: kind, level: .intermediate, minutes: 60, focus: focus, goal: .maintain, date: date)
                let families = catalogueEntries(workout).map(\.family)
                XCTAssertEqual(Set(families).count, families.count, "\(kind) \(focus): \(workout.exercises.map(\.name))")
            }
        }
        XCTAssertEqual(Exercise.named("Dumbbell Romanian deadlift")?.family, Exercise.named("Smith machine Romanian deadlift")?.family)
        XCTAssertEqual(Exercise.named("Dumbbell triceps kickback")?.family, "triceps")
        XCTAssertEqual(Exercise.named("Incline dumbbell press")?.family, "chest press")
    }

    func testSameDayIsStableAndDaysVary() {
        let morning = WorkoutBuilder.build(kind: .gym, level: .intermediate, minutes: 45, focus: .fullBody, goal: .maintain, date: day)
        let evening = WorkoutBuilder.build(kind: .gym, level: .intermediate, minutes: 45, focus: .fullBody, goal: .maintain,
                                           date: day.addingTimeInterval(10 * 3600))
        XCTAssertEqual(morning.exercises.map(\.name), evening.exercises.map(\.name))

        var sessions: Set<[String]> = []
        var seen: Set<String> = []
        for offset in 0..<14 {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: day)!
            let workout = WorkoutBuilder.build(kind: .gym, level: .intermediate, minutes: 45, focus: .fullBody, goal: .maintain, date: date)
            sessions.insert(workout.exercises.map(\.name))
            seen.formUnion(workout.exercises.map(\.name))
        }
        XCTAssertGreaterThanOrEqual(sessions.count, 10, "a new day usually brings a new session")
        XCTAssertGreaterThan(seen.count, 20, "the whole catalogue gets used, not its first entries")

        let fixed = WorkoutBuilder.build(kind: .home, level: .beginner, minutes: 30, focus: .upper, goal: .lose, seed: 42)
        let again = WorkoutBuilder.build(kind: .home, level: .beginner, minutes: 30, focus: .upper, goal: .lose,
                                         date: day.addingTimeInterval(86_400 * 30), seed: 42)
        XCTAssertEqual(fixed.exercises.map(\.name), again.exercises.map(\.name), "a fixed seed ignores the date")
    }

    func testCardioPicksByLevel() {
        for level in levels {
            let workout = WorkoutBuilder.build(kind: .cardio, level: level, minutes: 40, focus: .fullBody, goal: .lose, date: day)
            XCTAssertFalse(catalogueEntries(workout).isEmpty, "\(level): \(workout.exercises.map(\.name))")
            let total = workout.exercises.reduce(0) { $0 + $1.minutes }
            XCTAssertLessThanOrEqual(abs(total - 40), 3)
        }
    }

    // MARK: Kit

    func testNoKitRule() {
        func exercise(_ equipment: String) -> Exercise {
            Exercise(id: "x", name: "X", kind: .home, focus: .core, muscles: "", equipment: equipment,
                     level: .beginner, prescription: "3 × 10", howTo: "")
        }
        for yes in ["None", "Mat", "A wall", "Sturdy chair", "Towel", "Optional weight", "A doorway", "Chair or bench",
                    "Bench or sturdy table", "Mat (band optional)", "Step or box", "Wall or pole", "Sturdy step or chair"] {
            XCTAssertTrue(exercise(yes).needsNoKit, yes)
        }
        for no in ["Pull-up bar", "Dip bars", "Parallettes", "Bench", "Box", "Stability ball", "Resistance band",
                   "Resistance band, chair", "Suspension trainer", "Ab wheel", "Weight plate", "Mat, ankle anchor", "Pull-up bar, towels"] {
            XCTAssertFalse(exercise(no).needsNoKit, no)
        }
        let catalogue = Dictionary(uniqueKeysWithValues: Exercise.catalog.map { ($0.id, $0) })
        for id in ["push-up", "chair-dip", "bench-dip", "step-down", "decline-push-up", "clamshell", "wall-sit", "doorway-row"] {
            XCTAssertEqual(catalogue[id]?.needsNoKit, true, id)
        }
        for id in ["dip", "chest-dip", "neutral-grip-pull-up", "handstand-push-up", "stability-ball-hamstring-curl",
                   "banded-squat", "copenhagen-plank", "ab-wheel", "l-sit-hold"] {
            XCTAssertEqual(catalogue[id]?.needsNoKit, false, id)
        }
    }

    // MARK: Reps

    func testRepsAdjustOnlyModerateRanges() {
        XCTAssertEqual(WorkoutBuilder.reps(from: "3 × 5", goal: .gain), "5", "low-rep strength work stays")
        XCTAssertEqual(WorkoutBuilder.reps(from: "3 × 6", goal: .lose), "6")
        XCTAssertEqual(WorkoutBuilder.reps(from: "4 × 8", goal: .lose), "8")
        XCTAssertEqual(WorkoutBuilder.reps(from: "3 × 12", goal: .gain), "10")
        XCTAssertEqual(WorkoutBuilder.reps(from: "3 × 10", goal: .gain), "8")
        XCTAssertEqual(WorkoutBuilder.reps(from: "3 × 10", goal: .lose), "12")
        XCTAssertEqual(WorkoutBuilder.reps(from: "3 × 15", goal: .lose), "15")
        XCTAssertEqual(WorkoutBuilder.reps(from: "3 × 12", goal: .maintain), "12")
        XCTAssertEqual(WorkoutBuilder.reps(from: "3 × 20", goal: .gain), "20", "high-rep work stays")
        XCTAssertEqual(WorkoutBuilder.reps(from: "3 × 30 sec", goal: .lose), "30 sec")
        XCTAssertEqual(WorkoutBuilder.reps(from: "3 × 10 each side", goal: .gain), "10 each side")
    }

    // MARK: Logging

    func testMarkingDoneIsOncePerWorkoutPerDay() throws {
        let suite = "TrainFixesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkoutStore(defaults: defaults)
        let workout = WorkoutBuilder.build(kind: .home, level: .beginner, minutes: 30, focus: .fullBody, goal: .maintain, date: day)
        let other = WorkoutBuilder.build(kind: .gym, level: .beginner, minutes: 30, focus: .fullBody, goal: .maintain, date: day)

        XCTAssertFalse(store.isCompletedToday(workout, now: day))
        XCTAssertTrue(store.complete(workout, weightKg: 70, now: day))
        XCTAssertFalse(store.complete(workout, weightKg: 70, now: day.addingTimeInterval(3600)), "same workout, same day")
        XCTAssertTrue(store.isCompletedToday(workout, now: day))
        XCTAssertEqual(store.completed.count, 1)
        XCTAssertTrue(store.complete(other, weightKg: 70, now: day))
        XCTAssertTrue(store.complete(workout, weightKg: 70, now: day.addingTimeInterval(86_400)), "the next day counts again")
        XCTAssertEqual(store.completed.count, 3)
        // Survives a reload.
        XCTAssertTrue(WorkoutStore(defaults: defaults).isCompletedToday(workout, now: day))
    }

    func testTheSameSessionBuiltTwiceIsLoggedOncePerDay() throws {
        let suite = "TrainFixesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkoutStore(defaults: defaults)
        // Generating twice gives two workouts with new ids but the same content.
        let first = WorkoutBuilder.build(kind: .gym, level: .intermediate, minutes: 45, focus: .fullBody, goal: .maintain, date: day)
        let again = WorkoutBuilder.build(kind: .gym, level: .intermediate, minutes: 45, focus: .fullBody, goal: .maintain, date: day)
        XCTAssertNotEqual(first.id, again.id)
        XCTAssertEqual(first.contentKey, again.contentKey)

        XCTAssertTrue(store.complete(first, weightKg: 70, now: day))
        XCTAssertTrue(store.isCompletedToday(again, now: day))
        XCTAssertFalse(store.complete(again, weightKg: 70, now: day.addingTimeInterval(1800)), "same session, built again")
        XCTAssertEqual(store.completed.count, 1)
        XCTAssertTrue(WorkoutStore(defaults: defaults).isCompletedToday(again, now: day), "survives a reload")

        // A different length or a different exercise order is a different session.
        let longer = WorkoutBuilder.build(kind: .gym, level: .intermediate, minutes: 60, focus: .fullBody, goal: .maintain, date: day)
        XCTAssertNotEqual(longer.contentKey, first.contentKey)
        XCTAssertTrue(store.complete(longer, weightKg: 70, now: day))
        let reordered = Workout(title: first.title, summary: first.summary, kind: first.kind, level: first.level,
                                durationMinutes: first.durationMinutes, warmup: first.warmup, cooldown: first.cooldown,
                                exercises: Array(first.exercises.reversed()), safetyNote: first.safetyNote)
        XCTAssertNotEqual(reordered.contentKey, first.contentKey)
        XCTAssertTrue(store.complete(reordered, weightKg: 70, now: day))
        // The next day it counts again.
        XCTAssertTrue(store.complete(again, weightKg: 70, now: day.addingTimeInterval(86_400)))
        XCTAssertEqual(store.completed.count, 4)
    }

    func testOlderCompletedSessionsStillLoad() throws {
        let suite = "TrainFixesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Saved before sessions carried a workout id or a content key.
        let json = """
        [{"id":"\(UUID().uuidString)","title":"Walk","kind":"cardio","minutes":30,"calories":120,
          "date":\(day.timeIntervalSinceReferenceDate)}]
        """
        defaults.set(Data(json.utf8), forKey: "completedWorkouts_v1")
        let store = WorkoutStore(defaults: defaults)
        XCTAssertEqual(store.completed.count, 1)
        XCTAssertNil(store.completed.first?.contentKey)
        XCTAssertNil(store.completed.first?.workoutID)
        let workout = WorkoutBuilder.build(kind: .cardio, level: .beginner, minutes: 30, focus: .fullBody, goal: .maintain, date: day)
        XCTAssertFalse(store.isCompletedToday(workout, now: day), "an old entry matches nothing")
        XCTAssertTrue(store.complete(workout, weightKg: 70, now: day))
        XCTAssertEqual(WorkoutStore(defaults: defaults).completed.count, 2)
    }

    // MARK: Catalogue

    func testSupermanWorksTheBackOfTheBody() {
        XCTAssertEqual(Exercise.named("Superman hold")?.focus, .core)
        XCTAssertEqual(Exercise.named("  superman HOLD ")?.id, "superman")
    }

    // MARK: Matching

    func testFreeTextMatchingIsWordBased() {
        XCTAssertNil(ExerciseMotion.matching(name: "Overhead triceps extension (cable)"), "not a press")
        XCTAssertEqual(ExerciseMotion.matching(name: "Narrow-grip push-up"), .pushUp)
        XCTAssertNil(ExerciseMotion.matching(name: "Narrow stance calf raise"), "'narrow' is not a row")
        XCTAssertNil(ExerciseMotion.matching(name: "Scatter drill"), "'scatter' is not cat-cow")
        XCTAssertNotEqual(ExerciseMotion.matching(name: "Diploma stretch"), .dip, "'diploma' is not a dip")
        XCTAssertNil(ExerciseMotion.matching(name: "External shoulder rotation"), "'rotation' alone is not a twist")
        XCTAssertEqual(ExerciseMotion.matching(name: "Walking lunges"), .lunge)
        XCTAssertEqual(ExerciseMotion.matching(name: "Seated cable row"), .seatedRow)
        XCTAssertEqual(ExerciseMotion.matching(name: "Child's pose"), .childsPose)
        XCTAssertEqual(ExerciseMotion.matching(name: "Push ups"), .pushUp)
        XCTAssertEqual(ExerciseMotion.matching(name: "Barbell Back Squat"), .backSquat)
        XCTAssertNil(ExerciseMotion.matching(name: "Turkish get-up"))
    }

    func testApostrophesFoldAndOtherWalksGetNoWalkingDemo() {
        XCTAssertEqual(ExerciseText.matchWords("Child's pose"), ["child", "pose"])
        XCTAssertEqual(ExerciseText.matchWords("Child\u{2019}s pose"), ["child", "pose"])
        XCTAssertEqual(ExerciseMotion.matching(name: "Childs pose"), .childsPose)
        XCTAssertEqual(ExerciseMotion.matching(name: "Child\u{2019}s pose"), .childsPose)
        XCTAssertEqual(ExerciseMotion.matching(name: "World's greatest stretch"), .lungeReach)
        // A walk that is really another exercise gets no demo rather than a plain walk.
        for name in ["Wall walk", "Farmer's walk", "Farmers walk", "Farmer\u{2019}s walk", "Crab walk", "Bear crawl",
                     "Banded monster walk", "Lateral band walk", "Plank walk", "Hand walk", "Waiter's walk", "Duck walk"] {
            XCTAssertNotEqual(ExerciseMotion.matching(name: name), .walk, name)
        }
        XCTAssertNil(ExerciseMotion.matching(name: "Wall walk"))
        XCTAssertNil(ExerciseMotion.matching(name: "Farmer's walk"))
        XCTAssertNil(ExerciseMotion.matching(name: "Crab walk"))
        // Plain walks still walk.
        for name in ["Brisk walk", "Incline walking", "Walk", "Power walking", "Easy hike"] {
            XCTAssertEqual(ExerciseMotion.matching(name: name), .walk, name)
        }
        XCTAssertEqual(ExerciseMotion.matching(name: "Walking lunges"), .lunge)
    }

    func testStepsFindTheirCatalogueEntryByCloseName() {
        let step = WorkoutExercise(name: "Push ups", sets: 3, reps: "10", minutes: 0, restSeconds: 30, note: "")
        let guide = ExerciseGuide(step: step)
        XCTAssertEqual(guide.drawingID, "push-up")
        XCTAssertEqual(guide.muscles, Exercise.named("Push-up")?.muscles)
        XCTAssertEqual(Exercise.closestMatch(name: "jumping JACK")?.id, "jumping-jack")
        XCTAssertNil(Exercise.closestMatch(name: "Turkish get-up"))
    }

    // MARK: Drawings

    func testDrawingsAreReadOffTheMainThreadAndPreloadReturnsAtOnce() {
        let release = DispatchSemaphore(value: 0)
        let reading = expectation(description: "file read started")
        let readerWasMain = LockedFlag()
        // A fresh loader whose read waits until the test lets it go, so "returns at once" is deterministic.
        let drawings = ExerciseDrawings(willRead: {
            readerWasMain.set(Thread.isMainThread)
            reading.fulfill()
            release.wait()
        })
        drawings.startLoading()
        XCTAssertFalse(drawings.isLoaded, "startLoading returns before the file is read")
        wait(for: [reading], timeout: 10)
        XCTAssertFalse(drawings.isLoaded)
        release.signal()
        let loaded = expectation(description: "loaded")
        DispatchQueue.global().async {
            while !drawings.isLoaded { usleep(20_000) }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 30)
        XCTAssertEqual(readerWasMain.value, false, "the hook ran on the loading thread")
        XCTAssertEqual(drawings.wasReadOnMainThread, false, "the file was decoded off the main thread")

        // Building a drawing's paths for a view happens off the main thread too.
        XCTAssertTrue(drawings.hasDrawing(forExercise: "push-up"))
        XCTAssertNil(drawings.cachedDrawing(forExercise: "push-up"), "nothing is built until asked for")
        let builderWasMain = LockedFlag()
        let builtInBackground = expectation(description: "built")
        drawings.buildInBackground(forExercise: "push-up") {
            builderWasMain.set(Thread.isMainThread)
            builtInBackground.fulfill()
        }
        wait(for: [builtInBackground], timeout: 30)
        XCTAssertEqual(builderWasMain.value, false)
        XCTAssertEqual(drawings.lastBackgroundBuildWasOnMainThread, false)
        XCTAssertEqual(drawings.cachedDrawing(forExercise: "push-up")?.frames.count, 3)
    }

    func testDrawingsLoadInTheBackgroundAndSkipMismatches() {
        ExerciseDrawings.preload()
        let ready = expectation(description: "drawings loaded")
        Task { @MainActor in
            while !ExerciseDrawingsStatus.shared.isReady { try? await Task.sleep(nanoseconds: 50_000_000) }
            ready.fulfill()
        }
        wait(for: [ready], timeout: 30)
        XCTAssertEqual(ExerciseDrawings.shared.wasReadOnMainThread, false)
        XCTAssertNotNil(ExerciseDrawingsStatus.shared.credit)
        XCTAssertTrue(ExerciseDrawingsStatus.shared.credit?.text.contains("CC BY-SA") ?? false)

        // Views get a placeholder while the paths are built in the background, then the drawing.
        let status = ExerciseDrawingsStatus.shared
        let shown = "push-up"
        XCTAssertTrue(ExerciseDrawings.shared.hasDrawing(forExercise: shown))
        if status.drawing(forExercise: shown) == nil {
            XCTAssertTrue(status.isPending(forExercise: shown), "a placeholder stands in while it builds")
        }
        let built = expectation(description: "drawing built")
        Task { @MainActor in
            while status.drawing(forExercise: shown) == nil { try? await Task.sleep(nanoseconds: 20_000_000) }
            built.fulfill()
        }
        wait(for: [built], timeout: 30)
        XCTAssertFalse(status.isPending(forExercise: shown))
        if let onMain = ExerciseDrawings.shared.lastBackgroundBuildWasOnMainThread {
            XCTAssertFalse(onMain, "paths for views are built off the main thread")
        }
        XCTAssertNil(status.drawing(forExercise: "not-an-exercise"))
        XCTAssertFalse(status.isPending(forExercise: "not-an-exercise"))

        // Drawings that show a different exercise fall back to the posed figure, and have no credit.
        XCTAssertNil(ExerciseDrawings.shared.drawing(forExercise: "thoracic-rotation"))
        XCTAssertFalse(ExerciseDrawings.shared.hasDrawing(forExercise: "thoracic-rotation"))
        XCTAssertFalse(status.isPending(forExercise: "thoracic-rotation"))
        XCTAssertNil(status.drawing(forExercise: "thoracic-rotation"))
        XCTAssertNotNil(Exercise.named("Thoracic rotation")?.motion)
        // Built once, then served from the (bounded) cache.
        let first = ExerciseDrawings.shared.drawing(forExercise: "plank")
        XCTAssertEqual(first?.frames.count, 3)
        XCTAssertEqual(ExerciseDrawings.shared.cachedDrawing(forExercise: "plank")?.slug, first?.slug)
        XCTAssertGreaterThan(ExerciseDrawings.cacheLimit, 20)
    }
}

/// A Bool written on one thread and read on another.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool?
    func set(_ value: Bool) { lock.withLock { stored = value } }
    var value: Bool? { lock.withLock { stored } }
}

