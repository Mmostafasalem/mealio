import SwiftUI
import Observation

/// Single shared view model for the entire onboarding flow.
@Observable
final class OnboardingViewModel {

    // MARK: - Navigation
    var path: [OnboardingStep] = []

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
        AppState.shared.completeOnboarding()
        AppState.shared.agentLoop.start(appState: AppState.shared)
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
