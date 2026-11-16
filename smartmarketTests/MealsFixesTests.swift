import XCTest
@testable import smartmarket

@MainActor
final class MealsFixesTests: XCTestCase {

    private var savedDomain: [String: Any] = [:]
    private let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"

    override func setUp() async throws {
        savedDomain = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
    }

    override func tearDown() async throws {
        UserDefaults.standard.setPersistentDomain(savedDomain, forName: domain)
    }

    // MARK: - Tick decision

    private func inputs(hasPlan: Bool = true, count: Int = 0, baseline: Int? = nil,
                        due: Bool = false, requested: Bool = false, consent: Bool = true,
                        failure: Date? = nil, now: Date = Date()) -> AgentLoop.RegenerationInputs {
        AgentLoop.RegenerationInputs(hasPlan: hasPlan, groceryCount: count, groceryBaseline: baseline,
                                     dueForDailyRefresh: due, refreshRequested: requested,
                                     hasAIConsent: consent, lastFailure: failure, now: now)
    }

    func testFirstTickWithRestoredLegacyListOnlySetsBaseline() {
        // A list loaded from disk on launch has no baseline yet: no regeneration.
        XCTAssertFalse(AgentLoop.shouldAttemptOnlineRegeneration(inputs(count: 5, baseline: nil)))
        // A real addition after the baseline does trigger one.
        XCTAssertTrue(AgentLoop.shouldAttemptOnlineRegeneration(inputs(count: 6, baseline: 5)))
        XCTAssertFalse(AgentLoop.shouldAttemptOnlineRegeneration(inputs(count: 5, baseline: 5)))
    }

    func testFreshPlanIsNotRegeneratedOnLaunch() {
        // Deals are no longer an input at all; a fresh plan with nothing changed stays.
        XCTAssertFalse(AgentLoop.shouldAttemptOnlineRegeneration(inputs()))
    }

    func testDailyRefreshAndMissingPlanAndProfileRequestTrigger() {
        XCTAssertTrue(AgentLoop.shouldAttemptOnlineRegeneration(inputs(due: true)))
        XCTAssertTrue(AgentLoop.shouldAttemptOnlineRegeneration(inputs(hasPlan: false)))
        XCTAssertTrue(AgentLoop.shouldAttemptOnlineRegeneration(inputs(requested: true)))
    }

    func testFailedRefreshBacksOffForAnHour() {
        let now = Date()
        XCTAssertFalse(AgentLoop.shouldAttemptOnlineRegeneration(
            inputs(due: true, failure: now.addingTimeInterval(-60), now: now)))
        XCTAssertFalse(AgentLoop.shouldAttemptOnlineRegeneration(
            inputs(due: true, failure: now.addingTimeInterval(-3500), now: now)))
        XCTAssertTrue(AgentLoop.shouldAttemptOnlineRegeneration(
            inputs(due: true, failure: now.addingTimeInterval(-3700), now: now)))
    }

    func testNoOnlineAttemptWithoutConsent() {
        XCTAssertFalse(AgentLoop.shouldAttemptOnlineRegeneration(inputs(hasPlan: false, consent: false)))
        XCTAssertFalse(AgentLoop.shouldAttemptOnlineRegeneration(inputs(due: true, consent: false)))
        XCTAssertFalse(AgentLoop.shouldAttemptOnlineRegeneration(inputs(requested: true, consent: false)))
    }

    func testConsentFlagIsReadFromStorage() {
        UserDefaults.standard.set(false, forKey: "aiSharingConsent_v1")
        let service = APIService(authorization: { "Bearer test" })
        XCTAssertFalse(service.hasAIConsent)
        UserDefaults.standard.set(true, forKey: "aiSharingConsent_v1")
        XCTAssertTrue(service.hasAIConsent)
    }

