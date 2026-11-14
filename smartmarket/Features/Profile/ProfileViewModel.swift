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

    /// What was last loaded or saved, so `save()` can skip when nothing changed.
    private struct Snapshot: Equatable {
        var profile: UserProfile
        var preferences: Set<DietaryPreference>
        var favorites: Set<String>
    }
    @ObservationIgnored private var lastSaved: Snapshot?

    private var current: Snapshot {
        Snapshot(profile: profile, preferences: selectedPreferences, favorites: favoriteFoodIDs)
    }

    func load() {
        guard !didLoad else { return }
        load(profile: .load(), preferences: .load(),
             favorites: Set(UserDefaults.standard.stringArray(forKey: Constants.Storage.favoriteFoodIDs) ?? []))
    }

    /// Takes the given values as the loaded (already saved) state.
    func load(profile: UserProfile, preferences: Set<DietaryPreference>, favorites: Set<String>) {
        didLoad = true
        self.profile = profile
        selectedPreferences = preferences
        favoriteFoodIDs = favorites
        lastSaved = current
    }

    // MARK: - Goal

    /// Under-18s are offered maintain or gain only.
    var allowsWeightLoss: Bool { BMRCalculator.allowsWeightLoss(age: profile.age) }

    var availableGoals: [WeightGoal] {
        allowsWeightLoss ? WeightGoal.allCases : WeightGoal.allCases.filter { $0 != .lose }
    }

    /// Targets for the current body stats with a given goal and pace.
    func targets(goal: WeightGoal? = nil, pace: LossPace? = nil) -> BMRCalculator.Targets {
        BMRCalculator.targets(weight: profile.weight, height: profile.height, age: profile.age,
                              gender: profile.gender, activityLevel: profile.activityLevel,
                              goal: goal ?? profile.weightGoal, pace: pace ?? profile.lossPace)
    }

    func effectiveDeficit(for pace: LossPace) -> Int {
        BMRCalculator.effectiveDeficit(tdee: targets().tdee, pace: pace, gender: profile.gender, age: profile.age)
    }

    func isCappedBySafetyFloor(_ pace: LossPace) -> Bool {
        BMRCalculator.isCappedBySafetyFloor(tdee: targets().tdee, pace: pace, gender: profile.gender, age: profile.age)
    }

    func setGoal(_ goal: WeightGoal) {
        profile.weightGoal = BMRCalculator.effectiveGoal(goal, age: profile.age)
        save()
    }

    func setPace(_ pace: LossPace) {
        profile.lossPace = pace
        save()
    }

    // MARK: - Save

    /// Recomputes targets (the same path as onboarding) and saves. Does nothing,
    /// and posts nothing, when nothing changed since the last load or save.
    @discardableResult
    func save() -> Bool {
        profile = Self.prepared(profile)
        guard current != lastSaved else { return false }
        let weightChanged = lastSaved.map { $0.profile.weight != profile.weight } ?? true
        isSaving = true
        defer { isSaving = false }
        profile.save()
        UserProfile.markTargetsCurrent()
        selectedPreferences.save()
        // Apple Health only suggests a weight measured after this edit.
        if weightChanged { HealthService.shared.noteProfileWeightEdited() }
        UserDefaults.standard.set(Array(favoriteFoodIDs), forKey: Constants.Storage.favoriteFoodIDs)
        // Propagate like onboarding does, so Home, the planner and the agent
        // use the new body stats, goal and keto macro split immediately.
        AppState.shared.userProfile = profile
        AppState.shared.saveBMR(BMRCalculator.response(for: profile,
                                                       isKeto: selectedPreferences.contains(.keto)))
        NotificationCenter.default.post(name: .personalDataDidChange, object: nil)
        lastSaved = current
        return true
    }

    /// The profile `save()` stores: goal moved to what the age allows and
    /// targets recomputed. Pure, so tests can check it without the Keychain.
    nonisolated static func prepared(_ profile: UserProfile) -> UserProfile {
        var profile = profile
        BMRCalculator.populate(profile: &profile)
        return profile
    }

    /// Takes Apple Health's weight after the person confirmed it, through the
    /// normal save path (targets recomputed, `.personalDataDidChange` posted).
    @discardableResult
    func applyHealthWeight(_ kilograms: Double) -> Bool {
        guard kilograms.isFinite, WeightRuler.defaultRange.contains(kilograms) else { return false }
        profile.weight = kilograms
        return save()
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
        // Stops Apple Health syncing and forgets what was written; data
        // already in the Health app stays there for the person to manage.
        HealthService.shared.resetForDataDeletion()
        AppState.shared.dataGeneration = UUID()
        AppState.shared.uiIdentity = UUID()
        AppState.shared.agentLoop.invalidateUserData()
        // Initialize and reset the cart before clearing grocery storage: cart
        // initialization can mirror existing cart lines into the grocery list.
        ShoppingCartService.shared.resetAll()
        LocalDataEraser.clear(defaults: .standard,
                              domain: Bundle.main.bundleIdentifier ?? "com.mostafa.mealio")
        Self.reloadErasedStores()
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
        lastSaved = nil
        PrivateSyncService.shared.finishDeletion()
    }

    /// Every app-wide store that keeps user data in memory re-reads (now empty)
    /// storage, so nothing erased can be shown again or written back. Called
    /// right after the stored data is erased. The cart is reset before the
    /// erase, and the food log (with stock and saved foods) clears itself.
    static func reloadErasedStores() {
        FoodLogStore.shared.clearAll()          // also StockStore and NutritionCatalogService
        WorkoutStore.shared.reload()
        ReminderStore.shared.reload()
        RecipeRatingStore.shared.reload()
        DailyLoopStore.shared.reset()
    }
}
