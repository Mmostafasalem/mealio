import Foundation
import Combine

@MainActor
@Observable
final class AppState {

    static let shared = AppState()
    var dataGeneration = UUID()

    func reloadStoredData() {
        dataGeneration = UUID()
        agentLoop.invalidateUserData()
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
    var isGeneratingMealPlan: Bool = false
    var lastGroceryCount: Int = 0

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
        isOnboarded = true
        UserDefaults.standard.set(true, forKey: Constants.Storage.hasCompletedOnboarding)
    }

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
        return try? JSONDecoder().decode(WeeklyMealPlan.self, from: data)
    }

    private static func loadGroceryDeals() -> [Deal] {
        guard let data = UserDefaults.standard.data(forKey: Constants.Storage.groceryDeals) else { return [] }
        return (try? JSONDecoder().decode([Deal].self, from: data)) ?? []
    }
}

