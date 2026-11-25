import SwiftUI
import Observation

/// Single shared view model for the entire onboarding flow.
@Observable
final class OnboardingViewModel {

    // MARK: - Navigation
    var path: [OnboardingStep] = []

    // MARK: - Features (what Nourlo is for); all on until the person changes them
    var features: Set<AppFeature> = AppFeature.all

    func toggleFeature(_ feature: AppFeature) {
        if features.contains(feature) { features.remove(feature) } else { features.insert(feature) }
    }

    var canContinueFromFeatures: Bool { !features.isEmpty }

    /// Whether the online AI account step is shown; nil asks the account service
    /// (tests set it so the screen count doesn't depend on the server).
    var offersAI: Bool? = nil

    /// The screens these features need, in order (`pace` only when losing weight).
    var steps: [OnboardingStep] {
        FeatureLayout.onboardingSteps(for: features, losingWeight: weightGoal == .lose,
                                      offersAI: offersAI ?? AIAccountService.shared.offersOnlineAI)
    }

    /// The screen after `step`, or nil when `step` is the last one.
    func step(after step: OnboardingStep) -> OnboardingStep? {
        let steps = steps
        guard let index = steps.firstIndex(of: step) else {
            // A screen these features don't use: the next one that is used.
            return steps.first { $0.rawValue > step.rawValue }
        }
        return steps.indices.contains(index + 1) ? steps[index + 1] : nil
    }

    /// Screens counted in "3 / 8". `pace` shares the goal's number.
    var totalSteps: Int { steps.filter { $0 != .pace }.count }

    /// 1-based number shown for `step`.
    func number(of step: OnboardingStep) -> Int {
        let counted = steps.filter { $0 != .pace }
        let key: OnboardingStep = step == .pace ? .goal : step
        return (counted.firstIndex(of: key) ?? max(counted.count - 1, 0)) + 1
    }

    func progress(of step: OnboardingStep) -> CGFloat {
        CGFloat(number(of: step)) / CGFloat(max(totalSteps, 1))
    }

    // MARK: - Step 1: Body stats
    var firstName: String        = ""
    var lastName: String         = ""
    var weight: Double           = 70.0
    var height: Double           = 170.0
    var age: Int                 = 25
    var gender: Gender           = .male
    var activityLevel: ActivityLevel = .moderatelyActive

    // MARK: - Step 2: Goal
    var weightGoal: WeightGoal = .maintain
    var lossPace: LossPace     = .medium

    // MARK: - Step 3: Dietary preferences
    var selectedPreferences: Set<DietaryPreference> = []

    // MARK: - Step 4: Favorite foods (static catalog, no network required)
    var favoriteFoodIDs: Set<String> = []
    var selectedCategory: CatalogCategory? = nil   // nil = show all
    var foodSearchQuery: String = "" {
        didSet { scheduleFilter() }
    }
    private(set) var filteredItems: [CatalogItem] = CatalogItem.all
    @ObservationIgnored private var filterTask: Task<Void, Never>?

    // MARK: - Live computed values (local Mifflin-St Jeor; no network)
    // The same calculation `finish()` saves, so the number shown is the one saved.
    func liveTargets(goal: WeightGoal? = nil, pace: LossPace? = nil) -> BMRCalculator.Targets {
        BMRCalculator.targets(weight: weight, height: height, age: age, gender: gender,
                              activityLevel: activityLevel, goal: goal ?? weightGoal, pace: pace ?? lossPace)
    }

    var liveBMR: Int { Int(liveTargets().bmr.rounded()) }

    var liveTDEE: Int { Int(liveTargets().tdee.rounded()) }

    var liveDailyGoal: Int { liveTargets().dailyGoal }

    /// Under-18s are offered maintain or gain only.
    var allowsWeightLoss: Bool { BMRCalculator.allowsWeightLoss(age: age) }

    var availableGoals: [WeightGoal] {
        allowsWeightLoss ? WeightGoal.allCases : WeightGoal.allCases.filter { $0 != .lose }
    }

    /// Moves a weight-loss goal to maintain when the age no longer allows it.
    func normalizeGoalForAge() {
        weightGoal = BMRCalculator.effectiveGoal(weightGoal, age: age)
    }

