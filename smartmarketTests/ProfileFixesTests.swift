import XCTest
@testable import smartmarket

/// Profile / onboarding fixes: shared calorie targets, safety floor, minors,
/// onboarding navigation, ruler conversions and Delete All Data store resets.
@MainActor
final class ProfileFixesTests: XCTestCase {

    // MARK: - Safety floor only on weight loss

    func testFloorAppliesOnlyToWeightLoss() {
        // A small, sedentary person whose maintenance is below the floor.
        let tdee = 1100.0
        XCTAssertEqual(BMRCalculator.dailyGoal(tdee: tdee, goal: .maintain, pace: .medium, gender: .male), 1100)
        XCTAssertEqual(BMRCalculator.dailyGoal(tdee: tdee, goal: .gain, pace: .medium, gender: .male),
                       1100 + Constants.Calories.gainSurplus)
        // Losing never goes above maintenance, even when the floor is higher.
        XCTAssertEqual(BMRCalculator.dailyGoal(tdee: tdee, goal: .lose, pace: .fast, gender: .male), 1100)
    }

    func testLossFloorStillHolds() {
        let goal = BMRCalculator.dailyGoal(tdee: 1600, goal: .lose, pace: .fast, gender: .female)
        XCTAssertEqual(goal, Constants.Calories.minimumFemale)
        XCTAssertEqual(BMRCalculator.effectiveDeficit(tdee: 1600, pace: .fast, gender: .female), 400)
        XCTAssertTrue(BMRCalculator.isCappedBySafetyFloor(tdee: 1600, pace: .fast, gender: .female))
        XCTAssertFalse(BMRCalculator.isCappedBySafetyFloor(tdee: 1600, pace: .slow, gender: .female))
        XCTAssertEqual(BMRCalculator.effectiveDeficit(tdee: 1600, pace: .slow, gender: .female), LossPace.slow.dailyDeficit)
    }

    // MARK: - Under 18

    func testUnderEighteenNeverGetsADeficit() {
        for age in [13, 15, 17] {
            let lose = BMRCalculator.dailyGoal(tdee: 2400, goal: .lose, pace: .fast, gender: .female, age: age)
            XCTAssertEqual(lose, 2400, "age \(age)")
            XCTAssertEqual(BMRCalculator.effectiveDeficit(tdee: 2400, pace: .fast, gender: .female, age: age), 0)
            XCTAssertFalse(BMRCalculator.isCappedBySafetyFloor(tdee: 2400, pace: .fast, gender: .female, age: age))
        }
        XCTAssertLessThan(BMRCalculator.dailyGoal(tdee: 2400, goal: .lose, pace: .fast, gender: .female, age: 18), 2400)
    }

    func testStoredMinorLosingProfileIsTreatedAsMaintain() {
        var profile = UserProfile()
        profile.age = 15
        profile.weightGoal = .lose
        profile.lossPace = .fast
        BMRCalculator.populate(profile: &profile)
        XCTAssertEqual(profile.weightGoal, .maintain)
        XCTAssertEqual(profile.dailyCalorieGoal, Int(profile.tdee))
        let response = BMRCalculator.response(for: profile, isKeto: false)
        XCTAssertEqual(response.loseCalories, response.maintainCalories)
    }

    func testOnboardingHidesWeightLossForMinors() {
        let vm = OnboardingViewModel()
        vm.age = 16
        vm.weightGoal = .lose
        XCTAssertFalse(vm.availableGoals.contains(.lose))
        vm.normalizeGoalForAge()
        XCTAssertEqual(vm.weightGoal, .maintain)
        vm.age = 30
        XCTAssertTrue(vm.availableGoals.contains(.lose))
        XCTAssertEqual(Constants.Onboarding.minimumAge, 13)
    }

    // MARK: - Live goal equals saved goal

