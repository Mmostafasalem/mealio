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

    func toggleFavorite(_ food: Food) {
        if favoriteFoodIDs.contains(food.id) {
            favoriteFoodIDs.remove(food.id)
        } else {
            favoriteFoodIDs.insert(food.id)
        }
    }

    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: Constants.Storage.hasCompletedOnboarding)
    }
}