    /// The deficit a pace will actually apply, after the safety floor.
    func effectiveDeficit(for pace: LossPace) -> Int {
        BMRCalculator.effectiveDeficit(tdee: liveTargets().tdee, pace: pace, gender: gender, age: age)
    }

    func isCappedBySafetyFloor(_ pace: LossPace) -> Bool {
        BMRCalculator.isCappedBySafetyFloor(tdee: liveTargets().tdee, pace: pace, gender: gender, age: age)
    }

    /// The selected pace is limited by the minimum safe calories.
    var isBelowSafeFloor: Bool { weightGoal == .lose && isCappedBySafetyFloor(lossPace) }

    // MARK: - Catalog filtering (synchronous — catalog is static)

    func applyFilter(category: CatalogCategory?) {
        selectedCategory = category
        scheduleFilter()
    }

    private func scheduleFilter() {
        filterTask?.cancel()
        filterTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            let q    = foodSearchQuery.lowercased()
            var base = CatalogItem.all
            if let cat = selectedCategory { base = base.filter { $0.category == cat } }
            if !q.isEmpty { base = base.filter { $0.name.lowercased().contains(q) } }
            filteredItems = base
        }
    }

    var favoritesCount: Int { favoriteFoodIDs.count }
    var canFinish: Bool { favoritesCount >= Constants.Onboarding.minimumFavorites }

    /// Picks every food in `items`, or clears them all when they are all picked already.
    func toggleAll(_ items: [CatalogItem]) {
        let ids = Set(items.map(\.id))
        if ids.isSubset(of: favoriteFoodIDs) { favoriteFoodIDs.subtract(ids) } else { favoriteFoodIDs.formUnion(ids) }
    }

    /// Goes to the screen after `step`, or finishes onboarding when it was the last.
    @MainActor
    func continueFrom(_ step: OnboardingStep) {
        if let next = self.step(after: step) { advance(to: next) } else { finish() }
    }

    func toggleFavorite(_ item: CatalogItem) {
        if favoriteFoodIDs.contains(item.id) { favoriteFoodIDs.remove(item.id) }
        else { favoriteFoodIDs.insert(item.id) }
    }

    func togglePreference(_ pref: DietaryPreference) {
        if selectedPreferences.contains(pref) { selectedPreferences.remove(pref) }
        else { selectedPreferences.insert(pref) }
    }

    /// Pushes `step` unless it is already on the stack or isn't ahead of the
    /// current screen, so a double tap on Next (or a tap on the previous
    /// screen while the push animates) can't push the same step twice.
    func advance(to step: OnboardingStep) {
        let current = path.last ?? .name
        guard step.rawValue > current.rawValue, !path.contains(step) else { return }
        path.append(step)
    }

    // MARK: - Finish onboarding
    @MainActor
    func finish() {
        let profile = makeProfile()
        profile.save()
        UserProfile.markTargetsCurrent()
        AppState.shared.saveBMR(BMRCalculator.response(for: profile,
                                                       isKeto: selectedPreferences.contains(.keto)))

        selectedPreferences.save()
        UserDefaults.standard.set(Array(favoriteFoodIDs), forKey: Constants.Storage.favoriteFoodIDs)

        AppState.shared.userProfile = profile
        // Saved before onboarding completes, so the first Home already fits the choice.
        AppState.shared.setEnabledFeatures(features)
        AppFeature.save(features)
        AppState.shared.completeOnboarding()
        // The app's start-up task (SmartMarketAgentApp) starts the agent loop once the screen
        // swap has finished, so the change to the app stays smooth.
    }

    /// The profile `finish()` saves, with its targets. Pure (no storage).
    func makeProfile() -> UserProfile {
        var profile = UserProfile()
        let fullName = [firstName.trimmingCharacters(in: .whitespaces),
                        lastName.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        profile.name          = fullName.isEmpty ? "Nourlo User" : fullName
        profile.weight        = weight
        profile.height        = height
        profile.age           = age
        profile.gender        = gender
        profile.activityLevel = activityLevel
        profile.weightGoal    = BMRCalculator.effectiveGoal(weightGoal, age: age)
        profile.lossPace      = lossPace
        BMRCalculator.populate(profile: &profile)
        return profile
    }
}