    func testSuccessfulPlanClearsBackoffAndRefreshRequest() {
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: AgentLoop.lastFailureKey)
        defaults.set(true, forKey: AgentLoop.refreshRequestedKey)
        defaults.removeObject(forKey: AgentLoop.lastPlanDateKey)
        XCTAssertTrue(AgentLoop.isDueForDailyRefresh(defaults: defaults))
        AgentLoop.markPlanGeneratedToday(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: AgentLoop.lastFailureKey))
        XCTAssertFalse(defaults.bool(forKey: AgentLoop.refreshRequestedKey))
        XCTAssertFalse(AgentLoop.isDueForDailyRefresh(defaults: defaults))
    }

    // MARK: - Shared request slot

    func testUserRegenerateTakesOverFromBackgroundRequest() throws {
        // A separate state, so the app's live agent loop can't claim the slot mid-test.
        let state = AppState()
        let background = try XCTUnwrap(state.beginMealPlanRequest(.background))
        XCTAssertTrue(state.isGeneratingMealPlan)
        XCTAssertNil(state.beginMealPlanRequest(.background), "a second background request must wait")
        let user = try XCTUnwrap(state.beginMealPlanRequest(.user))
        XCTAssertFalse(state.ownsMealPlanRequest(background), "the background result must be discarded")
        XCTAssertNil(state.beginMealPlanRequest(.user), "only one user request at a time")
        state.endMealPlanRequest(background)
        XCTAssertTrue(state.isGeneratingMealPlan, "the old request must not clear the user's flag")
        state.endMealPlanRequest(user)
        XCTAssertFalse(state.isGeneratingMealPlan)
    }

    // MARK: - Profile changes

    private func plan(source: String?, kcal: Int) -> WeeklyMealPlan {
        func meal(_ k: Int) -> MealItem { MealItem(pavadinimas: "Meal", ingredientai: [], kcal: k) }
        let d = DayPlan(pusryciai: meal(kcal / 4), pietus: meal(kcal * 35 / 100), vakariene: meal(kcal * 3 / 10),
                        uzkandziai: meal(kcal / 10), visoKcal: kcal)
        var p = WeeklyMealPlan(agentMessage: nil, pirmadienis: d, antradienis: d, treciadienis: d,
                               ketvirtadienis: d, pentadienis: d, sestadienis: d, sekmadienis: d)
        p.generationSource = source
        return p
    }

    func testProfileChangeRebuildsLocalPlanAndKeepsFittingOnlinePlan() {
        XCTAssertEqual(AgentLoop.profileChangeAction(for: nil, target: 2000), .rebuildLocally)
        XCTAssertEqual(AgentLoop.profileChangeAction(for: plan(source: "local", kcal: 2000), target: 2000),
                       .rebuildLocally)
        XCTAssertEqual(AgentLoop.profileChangeAction(for: plan(source: "online", kcal: 2000), target: 2100),
                       .requestRefresh)
        XCTAssertEqual(AgentLoop.profileChangeAction(for: plan(source: "online", kcal: 2000), target: 3500),
                       .rebuildLocally)
    }

    private func planInputs(target: Int = 2000, goal: String = "maintain", diet: [String] = [],
                            favourites: [String] = []) -> AgentLoop.PlanInputs {
        AgentLoop.PlanInputs(calorieTarget: target, weightGoal: goal, dietaryPreferences: diet,
                             favoriteFoodIDs: favourites)
    }

    func testUnrelatedSyncDoesNotTouchThePlan() {
        let built = planInputs(diet: ["vegan"], favourites: ["lasisa"])
        // Same inputs (a sync pull or a save that changed nothing relevant): keep.
        XCTAssertEqual(AgentLoop.profileChangeAction(for: plan(source: "online", kcal: 2000), target: 2000,
                                                     builtFor: built, current: built), .keep)
        XCTAssertEqual(AgentLoop.profileChangeAction(for: plan(source: "local", kcal: 2000), target: 2000,
                                                     builtFor: built, current: built), .keep)
        // Inputs never recorded (plan saved before this version): keep, adopt them.
        XCTAssertEqual(AgentLoop.profileChangeAction(for: plan(source: "online", kcal: 2000), target: 2000,
                                                     builtFor: nil, current: built), .keep)
        // No plan at all: build one.
        XCTAssertEqual(AgentLoop.profileChangeAction(for: nil, target: 2000, builtFor: built, current: built),
                       .rebuildLocally)
    }

    func testChangedInputsUpdateThePlan() {
        let built = planInputs()
        XCTAssertEqual(AgentLoop.profileChangeAction(for: plan(source: "online", kcal: 2000), target: 2000,
                                                     builtFor: built, current: planInputs(diet: ["vegan"])),
                       .requestRefresh)
        XCTAssertEqual(AgentLoop.profileChangeAction(for: plan(source: "online", kcal: 2000), target: 2000,
                                                     builtFor: built, current: planInputs(favourites: ["lasisa"])),
                       .requestRefresh)
        XCTAssertEqual(AgentLoop.profileChangeAction(for: plan(source: "online", kcal: 2000), target: 3500,
                                                     builtFor: built, current: planInputs(target: 3500)),
                       .rebuildLocally)
        XCTAssertEqual(AgentLoop.profileChangeAction(for: plan(source: "local", kcal: 2000), target: 2000,
                                                     builtFor: built, current: planInputs(goal: "lose")),
                       .rebuildLocally)
    }

    func testPlanInputsArePersisted() throws {
        let suite = "MealsFixesTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(AgentLoop.storedPlanInputs(defaults: defaults))
        let inputs = planInputs(target: 1800, diet: ["keto", "vegan"], favourites: ["a", "b"])
        AgentLoop.recordPlanInputs(inputs, defaults: defaults)
        XCTAssertEqual(AgentLoop.storedPlanInputs(defaults: defaults), inputs)
        AgentLoop.recordPlanInputs(nil, defaults: defaults)
        XCTAssertNil(AgentLoop.storedPlanInputs(defaults: defaults))
    }

    // MARK: - Failed online plans

    func testFailedAIKeepsTheSavedPlan() {
        // Off-target replies and failures both throw when a plan is saved,
        // so the caller keeps it and backs off.
        XCTAssertThrowsError(try APIService.fallbackMealPlan(after: APIError.unverifiedAIResponse,
                                                             hasSavedPlan: true, target: 2000))
    }

    func testFailedAIWithNoPlanGivesALocalPlanThatIsNotCountedAsAI() throws {
        let local = try APIService.fallbackMealPlan(after: APIError.unverifiedAIResponse,
                                                    hasSavedPlan: false, target: 2000)
        XCTAssertEqual(local.generationSource, "local")
        XCTAssertFalse(AgentLoop.isAIPlan(local), "a local fallback must not stamp the day")
        XCTAssertTrue(AgentLoop.isAIPlan(plan(source: "online", kcal: 2000)))
    }

    func testLocalFallbackStartsTheBackoff() throws {
        let suite = "MealsFixesTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        AgentLoop.noteRefreshFailed(defaults: defaults, now: now)
        let failure = defaults.object(forKey: AgentLoop.lastFailureKey) as? Date
        XCTAssertEqual(failure?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertFalse(AgentLoop.shouldAttemptOnlineRegeneration(
            inputs(due: true, failure: failure, now: now.addingTimeInterval(60))))
        XCTAssertTrue(AgentLoop.isDueForDailyRefresh(defaults: defaults), "the day stays unstamped")
    }

    func testOffTargetPlanIsNotReplacedInALoop() {
        let current = plan(source: "local", kcal: 2000)
        // The best local plan is the same plan: keep it, don't re-save every tick.
        XCTAssertNil(AgentLoop.replacement(for: current, target: 3800, build: { current }))
        // An online plan is never swapped for a local one that misses too.
        let online = plan(source: "online", kcal: 2000)
        XCTAssertNil(AgentLoop.replacement(for: online, target: 3800, build: { self.plan(source: "local", kcal: 2100) }))
        // An on-target replacement is used.
        XCTAssertNotNil(AgentLoop.replacement(for: online, target: 3800, build: { self.plan(source: "local", kcal: 3800) }))
        XCTAssertNil(AgentLoop.replacement(for: online, target: 2000, build: { current }))
    }

    // MARK: - Offline planner

    private func setCart(_ rows: [(id: String, category: String, price: Double)]) throws {
        let items = rows.map {
            CartItem(id: UUID(), catalogId: $0.id, name: $0.id.replacingOccurrences(of: "-", with: " ").capitalized,
                     store: ShopStore.catalog.name, price: $0.price, category: $0.category, quantity: 1)
        }
        UserDefaults.standard.set(try JSONEncoder().encode(items), forKey: "shoppingCart_v1")
    }

    private func assertPlannerReachesTargets(file: StaticString = #filePath, line: UInt = #line) {
        for target in [1300, 2000, 3000, 3800, 4000] {
            let weekly = FallbackData.mealPlan(targetKcal: target, pantry: [], preferences: [])
            XCTAssertTrue(weekly.isOnTarget(target),
                          "\(target) kcal: days \(weekly.allDays.map { $0.plan.visoKcal ?? 0 })", file: file, line: line)
        }
    }

    func testPlannerReachesTargetsWithoutCart() {
        UserDefaults.standard.removeObject(forKey: "shoppingCart_v1")
        GroceryStorage.save([])
        assertPlannerReachesTargets()
    }

    func testPlannerReachesTargetsWithBalancedCart() throws {
        try setCart([("chicken-breast", "meat", 5), ("white-rice", "grains", 2), ("broccoli", "vegetables", 1),
                     ("banana", "fruits", 1), ("greek-yogurt", "dairy", 2), ("almonds", "nuts", 3)])
        assertPlannerReachesTargets()
    }

    func testPlannerReachesTargetsWithLightFoods() throws {
        try setCart([("cod-fillet", "fish", 6), ("cucumber", "vegetables", 1), ("strawberries", "fruits", 3),
                     ("milk-25", "dairy", 1), ("spaghetti", "pasta", 1)])
        assertPlannerReachesTargets()
    }

    func testPlannerReachesTargetsWithDenseFoods() throws {
        try setCart([("bacon", "meat", 4), ("white-bread", "bread", 2), ("cheddar", "dairy", 3)])
        assertPlannerReachesTargets()
    }

    // MARK: - Plan messages

    func testBudgetIsOnlyClaimedWhenTheCartFits() {
        let within = FallbackData.cartMessage(itemCount: 3, total: 42.5, budget: 60)
        XCTAssertTrue(within.contains("within your €60.00 budget"), within)
        let over = FallbackData.cartMessage(itemCount: 3, total: 75, budget: 60)
        XCTAssertFalse(over.contains("within"), over)
        XCTAssertTrue(over.contains("€15.00 over your €60.00 budget"), over)
        XCTAssertFalse(FallbackData.cartMessage(itemCount: 1, total: 5, budget: 0).contains("budget"))
    }

    func testOverBudgetCartPlanSaysSo() throws {
        UserDefaults.standard.set(20.0, forKey: "weeklyBudget")
        try setCart([("chicken-breast", "meat", 15), ("white-rice", "grains", 10)])
        let message = FallbackData.mealPlan(targetKcal: 2000, pantry: [], preferences: []).agentMessage ?? ""
        XCTAssertTrue(message.contains("over your €20.00 budget"), message)
    }

    func testCartWithoutMealFoodsIsNotClaimed() throws {
        try setCart([("olive-oil", "oils", 6), ("cola", "beverages", 2), ("ketchup", "condiments", 1)])
        let weekly = FallbackData.mealPlan(targetKcal: 2000, pantry: [], preferences: [])
        let message = weekly.agentMessage ?? ""
        XCTAssertFalse(message.contains("built around your cart"), message)
        XCTAssertTrue(weekly.isOnTarget(2000))
    }

    func testCartThatFillsMealsIsClaimed() throws {
        try setCart([("chicken-breast", "meat", 5)])
        let message = FallbackData.mealPlan(targetKcal: 2000, pantry: [], preferences: []).agentMessage ?? ""
        XCTAssertTrue(message.contains("built around your cart"), message)
    }

    // MARK: - Deals and URLs

    func testOneMalformedDealDoesNotDiscardTheRest() throws {
        let good = try JSONEncoder().encode(Array(FallbackData.deals.prefix(2)))
        var array = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [Any])
        array.insert(["id": "not-a-number", "name": 5], at: 1)
        let data = try JSONSerialization.data(withJSONObject: array)
        let deals = try APIService.decodeDeals(data)
        XCTAssertEqual(deals.map(\.id), FallbackData.deals.prefix(2).map(\.id))
        XCTAssertTrue(try APIService.decodeDeals(Data("[{\"id\":1}]".utf8)).isEmpty)
    }

    func testProductFiltersArePercentEncoded() throws {
        let url = try XCTUnwrap(APIService.productsURL(baseURL: "https://example.com", store: "A&B Store",
                                                       category: "fruit+veg", query: "crème fraîche"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/products")
        let query = try XCTUnwrap(components.percentEncodedQuery)
        XCTAssertFalse(query.contains("A&B"))
        XCTAssertFalse(query.contains(" "))
        XCTAssertTrue(query.contains("fruit%2Bveg"), query)
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["store"], "A&B Store")
        XCTAssertEqual(values["category"], "fruit+veg")
        XCTAssertEqual(values["q"], "crème fraîche")
        XCTAssertEqual(APIService.productsURL(baseURL: "https://example.com")?.absoluteString,
                       "https://example.com/api/products")
    }

    // MARK: Daily cap on failed online attempts

    func testFailedOnlineAttemptsStopForTheDayAfterThree() {
        let now = Date()
        var i = AgentLoop.RegenerationInputs(hasPlan: true, groceryCount: 0, groceryBaseline: 0,
                                             dueForDailyRefresh: true, refreshRequested: false,
                                             hasAIConsent: true, lastFailure: nil, now: now)
        i.failuresToday = 2
        XCTAssertTrue(AgentLoop.shouldAttemptOnlineRegeneration(i))
        i.failuresToday = AgentLoop.maxFailuresPerDay
        XCTAssertFalse(AgentLoop.shouldAttemptOnlineRegeneration(i), "a saved plan stays after three failures today")
        i.hasPlan = false
        XCTAssertTrue(AgentLoop.shouldAttemptOnlineRegeneration(i), "with no plan at all it may still try")
    }

    func testFailureCountIsPerDayAndClearedBySuccess() {
        let defaults = UserDefaults(suiteName: "MealsFixesTests.failures")!
        defaults.removePersistentDomain(forName: "MealsFixesTests.failures")
        let day = Date()
        AgentLoop.noteRefreshFailed(defaults: defaults, now: day)
        AgentLoop.noteRefreshFailed(defaults: defaults, now: day)
        XCTAssertEqual(AgentLoop.failuresToday(defaults: defaults, now: day), 2)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        XCTAssertEqual(AgentLoop.failuresToday(defaults: defaults, now: tomorrow), 0)
        AgentLoop.markPlanGeneratedToday(defaults: defaults)
        XCTAssertEqual(AgentLoop.failuresToday(defaults: defaults, now: day), 0)
        defaults.removePersistentDomain(forName: "MealsFixesTests.failures")
    }
}
