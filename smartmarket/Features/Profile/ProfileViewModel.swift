import SwiftUI
import Observation

@MainActor
@Observable
final class ProfileViewModel {

    var profile: UserProfile = .load()
    var selectedPreferences: Set<DietaryPreference> = []
    var favoriteFoodIDs: Set<String> = []
    var showResetAlert = false
    var isSaving = false
    @ObservationIgnored private var didLoad = false

    var initials: String {
        let name = profile.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "SM" }
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    func load() {
        guard !didLoad else { return }
        didLoad = true
        profile = .load()
        selectedPreferences = .load()
        favoriteFoodIDs = Set(UserDefaults.standard.stringArray(forKey: Constants.Storage.favoriteFoodIDs) ?? [])
    }

    func save() {
        isSaving = true
        defer { isSaving = false }
        BMRCalculator.populate(profile: &profile)
        profile.save()
        selectedPreferences.save()
        UserDefaults.standard.set(Array(favoriteFoodIDs), forKey: Constants.Storage.favoriteFoodIDs)
    }

    func togglePreference(_ pref: DietaryPreference) {
        if selectedPreferences.contains(pref) {
            selectedPreferences.remove(pref)
        } else {
            selectedPreferences.insert(pref)
        }
    }

    func toggleFavorite(_ item: CatalogItem) {
        if favoriteFoodIDs.contains(item.id) {
            favoriteFoodIDs.remove(item.id)
        } else {
            favoriteFoodIDs.insert(item.id)
        }
    }

    func resetOnboarding() {
        let keys: [String] = [
            Constants.Storage.hasCompletedOnboarding,
            Constants.Storage.userProfile,
            Constants.Storage.bmrResponse,
            Constants.Storage.favoriteFoodIDs,
            Constants.Storage.selectedDietaryFilters,
            Constants.Storage.groceryList,
            Constants.Storage.groceryDeals,
            Constants.Storage.caloriesConsumedToday,
            Constants.Storage.loggedMealEntries,
            Constants.Storage.currentMealPlan,
            Constants.Storage.lang
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
        UserDefaults.standard.removeObject(forKey: "lastMealPlanGeneratedDate")
        UserDefaults.standard.removeObject(forKey: "foodLogEntries")
        UserDefaults.standard.removeObject(forKey: "recentFoodIDs")
        FoodLogStore.shared.clearToday()

        // Health data (BMR + body stats) lives in the Keychain, which survives a
        // UserDefaults wipe — clear it too so "clear all data" truly deletes
        // everything (correctness + GDPR/CCPA right-to-erasure).
        KeychainHelper.deleteAll()

        // Wipe active global runtime architecture states safely
        AppState.shared.weeklyMealPlan = nil
        AppState.shared.activeDeals = []
        AppState.shared.groceryList = []
        AppState.shared.favoriteFoodIDs = []
        AppState.shared.isOnboarded = false
        AppState.shared.hasSeenWelcome = false
        
        // Reset local memory states immediately
        profile = UserProfile()
        selectedPreferences = []
        favoriteFoodIDs = []
        didLoad = false
    }
}
