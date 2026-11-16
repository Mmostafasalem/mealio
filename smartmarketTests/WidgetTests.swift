import XCTest
@testable import smartmarket

/// The widgets' snapshot (today-only totals, goals, planned meals, the midnight
/// turn-over), the wording the widgets show, and the workout session behind the
/// Live Activity (Next / Finish bounds, logging once).
@MainActor
final class WidgetTests: XCTestCase {

    private let calendar = Calendar.current
    private lazy var now = DateComponents(calendar: calendar, year: 2026, month: 3, day: 10, hour: 13).date!

    private func defaults(_ name: String = #function) -> UserDefaults {
        let suite = "WidgetTests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func entry(_ kcal: Int, protein: Double = 10, carbs: Double = 20, fat: Double = 5, at date: Date) -> FoodLogEntry {
        FoodLogEntry(name: "Food", slot: .lunch, servingG: 100, calories: kcal,
                     proteinG: protein, carbsG: carbs, fatG: fat, loggedAt: date)
    }

    private func mealEntry(_ name: String, _ kcal: Int) -> MealEntry {
        MealEntry(id: UUID().uuidString, foodName: name, portionG: 0, calories: kcal,
                  proteinG: 0, carbsG: 0, fatG: 0, notes: nil)
    }

    private func plan(breakfast: [MealEntry] = [], lunch: [MealEntry] = [], dinner: [MealEntry] = [],
                      snacks: [MealEntry] = []) -> MealPlan {
        let all = breakfast + lunch + dinner + snacks
        return MealPlan(id: "p", date: now, breakfast: breakfast, lunch: lunch, dinner: dinner, snacks: snacks,
                        totalCalories: all.reduce(0) { $0 + $1.calories }, totalProteinG: 0, totalCarbsG: 0,
                        totalFatG: 0, agentNotes: "")
    }

    // MARK: - Snapshot building

