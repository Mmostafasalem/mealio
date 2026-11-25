import XCTest
@testable import smartmarket

/// The features chosen in onboarding ("What do you want Nourlo for?") and
/// Profile › Features: storage, defaults for earlier users, and what each
/// choice shows (tabs, quick actions, onboarding steps, quests, guide).
@MainActor
final class FeatureChoiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "FeatureChoiceTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: Storage and migration

    func testStorageKeyIsVersioned() {
        XCTAssertEqual(Constants.Storage.enabledFeatures, "enabledFeatures_v1")
    }

    func testNothingStoredMeansEveryFeature() {
        // People who finished onboarding before the choice existed have no key: no change for them.
        XCTAssertNil(defaults.string(forKey: Constants.Storage.enabledFeatures))
        XCTAssertEqual(AppFeature.load(from: defaults), AppFeature.all)
    }

    func testUnreadableOrEmptyValueMeansEveryFeature() {
        XCTAssertEqual(AppFeature.decode(""), AppFeature.all)
        XCTAssertEqual(AppFeature.decode("nonsense,more"), AppFeature.all)
        XCTAssertEqual(AppFeature.decode(nil), AppFeature.all)
    }

    func testSaveAndLoadRoundTrip() {
        AppFeature.save([.workouts, .tracking], to: defaults)
        XCTAssertEqual(defaults.string(forKey: Constants.Storage.enabledFeatures), "tracking,workouts")
        XCTAssertEqual(AppFeature.load(from: defaults), [.tracking, .workouts])
    }

    func testUnknownNamesAreIgnored() {
        XCTAssertEqual(AppFeature.decode("workouts, flying"), [.workouts])
    }

    func testEmptyChoiceIsNeverSaved() {
        AppFeature.save([.meals], to: defaults)
        AppFeature.save([], to: defaults)
        XCTAssertEqual(AppFeature.load(from: defaults), [.meals])
    }

    func testAppStateKeepsAtLeastOneFeature() {
        let saved = UserDefaults.standard.string(forKey: Constants.Storage.enabledFeatures)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: Constants.Storage.enabledFeatures) }
            else { UserDefaults.standard.removeObject(forKey: Constants.Storage.enabledFeatures) }
            AppState.shared.reloadStoredData()
        }
        let state = AppState.shared
        state.setEnabledFeatures([.workouts])
        XCTAssertEqual(state.enabledFeatures, [.workouts])
        XCTAssertEqual(AppFeature.load(), [.workouts])
        state.setFeature(.workouts, enabled: false)
        XCTAssertEqual(state.enabledFeatures, [.workouts], "the last feature stays on")
        state.setFeature(.meals, enabled: true)
        XCTAssertEqual(state.enabledFeatures, [.workouts, .meals])
        XCTAssertTrue(state.isEnabled(.meals))
        XCTAssertFalse(state.isEnabled(.tracking))
    }

    func testFinishingOnboardingSavesTheChoice() {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        let profile = KeychainHelper.load(key: Constants.Storage.userProfile)
        let bmr = KeychainHelper.load(key: Constants.Storage.bmrResponse)
        defer {
            AppState.shared.agentLoop.stop()
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            if let profile { KeychainHelper.save(profile, key: Constants.Storage.userProfile) }
            else { KeychainHelper.delete(key: Constants.Storage.userProfile) }
            if let bmr { KeychainHelper.save(bmr, key: Constants.Storage.bmrResponse) }
            else { KeychainHelper.delete(key: Constants.Storage.bmrResponse) }
            AppState.shared.reloadStoredData()
        }
        let vm = OnboardingViewModel()
        vm.offersAI = false
        XCTAssertEqual(vm.features, AppFeature.all, "every feature starts on")
        vm.toggleFeature(.tracking)
        vm.toggleFeature(.meals)
        vm.toggleFeature(.groceries)
        XCTAssertEqual(vm.features, [.workouts])
        vm.finish()
        XCTAssertEqual(AppState.shared.enabledFeatures, [.workouts])
        XCTAssertEqual(UserDefaults.standard.string(forKey: Constants.Storage.enabledFeatures), "workouts")
    }

    // MARK: Tabs

    func testEveryFeatureKeepsTodaysTabBar() {
        XCTAssertEqual(FeatureLayout.tabs(for: AppFeature.all), [.home, .meals, .quickActions, .shop, .train])
        XCTAssertEqual(FeatureLayout.tabs(for: AppFeature.all).map(\.name), ["Home", "Meals", "Quick actions", "Shop", "Train"])
    }

    func testWorkoutsOnlyShowsHomeAndTrain() {
        XCTAssertEqual(FeatureLayout.tabs(for: [.workouts]), [.home, .quickActions, .train])
    }

    func testTrackingOnlyShowsHomeAlone() {
        XCTAssertEqual(FeatureLayout.tabs(for: [.tracking]), [.home, .quickActions])
    }

    func testTabsForOtherChoices() {
        XCTAssertEqual(FeatureLayout.tabs(for: [.meals, .groceries]), [.home, .meals, .quickActions, .shop])
        XCTAssertEqual(FeatureLayout.tabs(for: [.groceries, .tracking]), [.home, .quickActions, .shop])
        XCTAssertEqual(FeatureLayout.tabs(for: [.meals, .workouts]), [.home, .meals, .quickActions, .train])
    }

    func testTabTagsStayFixed() {
        XCTAssertEqual(AppTab.home.rawValue, 0)
        XCTAssertEqual(AppTab.meals.rawValue, 1)
        XCTAssertEqual(AppTab.shop.rawValue, 2)
        XCTAssertEqual(AppTab.train.rawValue, 3)
        XCTAssertEqual(AppTab.quickActions.rawValue, 4)
    }

    // MARK: Quick actions

    func testEveryFeatureKeepsAllQuickActions() {
        XCTAssertEqual(FeatureLayout.quickActionIDs(for: AppFeature.all),
                       ["voice", "mealPhoto", "logFood", "cart", "groceries", "chat", "profile"])
    }

    func testQuickActionsFollowTheChoice() {
        XCTAssertEqual(FeatureLayout.quickActionIDs(for: [.workouts]), ["voice", "chat", "profile"])
        XCTAssertEqual(FeatureLayout.quickActionIDs(for: [.meals]), ["chat", "profile"])
        XCTAssertEqual(FeatureLayout.quickActionIDs(for: [.tracking]), ["voice", "mealPhoto", "logFood", "chat", "profile"])
        XCTAssertEqual(FeatureLayout.quickActionIDs(for: [.groceries]), ["voice", "cart", "groceries", "chat", "profile"])
    }

    func testLinksAndActionsNameTheirFeature() {
        XCTAssertNil(FeatureLayout.feature(for: NourloLink.home))
        XCTAssertEqual(FeatureLayout.feature(for: NourloLink.logFood), .tracking)
        XCTAssertEqual(FeatureLayout.feature(for: NourloLink.scan), .tracking)
        XCTAssertEqual(FeatureLayout.feature(for: NourloLink.meals), .meals)
        XCTAssertEqual(FeatureLayout.feature(for: NourloLink.groceries), .groceries)
        XCTAssertEqual(FeatureLayout.feature(for: NourloLink.train), .workouts)
        XCTAssertEqual(FeatureLayout.feature(for: MealioQuickAction.cart), .groceries)
        XCTAssertNil(FeatureLayout.feature(for: MealioQuickAction.profile))
    }

    func testStockStaysWithMealsOrGroceries() {
        XCTAssertTrue(FeatureLayout.showsStock([.meals]), "meal planning uses the stock, so it stays reachable")
        XCTAssertTrue(FeatureLayout.showsStock([.groceries]))
        XCTAssertFalse(FeatureLayout.showsStock([.tracking, .workouts]))
    }

    // MARK: Onboarding steps

    func testEveryFeatureAsksTenQuestions() {
        let vm = OnboardingViewModel()
        vm.offersAI = false
        XCTAssertEqual(vm.steps, [.name, .features, .height, .weight, .activity, .goal, .diet, .favorites, .week, .alerts])
        XCTAssertEqual(vm.totalSteps, 10)
        XCTAssertEqual(vm.number(of: .name), 1)
        XCTAssertEqual(vm.number(of: .features), 2)
        XCTAssertEqual(vm.number(of: .favorites), 8)
        XCTAssertEqual(vm.step(after: .favorites), .week)
        XCTAssertNil(vm.step(after: .alerts), "reminders and Health always end onboarding")
    }

    func testPaceSharesTheGoalsNumber() {
        let vm = OnboardingViewModel()
        vm.offersAI = false
        vm.weightGoal = .lose
        XCTAssertEqual(vm.steps, [.name, .features, .height, .weight, .activity, .goal, .pace, .diet, .favorites, .week, .alerts])
        XCTAssertEqual(vm.totalSteps, 10)
        XCTAssertEqual(vm.number(of: .pace), vm.number(of: .goal))
        XCTAssertEqual(vm.step(after: .goal), .pace)
        XCTAssertEqual(vm.step(after: .pace), .diet)
    }

    func testWorkoutsOnlySkipsFoodQuestions() {
        // Body stats and the goal still matter: calorie estimates and Train's focus.
        XCTAssertEqual(FeatureLayout.onboardingSteps(for: [.workouts], losingWeight: true),
                       [.name, .features, .height, .weight, .activity, .goal, .alerts])
        let vm = OnboardingViewModel()
        vm.offersAI = false
        vm.features = [.workouts]
        XCTAssertEqual(vm.step(after: .goal), .alerts)
        XCTAssertEqual(vm.totalSteps, 7)
    }

    func testGroceriesOnlySkipsBodyQuestions() {
        XCTAssertEqual(FeatureLayout.onboardingSteps(for: [.groceries], losingWeight: false),
                       [.name, .features, .diet, .favorites, .week, .alerts])
    }

    func testTrackingOnlySkipsFavourites() {
        XCTAssertEqual(FeatureLayout.onboardingSteps(for: [.tracking], losingWeight: true),
                       [.name, .features, .height, .weight, .activity, .goal, .pace, .diet, .week, .alerts])
    }

    func testMealsKeepsFavourites() {
        XCTAssertEqual(FeatureLayout.onboardingSteps(for: [.meals], losingWeight: false),
                       [.name, .features, .height, .weight, .activity, .goal, .diet, .favorites, .week, .alerts])
    }

    func testRemindersFollowTheChoice() {
        XCTAssertTrue(FeatureLayout.offersReminder(.workout, [.workouts]))
        XCTAssertFalse(FeatureLayout.offersReminder(.breakfast, [.workouts]))
        XCTAssertTrue(FeatureLayout.offersReminder(.breakfast, [.tracking]))
        XCTAssertFalse(FeatureLayout.offersReminder(.workout, [.tracking, .meals]))
    }

    func testNoFeatureCannotContinue() {
        let vm = OnboardingViewModel()
        vm.offersAI = false
        AppFeature.allCases.forEach(vm.toggleFeature)
        XCTAssertTrue(vm.features.isEmpty)
        XCTAssertFalse(vm.canContinueFromFeatures)
    }

    // MARK: Quests and guide

    func testQuestsFollowTheChoice() {
        var inputs = LoopFixture.inputs(cartHasItems: true, hasStock: true)
        XCTAssertTrue(DailyLoop.available(day: LoopFixture.day(), inputs).contains(.logAny))

        inputs.features = [.workouts]
        let workoutsOnly = DailyLoop.available(day: LoopFixture.day(), inputs)
        XCTAssertEqual(Set(workoutsOnly), [.workout, .anyWorkout], "workout quests every day without tracking")
        XCTAssertTrue(DailyLoop.pickQuests(for: LoopFixture.day(), inputs).allSatisfy { [.workout, .anyWorkout].contains($0) })

        inputs.features = [.tracking]
        let trackingOnly = DailyLoop.available(day: LoopFixture.day(), inputs)
        XCTAssertFalse(trackingOnly.contains(.budget))
        XCTAssertFalse(trackingOnly.contains(.fromStock))
        XCTAssertFalse(trackingOnly.contains(.workout))
    }

    func testTodaysPickIsRedoneWhenItsFeatureIsTurnedOff() {
        let day = LoopFixture.day()
        var inputs = LoopFixture.inputs(ledger: [.questsChosen(day, [.logAny, .workout, .budget])])
        XCTAssertEqual(DailyLoop.chosenQuests(day: day, inputs), [.logAny, .workout, .budget])
        inputs.features = [.tracking]
        XCTAssertNil(DailyLoop.chosenQuests(day: day, inputs))
        XCTAssertTrue(DailyLoop.quests(for: day, inputs).allSatisfy { FeatureLayout.allows($0.id, [.tracking]) })
    }

    func testGuideFollowsTheChoice() {
        XCTAssertEqual(BowlTourStep.steps(for: AppFeature.all).map(\.title),
                       ["Start with one meal", "Build your grocery list", "Make room for a plan"])
        XCTAssertEqual(BowlTourStep.pathways(for: AppFeature.all), [.logFood, .groceries, .meals])
        XCTAssertEqual(BowlTourStep.steps(for: [.workouts]).map(\.action), [.train])
        XCTAssertEqual(BowlTourStep.pathways(for: [.workouts]), [.train])
        XCTAssertEqual(BowlTourStep.pathways(for: [.meals, .tracking]), [.logFood, .meals])
    }
}

@MainActor
final class AccountStepTests: XCTestCase {
    func testAccountStepOnlyWhenOnlineAIIsOffered() {
        let without = FeatureLayout.onboardingSteps(for: AppFeature.all, losingWeight: false)
        XCTAssertFalse(without.contains(.account))
        let with = FeatureLayout.onboardingSteps(for: AppFeature.all, losingWeight: false, offersAI: true)
        XCTAssertEqual(Array(with.suffix(2)), [.account, .alerts], "just before reminders and Health")
    }
}
