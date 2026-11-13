import SwiftUI
import Observation
import UserNotifications

@MainActor
@Observable
final class ProfileViewModel {

    var profile: UserProfile = .load()
    var selectedPreferences: Set<DietaryPreference> = []
    var favoriteFoodIDs: Set<String> = []
    var showResetAlert = false
    var isSaving = false
    var deletionError: String?
    /// Set when the server AI account couldn't be deleted; the user may still
    /// erase this iPhone's data after confirming.
    var serverDeletionFailure: String?
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
        // Propagate like onboarding does, so Home, the planner and the agent
        // use the new body stats, goal and keto macro split immediately.
        AppState.shared.userProfile = profile
        AppState.shared.saveBMR(BMRCalculator.response(for: profile,
                                                       isKeto: selectedPreferences.contains(.keto)))
        NotificationCenter.default.post(name: .personalDataDidChange, object: nil)
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

    private(set) var isDeletingData = false

    /// `localOnly` skips the server AI account deletion after the user has
    /// confirmed erasing this iPhone anyway.
    func resetOnboarding(localOnly: Bool = false) async {
        guard !isDeletingData else { return }
        isDeletingData = true
        defer { isDeletingData = false }
        if !localOnly {
            do { try await AIAccountService.shared.deleteAccountIfPresent() }
            catch {
                serverDeletionFailure = "The online AI account on Nourlo's server could not be deleted (\(error.localizedDescription)). You can erase this iPhone's data anyway, but the server account and its AI usage record will remain. To delete it later, finish setup, sign in with the same Apple Account in Profile, then use Delete All Data again. Guest access can't be restored after erasing, so for a guest account ask the person who provided your build to delete it. Or cancel, connect to the internet, sign in again and retry."
                return
            }
        }
        do { try PrivateSyncService.shared.beginDeletion() }
        catch {
            deletionError = "Could not safely record deletion. Please try again."
            return
        }
        guard KeychainHelper.deleteAll() else {
            deletionError = "Could not erase secure storage. Unlock your iPhone and retry deletion."
            return
        }
        AIAccountService.shared.clearLocalSession()
        AppState.shared.dataGeneration = UUID()
        AppState.shared.uiIdentity = UUID()
        AppState.shared.agentLoop.invalidateUserData()
        // Initialize and reset the cart before clearing grocery storage: cart
        // initialization can mirror existing cart lines into the grocery list.
        ShoppingCartService.shared.resetAll()
        LocalDataEraser.clear(defaults: .standard,
                              domain: Bundle.main.bundleIdentifier ?? "com.mostafa.mealio")
        FoodLogStore.shared.clearAll()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        // Wipe active global runtime architecture states safely
        AppState.shared.weeklyMealPlan = nil
        AppState.shared.userProfile = UserProfile()
        AppState.shared.bmrData = nil
        AppState.shared.activeDeals = []
        AppState.shared.notifiedDealIds = []
        AppState.shared.dealNotifications = []
        AppState.shared.lastGroceryCount = 0
        AppState.shared.lang = "en"
        AppState.shared.groceryList = []
        AppState.shared.favoriteFoodIDs = []
        AppState.shared.isOnboarded = false
        AppState.shared.hasSeenWelcome = false
        
        // Reset local memory states immediately
        profile = UserProfile()
        selectedPreferences = []
        favoriteFoodIDs = []
        didLoad = false
        PrivateSyncService.shared.finishDeletion()
    }
}
