import Foundation
import CoreLocation

@MainActor
final class AgentLoop {

    private var task: Task<Void, Never>?
    private var regenTask: Task<Void, Never>?
    private var cartObserver: NSObjectProtocol?
    private weak var appState: AppState?

    func start(appState: AppState) {
        stop()
        self.appState = appState
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
        if !deals.isEmpty { appState.activeDeals = deals }

        // 2. Resolve favorited product IDs → lowercase name tokens for fuzzy matching.
        //    This replaces the old broken backendId integer approach.
        let favNames: [String] = ProductCatalogService.shared.nameFor(ids: appState.favoriteFoodIDs)

        // 3. Match deals whose name contains any favorited product name (or vice versa)
        let matched = deals.filter { deal in
            let dealName = deal.name.lowercased()
            let nameMatch = favNames.contains { fav in
                dealName.contains(fav) || fav.contains(dealName.prefix(8))
            }
            guard nameMatch else { return false }
            guard let loc = userLoc else { return true }

            let storeLat = deal.latitude ?? APIService.storeCoordinates(for: deal.store).lat
            let storeLon = deal.longitude ?? APIService.storeCoordinates(for: deal.store).lon
            let storeLoc = CLLocation(latitude: storeLat, longitude: storeLon)
            return loc.distance(from: storeLoc) <= 8_000
        }

        // 4. Fire push notification for each new match (persisted so they don't repeat on relaunch)
        for deal in matched where !appState.notifiedDealIds.contains(deal.id) {
            appState.dealNotifications.append(deal)
            appState.saveNotifiedDealId(deal.id)
            NotificationService.shared.scheduleDealNotification(
                for: deal,
                storeName: deal.store,
                storeId: "\(deal.id)"
            )
        }

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
            name:           profile.name,
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
            appState.saveMealPlan(plan)
            appLog("[AgentLoop] meal plan regenerated successfully")
        } catch {
            appLog("[AgentLoop] meal plan generation failed:", error)
        }
    }
}
