import SwiftUI
import Observation

@MainActor
@Observable
final class HomeViewModel {

    var deals: [MarketDeal] = []
    /// Today's meals from the saved weekly plan. Rebuilt on load, when the
    /// plan changes, when the app comes back and when the day changes.
    private(set) var mealPlan: MealPlan?
    var isLoading = false
    var isRefreshing = false  // true while background fetch is running over stale data
    var errorMessage: String?
    /// Starts from the in-memory copy; `activate()` reads storage once.
    var profile: UserProfile = AppState.shared.userProfile
    var groceryList: [GroceryItem] = []
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

    private let log: FoodLogStore
    static let maxChatHistory = 20

    private var favoriteFoodIDs: Set<String> = []

    /// Home's clock. Today's log, due reminders, the header date and today's
    /// plan read it, so they move on with it: each minute while Home is on
    /// screen, when the app comes back and at midnight (see `tick`).
    private(set) var now = Date()
    @ObservationIgnored private var mealPlanDay: Date?
    @ObservationIgnored private var isActivated = false
    /// Removed in deinit so throwaway instances leave nothing registered.
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    var goal: Int { max(profile.dailyCalorieGoal, 1) }

    // MARK: - Logged totals (single source of truth = FoodLogStore)

    private var todayEntries: [FoodLogEntry] { log.entries(on: now) }
    var consumed: Int { todayEntries.reduce(0) { $0 + $1.calories } }
    var remaining: Int { max(goal - consumed, 0) }
    var proteinCurrent: Double { todayEntries.reduce(0) { $0 + $1.proteinG } }
    var carbsCurrent: Double { todayEntries.reduce(0) { $0 + $1.carbsG } }
    var fatCurrent: Double { todayEntries.reduce(0) { $0 + $1.fatG } }
    /// Meals with at least one entry today; their reminders are done.
    var loggedSlots: Set<MealSlot> { Set(todayEntries.map(\.slot)) }

    func entries(for slot: MealSlot) -> [FoodLogEntry] { todayEntries.filter { $0.slot == slot } }
    func calories(for slot: MealSlot) -> Int { entries(for: slot).reduce(0) { $0 + $1.calories } }

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

    /// Catalogue estimates shown on Home. (Named for the location filter it used to apply.)
    /// The estimates card: the person's favourite foods, each with the catalogue's
    /// estimated price (or the price they corrected in Shop). The pack size comes from
    /// the curated list when it has the same food; otherwise none is shown.
    var nearbyDeals: [MarketDeal] {
        let sizes = Dictionary(deals.map { ($0.productName.lowercased(), $0.quantity) }, uniquingKeysWith: { first, _ in first })
        let catalogue = Store(id: ShopStore.catalog.id, chain: "", name: ShopStore.catalog.name, address: "", latitude: 0, longitude: 0)
        return CatalogItem.all.filter { favoriteFoodIDs.contains($0.id) }.map { item in
            let price = ShoppingCartService.shared.effectivePrice(for: item, store: .catalog)
            return MarketDeal(id: "fav_\(item.id)", store: catalogue, productId: item.id, productName: item.name,
                              originalPrice: price, discountPrice: price, discountPercent: 0, validUntil: .distantFuture,
                              dealType: .weeklySpecial, quantity: sizes[item.name.lowercased()] ?? "")
        }
    }

    /// Cheap on purpose: SwiftUI may build and throw away several of these.
    /// Storage reads and observers wait for `activate()`.
    /// `log` defaults to the shared food log (tests pass their own).
    init(log: FoodLogStore? = nil) {
        self.log = log ?? .shared
        rebuildMealPlan()
    }

    deinit {
        for token in observers { NotificationCenter.default.removeObserver(token) }
    }

    /// Call when the view using this model appears. The first call reads
    /// storage and starts observing; every call brings the clock up to date.
    func activate() {
        if !isActivated {
            isActivated = true
            reloadLocalData()
            startObserving()
        }
        tick()
    }

