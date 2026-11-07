import Foundation
import CoreLocation

@MainActor
final class AgentLoop {

    private var task: Task<Void, Never>?
    private var regenTask: Task<Void, Never>?
    private var cartObserver: NSObjectProtocol?
    private weak var appState: AppState?
    private var dataGeneration = 0

    /// Invalidates responses that were requested before the user's data was erased.
    func invalidateUserData() {
        dataGeneration += 1
        regenTask?.cancel()
        regenTask = nil
    }

    func start(appState: AppState) {
        stop()
        self.appState = appState
        // Curated estimates cannot support retailer alerts. Discard any old
        // in-memory alert queue when the loop restarts.
        appState.dealNotifications = []
        task = Task { [weak appState] in
            while !Task.isCancelled {
                if let appState { await tick(appState: appState) }
                // 5-minute cadence — battery/data friendly (was 30s).
                try? await Task.sleep(for: .seconds(300))
            }
        }
        // Regenerate the plan shortly after the shopping cart changes (debounced).
        cartObserver = NotificationCenter.default.addObserver(
            forName: .cartDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRegen() }
        }
    }

    func stop() {
        task?.cancel(); task = nil
        regenTask?.cancel(); regenTask = nil
        if let cartObserver {
            NotificationCenter.default.removeObserver(cartObserver)
            self.cartObserver = nil
        }
    }

    /// Coalesces rapid cart edits into a single plan regeneration.
    private func scheduleRegen() {
        regenTask?.cancel()
        regenTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, let appState = self.appState else { return }
            await self.regenerateMealPlan(appState: appState)
        }
    }

    // MARK: - Tick

    private func tick(appState: AppState) async {
        guard appState.isOnboarded else { return }
        let generation = dataGeneration
        // 1. Refresh deals — pass user location for server-side proximity filter
        let userLoc = LocationService.shared.userLocation
        let hadNoDeals = appState.activeDeals.isEmpty
        let deals: [Deal]
        if let loc = userLoc {
            deals = (try? await APIService.shared.getDeals(near: loc.coordinate.latitude,
                                                           lon: loc.coordinate.longitude,
                                                           radiusKm: 8)) ?? []
        } else {
            deals = (try? await APIService.shared.getDeals()) ?? []
        }
        guard !Task.isCancelled, generation == dataGeneration else { return }
        if !deals.isEmpty { appState.activeDeals = deals }

        // Catalog estimates still support browsing/planning, but never generate
        // discount, proximity, availability or expiry notifications.

        // 5. Regenerate meal plan if needed
        let currentCount = appState.groceryList.count
        let needsPlan = appState.weeklyMealPlan == nil
        let listGrew  = currentCount > appState.lastGroceryCount
        let needsDailyRefresh = isDueForDailyRefresh()
        let dealsJustArrived = !deals.isEmpty && hadNoDeals
        if needsPlan || listGrew || needsDailyRefresh || dealsJustArrived {
            appState.lastGroceryCount = currentCount
            await regenerateMealPlan(appState: appState)
        }
    }

    private func isDueForDailyRefresh() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let key = "lastMealPlanGeneratedDate"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        if last < today {
            UserDefaults.standard.set(today, forKey: key)
            return true
        }
        return false
    }

    // MARK: - Meal plan regeneration

    private func regenerateMealPlan(appState: AppState) async {
        guard let bmr = appState.bmrData else { return }
        let generation = dataGeneration
        appState.isGeneratingMealPlan = true
        defer { appState.isGeneratingMealPlan = false }

        let profile = appState.userProfile
        let goalString: String = {
            switch profile.weightGoal {
            case .lose:     return "lose"
            case .maintain: return "maintain"
            case .gain:     return "gain"
            }
        }()

        let dietaryPrefs = Set<DietaryPreference>.load()
        let planUser = MealPlanUser(
            name:           "",
            age:            profile.age,
            gender:         profile.gender.rawValue,
            weight:         Double(Int(profile.weight)),
            height:         Double(Int(profile.height)),
            goal:           goalString,
            activityLevel:  profile.activityLevel.rawValue,
            dietaryOptions: dietaryPrefs.filter { !$0.isAllergy }.map(\.rawValue),
            allergies:      dietaryPrefs.filter { $0.isAllergy }.map(\.rawValue),
            favoriteFoods:  ProductCatalogService.shared.nameFor(ids: appState.favoriteFoodIDs)
        )

        let cartDeals = ShoppingCartService.shared.planDeals()
        let groceriesForPlan = cartDeals.isEmpty ? appState.groceryList : cartDeals
        let request = MealPlanRequest(
            user:        planUser,
            bmrData:     bmr,
            groceryList: groceriesForPlan,
            goal:        goalString,
            lang:        appState.lang
        )

        do {
            let plan = try await APIService.shared.generateMealPlan(request)
            guard !Task.isCancelled, generation == dataGeneration else { return }
            appState.saveMealPlan(plan)
            appLog("[AgentLoop] meal plan regenerated successfully")
        } catch {
            appLog("[AgentLoop] meal plan generation failed:", error)
        }
    }
}
