import SwiftUI
import Observation

@MainActor
@Observable
final class HomeViewModel {

    var deals: [MarketDeal] = []
    var mealPlan: MealPlan?
    var isLoading = false
    var errorMessage: String?
    var profile: UserProfile = .load()
    var consumed: Int = UserDefaults.standard.integer(forKey: Constants.Storage.caloriesConsumedToday)
    var groceryList: [GroceryItem] = GroceryStorage.load()
    var activeDealBanner: MarketDeal?
    var showLogSheet = false
    var loggedMealEntries: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: Constants.Storage.loggedMealEntries) ?? [])
    }()

    private var favoriteFoodIDs: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: Constants.Storage.favoriteFoodIDs) ?? []
    )

    var goal: Int { max(profile.dailyCalorieGoal, 1) }

    // Cached — recomputed only in load(), not on every render pass.
    private(set) var proteinGoal: Double = 0
    private(set) var carbsGoal: Double   = 0
    private(set) var fatGoal: Double     = 0

    private func refreshMacroTargets() {
        let isKeto = Set<DietaryPreference>.load().contains(.keto)
        let t = BMRCalculator.macroTargets(calories: goal, isKeto: isKeto)
        proteinGoal = Double(t.proteinG)
        carbsGoal   = Double(t.carbsG)
        fatGoal     = Double(t.fatG)
    }

    var proteinCurrent: Double { mealPlan?.totalProteinG ?? 0 }
    var carbsCurrent: Double { mealPlan?.totalCarbsG ?? 0 }
    var fatCurrent: Double { mealPlan?.totalFatG ?? 0 }

    /// Deals filtered to stores within 1 km of the user. Falls back to all when location is unavailable.
    var nearbyDeals: [MarketDeal] {
        deals.filter { LocationService.shared.isNearby($0.store, radius: 1000) }
    }

    init() {
        NotificationCenter.default.addObserver(
            forName: .groceryListDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.groceryList = GroceryStorage.load()
        }
        NotificationCenter.default.addObserver(
            forName: .mealPlanDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                if let weekly = AppState.shared.weeklyMealPlan {
                    self?.mealPlan = MealPlan.from(weekly: weekly)
                }
            }
        }
    }

    // MARK: - Loading

    func load() async {
        guard deals.isEmpty && mealPlan == nil else { return }

        // Read from UserDefaults only once — at cold start.
        profile = .load()
        groceryList = GroceryStorage.load()
        favoriteFoodIDs = Set(UserDefaults.standard.stringArray(forKey: Constants.Storage.favoriteFoodIDs) ?? [])
        consumed = UserDefaults.standard.integer(forKey: Constants.Storage.caloriesConsumedToday)
        loggedMealEntries = Set(UserDefaults.standard.stringArray(forKey: Constants.Storage.loggedMealEntries) ?? [])
        refreshMacroTargets()
        errorMessage = nil

        isLoading = true

        async let dealsResult = loadDeals()
        async let planResult = loadPlan()
        let (loadedDeals, loadedPlan) = await (dealsResult, planResult)

        deals = loadedDeals
        mealPlan = loadedPlan
        isLoading = false

        pickBanner()
        await checkAndNotifyFavouriteDeals()
    }

    func refresh() async {
        deals = []
        mealPlan = nil
        await load()
    }

    /// Network failures fall back to mocked deals silently.
    private func loadDeals() async -> [MarketDeal] {
        do {
            return try await APIService.shared.fetchMarketDeals()
        } catch {
            print("[Home] deals fetch failed, using mock:", error)
            return MarketDeal.mocked
        }
    }

    /// Returns the meal plan from AppState if one has been generated; the
    /// agent loop is responsible for requesting a new plan asynchronously.
    private func loadPlan() async -> MealPlan? {
        if let weekly = AppState.shared.weeklyMealPlan {
            return MealPlan.from(weekly: weekly)
        }
        return nil
    }

    private func pickBanner() {
        guard activeDealBanner == nil else { return }
        let favorites = favoriteFoodIDs
        activeDealBanner = deals.first { favorites.contains($0.productId) } ?? deals.first
    }

    // MARK: - Deal notifications

    private func checkAndNotifyFavouriteDeals() async {
        guard UserDefaults.standard.bool(forKey: "dealAlertsEnabled") else { return }
        await NotificationService.shared.checkPermission()
        guard NotificationService.shared.permissionGranted else { return }

        let nearby = nearbyDeals
        for deal in nearby where favoriteFoodIDs.contains(deal.productId) {
            await NotificationService.shared.scheduleDealNotification(for: deal)
        }
    }

    // MARK: - Deal response

    func respondToDeal(_ deal: MarketDeal, bought: Bool) async {
        if bought {
            let item = GroceryItem(
                id: UUID().uuidString,
                foodId: deal.productId,
                foodName: deal.productName,
                quantity: deal.quantity,
                estimatedPrice: deal.discountPrice,
                storeId: deal.store.id,
                storeName: deal.store.name,
                isBought: false
            )
            if !groceryList.contains(where: { $0.foodId == item.foodId && $0.storeId == item.storeId }) {
                groceryList.append(item)
                GroceryStorage.save(groceryList)
            }
        }
        activeDealBanner = nil
    }

    func dismissBanner() {
        activeDealBanner = nil
    }

    // MARK: - Calorie logging

    func logMealEntry(_ entry: MealEntry) {
        guard !loggedMealEntries.contains(entry.id) else { return }
        loggedMealEntries.insert(entry.id)
        consumed += entry.calories
        UserDefaults.standard.set(consumed, forKey: Constants.Storage.caloriesConsumedToday)
        UserDefaults.standard.set(Array(loggedMealEntries), forKey: Constants.Storage.loggedMealEntries)
    }

    func isLogged(_ entry: MealEntry) -> Bool {
        loggedMealEntries.contains(entry.id)
    }

    func resetDailyLog() {
        consumed = 0
        loggedMealEntries = []
        UserDefaults.standard.set(0, forKey: Constants.Storage.caloriesConsumedToday)
        UserDefaults.standard.set([String](), forKey: Constants.Storage.loggedMealEntries)
    }
}

/// Shared encode/decode for the grocery list stored in UserDefaults.
enum GroceryStorage {
    static func load() -> [GroceryItem] {
        guard let data = UserDefaults.standard.data(forKey: Constants.Storage.groceryList),
              let items = try? JSONDecoder().decode([GroceryItem].self, from: data)
        else { return [] }
        return items
    }

    static func save(_ items: [GroceryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Constants.Storage.groceryList)
    }

    static func add(_ item: GroceryItem) {
        var list = load()
        guard !list.contains(where: { $0.id == item.id }) else { return }
        list.append(item)
        save(list)
    }
}

