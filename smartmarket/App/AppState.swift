import Foundation
import SwiftUI
import Combine

@MainActor
@Observable
final class AppState {

    static let shared = AppState()
    /// Invalidates in-flight requests made for erased data (Delete All Data only).
    var dataGeneration = UUID()
    /// Root view identity. Changed only by Delete All Data so a sync apply never
    /// rebuilds the UI (open sheets and in-flight chat replies stay intact).
    var uiIdentity = UUID()

    /// Refreshes stores in place after a remote sync apply.
    func reloadStoredData() {
        userProfile = UserProfile.load()
        bmrData = Self.loadBMR()
        weeklyMealPlan = Self.loadWeeklyMealPlan()
        groceryList = Self.loadGroceryDeals()
        isOnboarded = UserDefaults.standard.bool(forKey: Constants.Storage.hasCompletedOnboarding)
        hasSeenWelcome = UserDefaults.standard.bool(forKey: "hasSeenWelcome")
        lang = UserDefaults.standard.string(forKey: Constants.Storage.lang) ?? "en"
    }

    // MARK: - User
    var userProfile: UserProfile = UserProfile.load()
    var bmrData: BMRResponse? = AppState.loadBMR()
    var isOnboarded: Bool = UserDefaults.standard.bool(forKey: Constants.Storage.hasCompletedOnboarding)
    var hasSeenWelcome: Bool = UserDefaults.standard.bool(forKey: "hasSeenWelcome")
    var lang: String = UserDefaults.standard.string(forKey: Constants.Storage.lang) ?? "en"

    // MARK: - Market
    var activeDeals: [Deal] = []
    var groceryList: [Deal] = AppState.loadGroceryDeals()
    var notifiedDealIds: Set<Int> = AppState.loadNotifiedDealIds()
    var dealNotifications: [Deal] = []

    // MARK: - Meal Plan
    var weeklyMealPlan: WeeklyMealPlan? = AppState.loadWeeklyMealPlan()
    /// True while an online meal-plan request (agent loop or Meals tab) runs.
    var isGeneratingMealPlan: Bool { mealPlanRequest != nil }
    var lastGroceryCount: Int = 0

    enum MealPlanRequester { case background, user }
    struct MealPlanRequestTicket: Equatable {
        let id = UUID()
        let requester: MealPlanRequester
    }
    /// The one meal-plan request allowed to save its result.
    private(set) var mealPlanRequest: MealPlanRequestTicket?

    /// Claims the single meal-plan slot. A background request never starts
    /// while another runs; a user request takes over from a background one
    /// (whose result is then discarded). Returns nil when the slot is taken.
    func beginMealPlanRequest(_ requester: MealPlanRequester) -> MealPlanRequestTicket? {
        if let current = mealPlanRequest {
            guard requester == .user, current.requester == .background else { return nil }
            agentLoop.cancelBackgroundRegeneration()
        }
        let ticket = MealPlanRequestTicket(requester: requester)
        mealPlanRequest = ticket
        return ticket
    }

    /// Whether this request still owns the slot (it may save its plan).
    func ownsMealPlanRequest(_ ticket: MealPlanRequestTicket) -> Bool {
        mealPlanRequest == ticket
    }

    func endMealPlanRequest(_ ticket: MealPlanRequestTicket) {
        if mealPlanRequest == ticket { mealPlanRequest = nil }
    }

    // MARK: - Agent
    let agentLoop = AgentLoop()

