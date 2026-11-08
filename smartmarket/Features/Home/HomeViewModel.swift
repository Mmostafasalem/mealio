import SwiftUI
import Observation

@MainActor
@Observable
final class HomeViewModel {

    var deals: [MarketDeal] = []
    var mealPlan: MealPlan?
    var isLoading = false
    var isRefreshing = false  // true while background fetch is running over stale data
    var errorMessage: String?
    var profile: UserProfile = .load()
    var groceryList: [GroceryItem] = GroceryStorage.load()
    var activeDealBanner: MarketDeal?
    var showLogSheet = false
    var logSheetSlot: MealSlot?          // pre-selects a slot when opening the log sheet
    var showAgentChat = false
    var chatMessages: [ChatMessage] = []
    var chatInput = ""
    var isChatLoading = false
    var chatNotice: String?
    var lastChatFailed = false
    var mascotCelebration: UUID?
    var assistantModeLabel: String { AIConnectionState.shared.modeLabel }
    var mealPlanSourceText: String {
        switch AppState.shared.weeklyMealPlan?.generationSource {
        case "online": return "AI meal plan"
        case "local": return "Local meal suggestions"
        default: return "Saved meal suggestions"
        }
    }

    private let log = FoodLogStore.shared

    private var favoriteFoodIDs: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: Constants.Storage.favoriteFoodIDs) ?? [])
    }()

    var goal: Int { max(profile.dailyCalorieGoal, 1) }

    // MARK: - Logged totals (single source of truth = FoodLogStore)

    var consumed: Int { log.totalCalories }
    var remaining: Int { max(goal - log.totalCalories, 0) }
    var proteinCurrent: Double { log.totalProtein }
    var carbsCurrent: Double { log.totalCarbs }
    var fatCurrent: Double { log.totalFat }

    func entries(for slot: MealSlot) -> [FoodLogEntry] { log.entries(for: slot) }
    func calories(for slot: MealSlot) -> Int { log.calories(for: slot) }

    /// Today's generated plan meals for a slot — for one-tap logging.
    func plannedEntries(for slot: MealSlot) -> [MealEntry] {
        guard let plan = mealPlan else { return [] }
        switch slot {
        case .breakfast: return plan.breakfast
        case .lunch:     return plan.lunch
        case .dinner:    return plan.dinner
        case .snack:     return plan.snacks
        }
    }

    var recentNutritionFoods: [NutritionFood] {
        log.recentFoodIDs.compactMap { NutritionCatalogService.shared.find($0) }
    }

    // Cached macro targets — recomputed in load(), not on every render pass.
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

    /// Deals filtered to stores within 8 km. Falls back to all deals when location is unavailable.
    var nearbyDeals: [MarketDeal] {
        guard let _ = LocationService.shared.userLocation else { return deals }
        return deals.filter { LocationService.shared.isNearby($0.store, radius: 8_000) }
    }

    init() {
        if let weekly = AppState.shared.weeklyMealPlan { mealPlan = MealPlan.from(weekly: weekly) }
        refreshMacroTargets()
        NotificationCenter.default.addObserver(
            forName: .groceryListDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.groceryList = GroceryStorage.load() }
        }

        NotificationCenter.default.addObserver(
            forName: .mealPlanDidUpdate, object: nil, queue: .main
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
        guard !isLoading && !isRefreshing else { return }
        log.reload()                       // daily reset handled by the store
        if profile.name.isEmpty { profile = .load() }
        groceryList = GroceryStorage.load()
        favoriteFoodIDs = Set(UserDefaults.standard.stringArray(forKey: Constants.Storage.favoriteFoodIDs) ?? [])
        refreshMacroTargets()
        errorMessage = nil

        // Stale-while-revalidate: show cached data instantly, fetch fresh in background
        if deals.isEmpty {
            if let cached = await CacheService.shared.getStale([MarketDeal].self, key: CacheService.Keys.deals) {
                deals = cached
            }
        }
        if mealPlan == nil, let weekly = AppState.shared.weeklyMealPlan {
            mealPlan = MealPlan.from(weekly: weekly)
        }

        isLoading = deals.isEmpty
        isRefreshing = !deals.isEmpty

        async let dealsResult = loadDeals()
        async let planResult = loadPlan()
        let (loadedDeals, loadedPlan) = await (dealsResult, planResult)

        deals = loadedDeals
        if mealPlan == nil { mealPlan = loadedPlan }
        isLoading = false
        isRefreshing = false

        // Curated estimates are not verified promotions or nearby inventory.
        activeDealBanner = nil
        await NotificationService.shared.checkPermission()
        await AIConnectionState.shared.checkOwnerConnection()
    }

    func refresh() async {
        // Keep readable content while revalidating; refresh never blanks the screen.
        await load()
    }

    /// Fetches fresh deals and updates the cache; falls back to stale cache then mocks.
    private func loadDeals() async -> [MarketDeal] {
        do {
            let result = try await APIService.shared.fetchMarketDeals()
            await CacheService.shared.set(result, key: CacheService.Keys.deals, ttl: CacheService.TTL.deals)
            return result
        } catch {
            appLog("[Home] deals fetch failed:", error)
            if let stale = await CacheService.shared.getStale([MarketDeal].self, key: CacheService.Keys.deals) {
                return stale
            }
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
        activeDealBanner = nil
    }

    // MARK: - Food logging (local, optimistic)

    func logFood(_ food: NutritionFood, slot: MealSlot, amount: Double) {
        guard food.isValid, amount.isFinite, amount >= food.minimumAmount, amount <= food.maximumAmount else { return }
        NutritionCatalogService.shared.remember(food)
        log.add(FoodLogEntry(nutritionFood: food, slot: slot, amount: amount))
        mascotCelebration = UUID()
    }

    func removeLog(_ entry: FoodLogEntry) { log.remove(entry) }

    func openLog(slot: MealSlot? = nil) {
        logSheetSlot = slot
        showLogSheet = true
    }

    // MARK: - Deal notifications

    private func checkAndNotifyFavouriteDeals() async {
        // Retail alerts require a verified price/stock source, which we do not have.
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

    func dismissBanner() { activeDealBanner = nil }

    // MARK: - Agent Chat Interaction

    func sendChatMessage() async {
        let text = chatInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isChatLoading else { return }

        chatInput = ""
        chatNotice = nil
        lastChatFailed = false
        let generation = AppState.shared.dataGeneration
        chatMessages.append(ChatMessage(role: "user", content: text))
        isChatLoading = true
        defer { isChatLoading = false }

        let appState = AppState.shared
        let goalStr = appState.userProfile.weightGoal.rawValue
        let target = appState.bmrData?.maintainCalories ?? 2000
        let favNames = ProductCatalogService.shared.nameFor(ids: appState.favoriteFoodIDs)

        let history = chatMessages.dropLast().map {
            AgentChatHistoryItem(role: $0.role, content: $0.content)
        }
        let context = AgentUserContext(
            goal: goalStr,
            targetCalories: target,
            caloriesConsumed: consumed,
            favoriteFoods: favNames
        )
        let request = AgentChatRequest(message: text, history: Array(history), userContext: context)

        do {
            let response = try await APIService.shared.agentChat(request)
            guard !Task.isCancelled, AppState.shared.dataGeneration == generation else { return }
            chatMessages.append(ChatMessage(role: "assistant", content: response.reply))
        } catch {
            guard !Task.isCancelled, AppState.shared.dataGeneration == generation else { return }
            let message: String
            if error is AIAccountError || error is APIError { message = error.localizedDescription }
            else if error is URLError, OwnerAITestConfiguration.current != nil {
                message = "Could not reach the AI on your Mac. Keep the Mac awake, connect both devices to the same Wi-Fi, and allow Nourlo access to your local network in iPhone Settings."
            }
            else { message = "Sorry, I couldn't reach the agent. Please try again." }
            chatNotice = message
            lastChatFailed = true
        }
    }
}
