import Foundation
import Combine

@MainActor
@Observable
final class AppState {

    static let shared = AppState()

    // MARK: - User
    var userProfile: UserProfile = UserProfile.load()
    var bmrData: BMRResponse? = AppState.loadBMR()
    var isOnboarded: Bool = UserDefaults.standard.bool(forKey: Constants.Storage.hasCompletedOnboarding)
    var lang: String = UserDefaults.standard.string(forKey: Constants.Storage.lang) ?? "en"

    // MARK: - Market
    var activeDeals: [Deal] = []
    var groceryList: [Deal] = AppState.loadGroceryDeals()
    var notifiedDealIds: Set<Int> = []
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
        if let data = try? JSONEncoder().encode(bmr) {
            UserDefaults.standard.set(data, forKey: Constants.Storage.bmrResponse)
        }
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
        guard let data = UserDefaults.standard.data(forKey: Constants.Storage.bmrResponse) else { return nil }
        return try? JSONDecoder().decode(BMRResponse.self, from: data)
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