    // MARK: - Favourite food IDs (String, from Food.catalog)
    var favoriteFoodIDs: Set<String> {
        get {
            let arr = UserDefaults.standard.array(forKey: Constants.Storage.favoriteFoodIDs) as? [String] ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Constants.Storage.favoriteFoodIDs)
        }
    }

    // MARK: - Persistence helpers

    func saveBMR(_ bmr: BMRResponse) {
        bmrData = bmr
        KeychainHelper.save(bmr, key: Constants.Storage.bmrResponse)
        // Remove legacy UserDefaults entry if migrating
        UserDefaults.standard.removeObject(forKey: Constants.Storage.bmrResponse)
    }

    func saveNotifiedDealId(_ id: Int) {
        notifiedDealIds.insert(id)
        UserDefaults.standard.set(Array(notifiedDealIds), forKey: Constants.Storage.notifiedDealIds)
    }

    func saveMealPlan(_ plan: WeeklyMealPlan) {
        weeklyMealPlan = plan
        if let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: Constants.Storage.currentMealPlan)
        }
        NotificationCenter.default.post(name: .mealPlanDidUpdate, object: nil)
    }

    func addDealToGrocery(_ deal: Deal) {
        guard !groceryList.contains(where: { $0.id == deal.id }) else { return }
        groceryList.append(deal)
        saveGroceryDeals()
        NotificationCenter.default.post(name: .groceryListDidChange, object: nil)
    }

    func removeDealFromGrocery(id: Int) {
        groceryList.removeAll { $0.id == id }
        saveGroceryDeals()
        NotificationCenter.default.post(name: .groceryListDidChange, object: nil)
    }

    func saveGroceryDeals() {
        if let data = try? JSONEncoder().encode(groceryList) {
            UserDefaults.standard.set(data, forKey: Constants.Storage.groceryDeals)
        }
    }

    func completeOnboarding() {
        // The screen swap to the app uses the same slow, even curve as the rest of the root changes.
        withAnimation(SmartMarketAgentApp.rootTransition) { isOnboarded = true }
        UserDefaults.standard.set(true, forKey: Constants.Storage.hasCompletedOnboarding)
        // The first plan is ready at once; it doesn't wait for the first network tick.
        AgentLoop.rebuildPlanNow(appState: self)
    }

    /// The profile lives in the Keychain. If it couldn't be read at launch (the phone was
    /// locked, on items saved by older builds), read it again once the phone is unlocked.
    /// And when it is really gone (a backup restored to a new phone brings the settings
    /// but not the Keychain), setup runs again instead of using a made-up person.
    func recoverProfileIfNeeded() {
        guard isOnboarded, UIApplication.shared.isProtectedDataAvailable else { return }
        let inKeychain = KeychainHelper.load(UserProfile.self, key: Constants.Storage.userProfile) != nil
        if inKeychain || UserDefaults.standard.data(forKey: Constants.Storage.userProfile) != nil {
            if !profileWasRead { reloadStoredData(); profileWasRead = true }
        } else if !NourloTips.isUITesting() {
            // UI tests start "onboarded" with no stored profile on purpose.
            UserDefaults.standard.set(false, forKey: Constants.Storage.hasCompletedOnboarding)
            withAnimation(SmartMarketAgentApp.rootTransition) { isOnboarded = false }
        }
    }
    /// Whether the stored profile was readable when the app state was created.
    @ObservationIgnored private var profileWasRead = KeychainHelper.load(UserProfile.self, key: Constants.Storage.userProfile) != nil

    // MARK: - Static loaders

    private static func loadBMR() -> BMRResponse? {
        // Keychain first, fall back to UserDefaults for migration
        if let bmr = KeychainHelper.load(BMRResponse.self, key: Constants.Storage.bmrResponse) {
            return bmr
        }
        guard let data = UserDefaults.standard.data(forKey: Constants.Storage.bmrResponse),
              let bmr = try? JSONDecoder().decode(BMRResponse.self, from: data) else { return nil }
        KeychainHelper.save(bmr, key: Constants.Storage.bmrResponse)
        UserDefaults.standard.removeObject(forKey: Constants.Storage.bmrResponse)
        return bmr
    }

    private static func loadNotifiedDealIds() -> Set<Int> {
        let arr = UserDefaults.standard.array(forKey: Constants.Storage.notifiedDealIds) as? [Int] ?? []
        return Set(arr)
    }

    private static func loadWeeklyMealPlan() -> WeeklyMealPlan? {
        guard let data = UserDefaults.standard.data(forKey: Constants.Storage.currentMealPlan) else { return nil }
        return ResilientStorage.decode(WeeklyMealPlan.self, from: data, key: Constants.Storage.currentMealPlan)
    }

    private static func loadGroceryDeals() -> [Deal] {
        ResilientStorage.loadArray(Deal.self, key: Constants.Storage.groceryDeals)
    }
}

