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
    var liveBMR: Int {
        Int(BMRCalculator.bmr(
            weight: weight, height: height, age: age, gender: gender
        ).rounded())
    }

    var liveTDEE: Int {
        Int(BMRCalculator.tdee(
            bmr: Double(liveBMR), activityLevel: activityLevel
        ).rounded())
    }

    var liveDailyGoal: Int {
        switch weightGoal {
        case .lose:     return BMRCalculator.dailyGoal(tdee: Double(liveTDEE), goal: .lose,     pace: lossPace, gender: gender)
        case .maintain: return liveTDEE
        case .gain:     return BMRCalculator.dailyGoal(tdee: Double(liveTDEE), goal: .gain,     pace: lossPace, gender: gender)
        }
    }

    var isBelowSafeFloor: Bool {
        let floor: Int
        switch gender {
        case .male:   floor = Constants.Calories.minimumMale
        case .female: floor = Constants.Calories.minimumFemale
        case .other:  floor = Constants.Calories.minimumOther
        }
        return liveDailyGoal <= floor
    }

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

    func advance(to step: OnboardingStep) { path.append(step) }

    // MARK: - Finish onboarding
    @MainActor
    func finish() {
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
        profile.weightGoal    = weightGoal
        profile.lossPace      = lossPace
        BMRCalculator.populate(profile: &profile)
        profile.save()
        AppState.shared.saveBMR(BMRCalculator.response(for: profile,
                                                       isKeto: selectedPreferences.contains(.keto)))

        selectedPreferences.save()
        UserDefaults.standard.set(Array(favoriteFoodIDs), forKey: Constants.Storage.favoriteFoodIDs)

        AppState.shared.userProfile = profile
        AppState.shared.completeOnboarding()
        AppState.shared.agentLoop.start(appState: AppState.shared)
    }
}