    func testLiveGoalEqualsSavedGoal() {
        let cases: [(Double, Double, Int, Gender, ActivityLevel, WeightGoal, LossPace)] = [
            (70, 170, 25, .male, .moderatelyActive, .maintain, .medium),
            (45, 150, 60, .female, .sedentary, .maintain, .medium),
            (45, 150, 60, .female, .sedentary, .lose, .fast),
            (52.5, 158, 34, .other, .lightlyActive, .lose, .medium),
            (95.5, 188, 41, .male, .veryActive, .gain, .slow),
            (61, 165, 16, .female, .superActive, .lose, .fast),
            (83.25, 177, 29, .male, .lightlyActive, .lose, .slow),
        ]
        for (w, h, a, g, act, goal, pace) in cases {
            let label = "\(w) \(h) \(a) \(g) \(goal)"
            // Onboarding: the live number on screen vs the profile finish() saves.
            let onboarding = OnboardingViewModel()
            onboarding.weight = w; onboarding.height = h; onboarding.age = a; onboarding.gender = g
            onboarding.activityLevel = act; onboarding.weightGoal = goal; onboarding.lossPace = pace
            let finished = onboarding.makeProfile()
            XCTAssertEqual(onboarding.liveDailyGoal, finished.dailyCalorieGoal, label)
            XCTAssertEqual(onboarding.liveTDEE, Int(finished.tdee), label)
            XCTAssertEqual(onboarding.liveBMR, Int(finished.bmr), label)
            XCTAssertEqual(finished.weightGoal, a < 18 && goal == .lose ? .maintain : goal, label)

            // Profile: the live targets Edit Goal shows vs what save() stores.
            let profileVM = ProfileViewModel()
            var edited = UserProfile()
            edited.weight = w; edited.height = h; edited.age = a; edited.gender = g
            edited.activityLevel = act; edited.weightGoal = goal; edited.lossPace = pace
            profileVM.profile = edited
            let live = profileVM.targets()
            let saved = ProfileViewModel.prepared(edited)
            XCTAssertEqual(live.dailyGoal, saved.dailyCalorieGoal, label)
            XCTAssertEqual(live.tdee.rounded(), saved.tdee, label)
            XCTAssertEqual(live.bmr.rounded(), saved.bmr, label)
            // Both paths save the same profile.
            XCTAssertEqual(saved.dailyCalorieGoal, finished.dailyCalorieGoal, label)

            // The planner reads the same number back for the saved goal.
            let response = BMRCalculator.response(for: saved, isKeto: false)
            XCTAssertEqual(response.calories(forGoal: saved.weightGoal.rawValue), saved.dailyCalorieGoal, label)
        }
    }

    // MARK: - Onboarding navigation

    func testAdvanceIgnoresRepeatedAndStaleSteps() {
        let vm = OnboardingViewModel()
        vm.advance(to: .gender)
        vm.advance(to: .gender)            // double tap on Next
        XCTAssertEqual(vm.path, [.gender])
        vm.advance(to: .age)
        vm.advance(to: .gender)            // stale tap from the previous screen
        XCTAssertEqual(vm.path, [.gender, .age])
        vm.path = [.gender, .age, .height, .weight, .activity, .goal]
        vm.advance(to: .diet)              // pace is skipped when not losing
        XCTAssertEqual(vm.path.last, .diet)
        vm.path.removeLast()               // back to goal, then choose lose
        vm.advance(to: .pace)
        vm.advance(to: .pace)
        XCTAssertEqual(vm.path.suffix(2), [.goal, .pace])
    }

    // MARK: - Ruler conversions

    func testUntouchedRulerWritesNothing() {
        // Same tick: nothing to write, so a stored 70.0 kg isn't rounded through pounds.
        let lb = WeightRuler.pounds(fromKilograms: 70)
        let range = WeightRuler.poundRange(WeightRuler.defaultRange)
        XCTAssertNil(RulerMath.newValue(current: lb, targetTick: Int(lb), range: range, step: 1))
        XCTAssertEqual(RulerMath.newValue(current: lb, targetTick: Int(lb) + 1, range: range, step: 1), lb + 1)
        // At the ends, a step past the limit writes nothing.
        let low = range.lowerBound
        XCTAssertNil(RulerMath.newValue(current: low, targetTick: Int(low) - 1, range: range, step: 1))
    }