    func testSnapshotCountsOnlyTodaysEntries() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let entries = [entry(400, protein: 20.4, carbs: 50, fat: 10.6, at: now.addingTimeInterval(-3600)),
                       entry(300, protein: 10.2, carbs: 30, fat: 5, at: calendar.startOfDay(for: now)),
                       entry(900, at: yesterday), entry(500, at: tomorrow)]
        let s = WidgetSync.makeSnapshot(entries: entries, now: now, calorieGoal: 2000, isKeto: false,
                                        todayPlan: nil, tomorrowPlan: nil, streak: 3)
        XCTAssertEqual(s.caloriesEaten, 700)
        XCTAssertEqual(s.proteinG, 31)   // 30.6 rounded
        XCTAssertEqual(s.carbsG, 80)
        XCTAssertEqual(s.fatG, 16)       // 15.6 rounded
        XCTAssertEqual(s.caloriesLeft, 1300)
        XCTAssertEqual(s.streakDays, 3)
        XCTAssertTrue(s.isFor(now))
    }

    func testSnapshotGoalsFollowHomeMacroSplit() {
        let s = WidgetSync.makeSnapshot(entries: [], now: now, calorieGoal: 2000, isKeto: false,
                                        todayPlan: nil, tomorrowPlan: nil, streak: 0)
        let t = BMRCalculator.macroTargets(calories: 2000)
        XCTAssertEqual(s.calorieGoal, 2000)
        XCTAssertEqual(s.proteinGoalG, t.proteinG)
        XCTAssertEqual(s.carbsGoalG, t.carbsG)
        XCTAssertEqual(s.fatGoalG, t.fatG)

        let keto = WidgetSync.makeSnapshot(entries: [], now: now, calorieGoal: 2000, isKeto: true,
                                           todayPlan: nil, tomorrowPlan: nil, streak: 0)
        XCTAssertEqual(keto.carbsGoalG, BMRCalculator.macroTargets(calories: 2000, isKeto: true).carbsG)

        // No goal yet: no invented targets.
        let none = WidgetSync.makeSnapshot(entries: [], now: now, calorieGoal: 0, isKeto: false,
                                           todayPlan: nil, tomorrowPlan: nil, streak: -2)
        XCTAssertEqual(none.calorieGoal, 0)
        XCTAssertEqual(none.proteinGoalG, 0)
        XCTAssertEqual(none.progress, 0)
        XCTAssertEqual(none.streakDays, 0)
    }

    func testSnapshotMealsSkipEmptySlotsAndKeepOrder() {
        let today = plan(breakfast: [mealEntry("Oats", 400)], lunch: [],
                         dinner: [mealEntry("Salmon", 500), mealEntry("Potatoes", 200)], snacks: [mealEntry("Apple", 80)])
        let meals = WidgetSync.meals(in: today)
        XCTAssertEqual(meals.map(\.slot), ["Breakfast", "Dinner", "Snacks"])
        XCTAssertEqual(meals[1].name, "Salmon, Potatoes")
        XCTAssertEqual(meals[1].kcal, 700)
        XCTAssertTrue(WidgetSync.meals(in: nil).isEmpty)

        let s = WidgetSync.makeSnapshot(entries: [], now: now, calorieGoal: 2000, isKeto: false,
                                        todayPlan: today, tomorrowPlan: plan(lunch: [mealEntry("Soup", 350)]), streak: 0)
        XCTAssertEqual(s.meals.count, 3)
        XCTAssertEqual(s.nextDayMeals?.map(\.name), ["Soup"])
    }

    // MARK: - Snapshot store (what the widgets read)

    func testStoreSavesOnlyWhenChangedAndTurnsOverAtMidnight() {
        let d = defaults()
        let tomorrowPlan = plan(lunch: [mealEntry("Soup", 350)])
        var s = WidgetSync.makeSnapshot(entries: [entry(600, at: now)], now: now, calorieGoal: 2000, isKeto: false,
                                        todayPlan: plan(breakfast: [mealEntry("Oats", 400)]),
                                        tomorrowPlan: tomorrowPlan, streak: 5)
        XCTAssertTrue(NourloSnapshotStore.save(s, to: d))
        XCTAssertFalse(NourloSnapshotStore.save(s, to: d), "unchanged: no widget reload")
        s.caloriesEaten += 1
        XCTAssertTrue(NourloSnapshotStore.save(s, to: d))
        XCTAssertNil(NourloSnapshotStore.load(from: nil), "no App Group: nothing to read")
        XCTAssertFalse(NourloSnapshotStore.save(s, to: nil), "no App Group: nothing written")

        XCTAssertEqual(NourloSnapshotStore.today(from: d, now: now).caloriesEaten, 601)

        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
        let next = NourloSnapshotStore.today(from: d, now: midnight)
        XCTAssertEqual(next.caloriesEaten, 0, "a new day starts at zero")
        XCTAssertEqual(next.calorieGoal, 2000)
        XCTAssertEqual(next.proteinGoalG, s.proteinGoalG)
        XCTAssertEqual(next.streakDays, 5)
        XCTAssertEqual(next.meals.map(\.name), ["Soup"], "tomorrow's plan shows after midnight")

        let later = NourloSnapshotStore.today(from: d, now: calendar.date(byAdding: .day, value: 2, to: now)!)
        XCTAssertTrue(later.meals.isEmpty, "a plan two days old isn't shown")
    }

    func testSameDataLaterTheSameDayDoesNotReload() {
        let d = defaults()
        let entries = [entry(600, at: now)]
        let morning = calendar.date(bySettingHour: 8, minute: 5, second: 0, of: now)!
        let evening = calendar.date(bySettingHour: 21, minute: 40, second: 12, of: now)!
        let first = WidgetSync.makeSnapshot(entries: entries, now: morning, calorieGoal: 2000, isKeto: false,
                                            todayPlan: nil, tomorrowPlan: nil, streak: 2)
        let second = WidgetSync.makeSnapshot(entries: entries, now: evening, calorieGoal: 2000, isKeto: false,
                                             todayPlan: nil, tomorrowPlan: nil, streak: 2)
        XCTAssertEqual(first.date, calendar.startOfDay(for: now), "the snapshot is stamped with its day")
        XCTAssertTrue(NourloSnapshotStore.save(first, to: d))
        XCTAssertFalse(NourloSnapshotStore.save(second, to: d), "same numbers later the same day: no reload")

        // Even a snapshot carrying a time of day doesn't count as a change.
        var timed = second
        timed.date = evening
        XCTAssertFalse(NourloSnapshotStore.save(timed, to: d))

        // A new day is a change, even with the same numbers.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: morning)!
        var nextDay = second
        nextDay.date = tomorrow
        XCTAssertTrue(NourloSnapshotStore.save(nextDay, to: d))
        XCTAssertTrue(NourloSnapshotStore.load(from: d)!.isFor(tomorrow))
    }

    func testOldSnapshotWithoutNextDayMealsStillDecodes() throws {
        let d = defaults()
        let json = """
        {"date":0,"caloriesEaten":10,"calorieGoal":2000,"proteinG":1,"proteinGoalG":2,"carbsG":3,"carbsGoalG":4,\
        "fatG":5,"fatGoalG":6,"meals":[],"streakDays":1}
        """
        d.set(Data(json.utf8), forKey: "nourloSnapshot_v1")
        let loaded = try XCTUnwrap(NourloSnapshotStore.load(from: d))
        XCTAssertEqual(loaded.caloriesEaten, 10)
        XCTAssertNil(loaded.nextDayMeals)
    }

    // MARK: - Wording

    func testFormatting() {
        var s = NourloSnapshot.empty(on: now, goal: 2000)
        s.caloriesEaten = 1380
        XCTAssertEqual(NourloWidgetFormat.inline(s), "620 kcal left")
        XCTAssertEqual(NourloWidgetFormat.caloriesAccessibility(s), "620 calories left. 1380 of 2000 eaten today.")
        s.caloriesEaten = 2120
        XCTAssertEqual(NourloWidgetFormat.headlineNumber(s), 120)
        XCTAssertEqual(NourloWidgetFormat.headlineCaption(s), "kcal over")
        XCTAssertEqual(NourloWidgetFormat.inline(s), "120 kcal over")
        XCTAssertEqual(s.progress, 1)
        s.calorieGoal = 0
        XCTAssertEqual(NourloWidgetFormat.inline(s), "2120 kcal eaten")

        XCTAssertEqual(NourloWidgetFormat.macro(82, of: 140), "82 / 140 g")
        XCTAssertEqual(NourloWidgetFormat.macro(82, of: 0), "82 g")
        XCTAssertEqual(NourloWidgetFormat.fraction(70, of: 140), 0.5)
        XCTAssertEqual(NourloWidgetFormat.fraction(300, of: 140), 1)
        XCTAssertEqual(NourloWidgetFormat.fraction(10, of: 0), 0)
        XCTAssertEqual(NourloWidgetFormat.macroAccessibility("Protein", 82, of: 140), "Protein, 82 of 140 grams")

        let meal = NourloSnapshot.Meal(slot: "Lunch", name: "Chicken rice bowl", kcal: 640)
        XCTAssertEqual(NourloWidgetFormat.mealAccessibility(meal), "Lunch: Chicken rice bowl, 640 calories")
        XCTAssertEqual(NourloWidgetFormat.plannedTotal(NourloSnapshot.placeholder.meals), 1670)
        XCTAssertEqual(NourloWidgetFormat.symbol(forSlot: "Dinner"), "moon.fill")
        XCTAssertEqual(NourloWidgetFormat.symbol(forSlot: "Snacks"), "sparkles")

        XCTAssertEqual(NourloWidgetFormat.stepPosition(index: 1, total: 6), "Exercise 2 of 6")
        XCTAssertEqual(NourloWidgetFormat.stepShort(index: 5, total: 6), "6/6")
        XCTAssertEqual(NourloWidgetFormat.duration(0), "0 min")
        XCTAssertEqual(NourloWidgetFormat.duration(20), "1 min")
        XCTAssertEqual(NourloWidgetFormat.duration(24 * 60), "24 min")
        XCTAssertEqual(NourloWidgetFormat.duration(65 * 60), "1 h 5 min")
        XCTAssertEqual(NourloWidgetFormat.duration(120 * 60), "2 h")
    }

    // MARK: - Session state (Live Activity)

    private func state(steps: Int) -> WorkoutSessionState {
        WorkoutSessionState(id: "s", title: "Legs",
                            steps: (0..<steps).map { .init(name: "Step \($0)", detail: "3 × 10") }, startDate: now)
    }

    func testSessionStateNextStopsAtLastExercise() {
        var s = state(steps: 3)
        XCTAssertEqual(s.current?.name, "Step 0")
        XCTAssertTrue(s.advance())
        XCTAssertTrue(s.advance())
        XCTAssertTrue(s.isLastStep)
        XCTAssertFalse(s.canAdvance)
        XCTAssertFalse(s.advance(), "no step past the last")
        XCTAssertEqual(s.index, 2)
        XCTAssertEqual(s.contentState.exerciseName, "Step 2")
        XCTAssertEqual(s.contentState.total, 3)
        XCTAssertTrue(s.contentState.isLastStep)
    }

    func testSessionStateFinishOnceAndNoNextAfter() {
        var s = state(steps: 3)
        XCTAssertTrue(s.finish(at: now.addingTimeInterval(600)))
        XCTAssertFalse(s.finish(at: now.addingTimeInterval(900)), "finishing twice does nothing")
        XCTAssertEqual(s.finishedAt, now.addingTimeInterval(600))
        XCTAssertFalse(s.advance(), "no Next after Finish")
        XCTAssertTrue(s.contentState.isFinished)
        XCTAssertEqual(s.contentState.endDate, now.addingTimeInterval(600))

        var early = state(steps: 2)
        early.finish(at: now.addingTimeInterval(-60))
        XCTAssertEqual(early.finishedAt, now, "never ends before it started")

        var single = state(steps: 1)
        XCTAssertFalse(single.canAdvance)
        XCTAssertFalse(single.advance())
        XCTAssertTrue(state(steps: 1).isStale(now: now.addingTimeInterval(WorkoutSessionState.maxAge + 1)))
        XCTAssertFalse(state(steps: 1).isStale(now: now.addingTimeInterval(3600)))
    }

    // MARK: - Session controller

    private func workout() -> Workout {
        Workout(title: "Legs", summary: "", kind: .gym, level: .beginner, durationMinutes: 30, warmup: "", cooldown: "",
                exercises: [WorkoutExercise(name: "Squat", sets: 3, reps: "10", minutes: 0, restSeconds: 60, note: ""),
                            WorkoutExercise(name: "Lunge", sets: 3, reps: "8 each side", minutes: 0, restSeconds: 60, note: "")],
                safetyNote: "")
    }

    /// Counts the immediate Health writes a session asks for.
    private final class Counter { var value = 0 }

    private func session(_ d: UserDefaults, _ store: WorkoutStore, counter: Counter = Counter()) -> WorkoutSession {
        WorkoutSession(defaults: d, store: store, weightKg: { 70 }, usesLiveActivities: false,
                       onFinishedOutsideApp: { counter.value += 1 })
    }

    func testSessionStartNextFinishLogsOnce() {
        let d = defaults()
        let store = WorkoutStore(defaults: d)
        let s = session(d, store)
        let w = workout()
        s.start(w, now: now)
        XCTAssertTrue(s.isRunning(w))
        XCTAssertEqual(s.state?.current?.detail, "3 × 10")
        s.next()
        XCTAssertEqual(s.state?.current?.name, "Lunge")
        s.next()
        XCTAssertEqual(s.state?.index, 1, "Next stops at the last exercise")
        s.finish(now: now.addingTimeInterval(1200))
        XCTAssertNil(s.state)
        XCTAssertFalse(s.isRunning(w))
        XCTAssertEqual(s.finishCount, 1)
        XCTAssertEqual(store.completed.count, 1)
        XCTAssertNil(WorkoutSessionStore.load(from: d), "nothing left behind")
        XCTAssertEqual(store.completed.first?.trackedStart, now, "real start recorded")
        XCTAssertEqual(store.completed.first?.trackedEnd, now.addingTimeInterval(1200), "real finish recorded")

        // Starting and finishing it again the same day doesn't log it twice.
        s.start(w, now: now.addingTimeInterval(1500))
        s.finish(now: now.addingTimeInterval(1600))
        XCTAssertEqual(store.completed.count, 1)
        s.finish()
        XCTAssertEqual(s.finishCount, 2, "finish without a session does nothing")
    }

    func testSessionCancelLogsNothingAndEmptyWorkoutDoesNotStart() {
        let d = defaults()
        let store = WorkoutStore(defaults: d)
        let s = session(d, store)
        s.start(workout(), now: now)
        s.cancel()
        XCTAssertNil(s.state)
        XCTAssertTrue(store.completed.isEmpty)

        let empty = Workout(title: "Empty", summary: "", kind: .home, level: .beginner, durationMinutes: 10,
                            warmup: "", cooldown: "", exercises: [], safetyNote: "")
        s.start(empty, now: now)
        XCTAssertNil(s.state)
    }

    func testSessionPicksUpLockScreenChangesAndDropsStaleOnes() throws {
        let d = defaults()
        let store = WorkoutStore(defaults: d)
        let w = workout()
        session(d, store).start(w, now: now)

        // The lock screen's Next changed the stored session; a new launch picks it up.
        var stored = try XCTUnwrap(WorkoutSessionStore.load(from: d))
        stored.advance()
        WorkoutSessionStore.save(stored, to: d)
        let relaunched = session(d, store)
        relaunched.syncFromStore(now: now.addingTimeInterval(60))
        XCTAssertEqual(relaunched.state?.index, 1)
        XCTAssertTrue(relaunched.isRunning(w))

        // Finished from the lock screen while the app was closed: logged on the next launch.
        stored.finish(at: now.addingTimeInterval(900))
        WorkoutSessionStore.save(stored, to: d)
        let promptSyncs = Counter()
        let again = session(d, store, counter: promptSyncs)
        again.syncFromStore(now: now.addingTimeInterval(1000))
        XCTAssertNil(again.state)
        XCTAssertEqual(store.completed.count, 1)
        XCTAssertEqual(store.completed.first?.date, now.addingTimeInterval(900))
        XCTAssertEqual(store.completed.first?.trackedStart, now)
        XCTAssertEqual(store.completed.first?.trackedEnd, now.addingTimeInterval(900))
        XCTAssertEqual(promptSyncs.value, 1, "a lock-screen finish asks for an immediate Health write")
        again.syncFromStore(now: now.addingTimeInterval(1100))
        XCTAssertEqual(store.completed.count, 1, "picked up once")
        XCTAssertEqual(promptSyncs.value, 1)

        // Left running for hours: dropped, not logged.
        let other = WorkoutStore(defaults: defaults("stale"))
        let d2 = defaults("staleSession")
        session(d2, other).start(w, now: now)
        let late = session(d2, other)
        late.syncFromStore(now: now.addingTimeInterval(WorkoutSessionState.maxAge + 60))
        XCTAssertNil(late.state)
        XCTAssertTrue(other.completed.isEmpty)
        XCTAssertNil(WorkoutSessionStore.load(from: d2))
    }

    func testMarkAsDoneIsNotTrackedButALaterSessionAddsItsTimes() {
        let d = defaults()
        let store = WorkoutStore(defaults: d)
        let w = workout()
        XCTAssertTrue(store.complete(w, weightKg: 70, now: now))
        XCTAssertNil(store.completed.first?.trackedStart, "Mark as done: no tracked times")

        let s = session(d, store)
        s.start(w, now: now.addingTimeInterval(600))
        s.finish(now: now.addingTimeInterval(2400))
        XCTAssertEqual(store.completed.count, 1, "still logged once")
        XCTAssertEqual(store.completed.first?.trackedStart, now.addingTimeInterval(600))
        XCTAssertEqual(store.completed.first?.trackedEnd, now.addingTimeInterval(2400))
    }

    func testOldCompletedWorkoutsStillDecode() throws {
        let json = """
        [{"id":"7B1F2C9E-5D4A-4B8B-9C3D-1E2F3A4B5C6D","title":"Walk","kind":"cardio","minutes":30,"calories":120,"date":0}]
        """
        let decoded = try JSONDecoder().decode([CompletedWorkout].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.minutes, 30)
        XCTAssertNil(decoded.first?.trackedStart)
        XCTAssertNil(decoded.first?.trackedEnd)
    }

    // MARK: - Live Activity launch clean-up

    private func content(finished: Bool, endDate: Date?) -> WorkoutActivityAttributes.ContentState {
        .init(exerciseName: "Squat", detail: "3 × 10", index: 0, total: 2, startDate: now,
              isFinished: finished, endDate: endDate)
    }

    func testLaunchKeepsWorkoutDoneCardUntilItsDismissalTime() {
        let finishedAt = now.addingTimeInterval(1200)
        let done = content(finished: true, endDate: finishedAt)
        let until = finishedAt.addingTimeInterval(WorkoutActivityControl.finishedDismissal)

        XCTAssertEqual(WorkoutActivityControl.launchCleanup(sessionID: "a", content: done, isEnded: false,
                                                            keeping: nil, now: finishedAt.addingTimeInterval(120)),
                       .endShowingDone(until: until), "relaunch 2 min later keeps the card")
        XCTAssertEqual(WorkoutActivityControl.launchCleanup(sessionID: "a", content: done, isEnded: true,
                                                            keeping: nil, now: finishedAt.addingTimeInterval(120)),
                       .keep, "already ended: its dismissal time stands")
        XCTAssertEqual(WorkoutActivityControl.launchCleanup(sessionID: "a", content: done, isEnded: false,
                                                            keeping: nil, now: until.addingTimeInterval(1)),
                       .endNow, "past its dismissal time")
        let running = content(finished: false, endDate: nil)
        XCTAssertEqual(WorkoutActivityControl.launchCleanup(sessionID: "a", content: running, isEnded: false,
                                                            keeping: "a", now: now), .keep, "the running session")
        XCTAssertEqual(WorkoutActivityControl.launchCleanup(sessionID: "b", content: running, isEnded: false,
                                                            keeping: "a", now: now), .endNow, "an unknown session")
    }
}