    /// Moves Home's clock on. `now` is only republished when the minute
    /// changes, and today's plan is rebuilt only when the day does.
    func tick(_ date: Date = Date()) {
        if Int(date.timeIntervalSince1970 / 60) != Int(now.timeIntervalSince1970 / 60) { now = date }
        if let day = mealPlanDay, Calendar.current.isDate(day, inSameDayAs: date) { return }
        rebuildMealPlan(now: date)
    }

    /// Today's meals from the saved weekly plan (none when there's no plan).
    func rebuildMealPlan(now date: Date = Date()) {
        mealPlan = AppState.shared.weeklyMealPlan.flatMap { MealPlan.from(weekly: $0, date: date) }
        mealPlanDay = date
    }

    private func reloadLocalData() {
        profile = .load()
        groceryList = GroceryStorage.load()
        favoriteFoodIDs = Set(UserDefaults.standard.stringArray(forKey: Constants.Storage.favoriteFoodIDs) ?? [])
        refreshMacroTargets()
    }

    private func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (HomeViewModel) -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                handler(self)
            }
        }
        observers.append(token)
    }

    private func startObserving() {
        observe(.groceryListDidChange) { $0.groceryList = GroceryStorage.load() }
        // Profile edits and sync apply change goals/macros in place.
        observe(.personalDataDidChange) { vm in
            vm.profile = .load()
            vm.favoriteFoodIDs = Set(UserDefaults.standard.stringArray(forKey: Constants.Storage.favoriteFoodIDs) ?? [])
            vm.refreshMacroTargets()
        }
        observe(.mealPlanDidUpdate) { $0.rebuildMealPlan() }
        // Midnight, a clock or time-zone change, and coming back to the app.
        observe(.NSCalendarDayChanged) { $0.tick() }
        observe(UIApplication.significantTimeChangeNotification) { $0.tick() }
        observe(UIApplication.didBecomeActiveNotification) { $0.tick() }
    }

    // MARK: - Loading

    func load() async {
        guard !isLoading && !isRefreshing else { return }
        let firstActivation = !isActivated
        activate()
        log.reload()                       // daily reset handled by the store
        if !firstActivation { reloadLocalData() }
        rebuildMealPlan()
        errorMessage = nil

        // Stale-while-revalidate: show cached data instantly, fetch fresh in background
        if deals.isEmpty {
            if let cached = await CacheService.shared.getStale([MarketDeal].self, key: CacheService.Keys.deals) {
                deals = cached
            }
        }
        isLoading = deals.isEmpty
        isRefreshing = !deals.isEmpty

        deals = await loadDeals()
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

    private func pickBanner() {
        activeDealBanner = nil
    }

    // MARK: - Food logging (local, optimistic)

    /// False when the food or amount isn't valid and nothing was logged.
    @discardableResult
    func logFood(_ food: NutritionFood, slot: MealSlot, amount: Double) -> Bool {
        guard food.isValid, amount.isFinite, amount >= food.minimumAmount, amount <= food.maximumAmount else { return false }
        NutritionCatalogService.shared.remember(food)
        log.add(FoodLogEntry(nutritionFood: food, slot: slot, amount: amount))
        mascotCelebration = UUID()
        return true
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
                quantity: deal.quantity.isEmpty ? "1" : deal.quantity,
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
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isChatLoading else { return }

        chatInput = ""
        chatNotice = nil
        lastChatFailed = false
        let generation = AppState.shared.dataGeneration
        chatMessages.append(ChatMessage(role: "user", content: text))
        isChatLoading = true
        defer { isChatLoading = false }

        let appState = AppState.shared
        let favNames = ProductCatalogService.shared.nameFor(ids: appState.favoriteFoodIDs)

        // Only the most recent turns are needed for context; cap what is sent.
        let history = chatMessages.dropLast().suffix(Self.maxChatHistory).map {
            AgentChatHistoryItem(role: $0.role, content: $0.content)
        }
        log.reload()
        let context = AgentUserContext.make(profile: .load(), entries: log.entries, stock: StockStore.shared.items,
                                             preferences: .load(), favoriteFoods: favNames, lang: appState.lang)
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
            else { message = "Sorry, I couldn't reach Nourlo's AI. Please try again." }
            chatNotice = message
            lastChatFailed = true
        }
    }
}