    func testPoundsRoundTripDoesNotDrift() {
        for lb in stride(from: 66.0, through: 661.0, by: 1) {
            let kg = WeightRuler.kilograms(fromPounds: lb)
            XCTAssertEqual(WeightRuler.pounds(fromKilograms: kg), lb, "lb \(lb)")
            // Repeated get/set stays put.
            let again = WeightRuler.kilograms(fromPounds: WeightRuler.pounds(fromKilograms: kg))
            XCTAssertEqual(again, kg, accuracy: 1e-9)
        }
    }

    func testInchesRoundTripDoesNotDrift() {
        for inch in stride(from: 39.0, through: 98.0, by: 1) {
            let cm = HeightRuler.centimetres(fromInches: inch)
            XCTAssertEqual(HeightRuler.inches(fromCentimetres: cm), inch, "in \(inch)")
            XCTAssertEqual(HeightRuler.centimetres(fromInches: HeightRuler.inches(fromCentimetres: cm)), cm)
        }
    }

    func testRangesCoverRealUsersAndReadoutsAgreeAtTheEnds() {
        XCTAssertEqual(WeightRuler.defaultRange, 30...300)
        XCTAssertEqual(HeightRuler.defaultRange, 100...250)
        let lb = WeightRuler.poundRange(WeightRuler.defaultRange)
        XCTAssertEqual(WeightRuler.number(30, .lb), String(format: "%.0f", lb.lowerBound))
        XCTAssertEqual(WeightRuler.number(300, .lb), String(format: "%.0f", lb.upperBound))
        let inch = HeightRuler.inchRange(HeightRuler.defaultRange)
        XCTAssertEqual(HeightRuler.text(100, .ft), HeightUnit.feetAndInches(inch.lowerBound))
        XCTAssertEqual(HeightRuler.text(250, .ft), HeightUnit.feetAndInches(inch.upperBound))
        // The ends of each display range convert back inside the metric range.
        XCTAssertTrue(WeightRuler.defaultRange.contains(WeightRuler.kilograms(fromPounds: lb.lowerBound)))
        XCTAssertTrue(WeightRuler.defaultRange.contains(WeightRuler.kilograms(fromPounds: lb.upperBound)))
        XCTAssertTrue(HeightRuler.defaultRange.contains(HeightRuler.centimetres(fromInches: inch.lowerBound)))
        XCTAssertTrue(HeightRuler.defaultRange.contains(HeightRuler.centimetres(fromInches: inch.upperBound)))
    }

    // MARK: - Profile saving

    func testSaveWithoutChangesDoesNothing() {
        // A saved (already computed) profile, not whatever the Keychain holds.
        var stored = UserProfile()
        stored.weight = 64; stored.height = 168; stored.age = 33; stored.gender = .female
        stored.weightGoal = .lose; stored.lossPace = .slow
        BMRCalculator.populate(profile: &stored)
        let vm = ProfileViewModel()
        vm.load(profile: stored, preferences: [.vegetarian], favorites: ["milk"])
        var posted = false
        let token = NotificationCenter.default.addObserver(forName: .personalDataDidChange, object: nil, queue: nil) { _ in
            posted = true
        }
        defer { NotificationCenter.default.removeObserver(token) }
        XCTAssertFalse(vm.save())
        XCTAssertFalse(posted)
        XCTAssertEqual(vm.profile, stored)
    }

    // MARK: - Targets migration

    func testTargetsMigrationRunsOnlyForOnboardedOldVersions() {
        let defaults = UserDefaults.standard
        let keys = [Constants.Storage.hasCompletedOnboarding, Constants.Storage.targetsVersion]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }

        defaults.set(false, forKey: Constants.Storage.hasCompletedOnboarding)
        defaults.removeObject(forKey: Constants.Storage.targetsVersion)
        XCTAssertFalse(UserProfile.needsTargetsMigration, "Nothing to migrate before onboarding")
        defaults.set(true, forKey: Constants.Storage.hasCompletedOnboarding)
        XCTAssertTrue(UserProfile.needsTargetsMigration)
        UserProfile.markTargetsCurrent()
        XCTAssertFalse(UserProfile.needsTargetsMigration, "Runs once")
        defaults.set(1, forKey: Constants.Storage.targetsVersion)
        XCTAssertTrue(UserProfile.needsTargetsMigration)
    }

    func testOldAdultTargetsAreRecomputedWithCurrentMaths() {
        // Saved under the old maths: a floor on maintain raised the goal.
        var old = UserProfile()
        old.weight = 40; old.height = 150; old.age = 70; old.gender = .female
        old.activityLevel = .sedentary; old.weightGoal = .maintain
        BMRCalculator.populate(profile: &old)
        let current = old.dailyCalorieGoal
        old.dailyCalorieGoal = Constants.Calories.minimumFemale
        XCTAssertLessThan(current, Constants.Calories.minimumFemale, "No floor on maintain")
        XCTAssertEqual(ProfileViewModel.prepared(old).dailyCalorieGoal, current)
    }

    // MARK: - Delete All Data: in-memory stores

    func testRecipeRatingsReloadAfterErase() {
        let suite = "ProfileFixesTests-ratings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecipeRatingStore(defaults: defaults)
        store.setRating(4, for: "Soup")
        defaults.removePersistentDomain(forName: suite)   // what Delete All Data does
        store.reload()
        XCTAssertEqual(store.rating(for: "Soup"), 0)
        store.setRating(5, for: "Salad")
        let stored = defaults.dictionary(forKey: "recipeRatings_v1") as? [String: Int]
        XCTAssertEqual(stored, ["salad": 5], "the erased rating must not be written back")
    }

    func testDailyLoopResetDropsMemoryState() {
        let suite = "ProfileFixesTests-loop-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = LoopSource(foodEntries: [LoopFixture.food(slot: .breakfast)], stockEntryIDs: [],
                                workouts: [LoopFixture.workout()], calorieGoal: 2000, proteinGoal: 90,
                                cartHasItems: false, cartWithinBudget: false, hasStock: false)
        let store = DailyLoopStore(defaults: defaults, calendar: LoopFixture.calendar, source: { source })
        store.refresh(now: LoopFixture.date())
        XCTAssertFalse(store.ledger.isEmpty)
        XCTAssertNotNil(store.lastCompletion)

        defaults.removePersistentDomain(forName: suite)
        store.reset()
        XCTAssertTrue(store.ledger.isEmpty)
        XCTAssertNil(store.lastCompletion)
        XCTAssertNil(store.pendingMilestone)
        XCTAssertEqual(store.state, LoopState())
    }

    func testDailyLoopWritesNothingWhileNotOnboarded() {
        let suite = "ProfileFixesTests-loop-off-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = LoopSource(foodEntries: [LoopFixture.food(slot: .breakfast)], stockEntryIDs: [],
                                workouts: [LoopFixture.workout()], calorieGoal: 2000, proteinGoal: 90,
                                cartHasItems: true, cartWithinBudget: true, hasStock: false)
        var onboarded = false
        let store = DailyLoopStore(defaults: defaults, calendar: LoopFixture.calendar, source: { source },
                                   isActive: { onboarded })
        // What Delete All Data's cart reset triggers after the erase.
        store.cartChanged(now: LoopFixture.date())
        store.refresh(now: LoopFixture.date())
        _ = store.stateForNudge(now: LoopFixture.date())
        XCTAssertNil(defaults.data(forKey: DailyLoopStore.key), "Nothing written while not onboarded")
        XCTAssertTrue(store.ledger.isEmpty)
        store.reset()
        XCTAssertTrue(store.ledger.isEmpty)
        XCTAssertEqual(store.state, LoopState())

        onboarded = true
        store.refresh(now: LoopFixture.date())
        XCTAssertFalse(store.ledger.isEmpty, "Normal behaviour once onboarded")
        XCTAssertNotNil(defaults.data(forKey: DailyLoopStore.key))
    }
}
