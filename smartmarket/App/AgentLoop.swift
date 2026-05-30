import Foundation

@MainActor
final class AgentLoop {

    private var task: Task<Void, Never>?

    func start(appState: AppState) {
        stop()
        task = Task { [weak appState] in
            while !Task.isCancelled {
                if let appState {
                    await tick(appState: appState)
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - Tick

    private func tick(appState: AppState) async {
        // 1. Refresh deals
        let deals = try? await APIService.shared.getDeals()
        if let deals {
            appState.activeDeals = deals
        }

        // 2. Match deals against user favourite food backend IDs
        let favStringIDs = appState.favoriteFoodIDs
        let favBackendIDs: Set<Int> = Set(
            Food.catalog
                .filter { favStringIDs.contains($0.id) }
                .compactMap { $0.backendId }
        )
        let matched = (deals ?? []).filter { favBackendIDs.contains($0.id) }

        // 3. Surface new matched deals as in-app notifications
        for deal in matched where !appState.notifiedDealIds.contains(deal.id) {
            appState.dealNotifications.append(deal)
            appState.notifiedDealIds.insert(deal.id)
        }

        // 4. Regenerate meal plan if no plan exists yet, or if grocery list grew
        let currentCount = appState.groceryList.count
        let needsPlan = appState.weeklyMealPlan == nil
        let listGrew  = currentCount > appState.lastGroceryCount

        if needsPlan || listGrew {
            appState.lastGroceryCount = currentCount
            await regenerateMealPlan(appState: appState)
        }
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

        let planUser = MealPlanUser(
            name:             profile.name,
            age:              profile.age,
            gender:           profile.gender.rawValue,
            weight:           Double(Int(profile.weight)),
            height:           Double(Int(profile.height)),
            goal:             goalString,
            activityLevel:    profile.activityLevel.rawValue,
            dietaryOptions:   [],
            allergies:        [],
            favoriteFoods:    Food.catalog
                                  .filter { appState.favoriteFoodIDs.contains($0.id) }
                                  .compactMap { $0.backendId }
        )

        let request = MealPlanRequest(
            user:        planUser,
            bmrData:     bmr,
            groceryList: appState.groceryList,
            goal:        goalString,
            lang:        appState.lang
        )

        if let plan = try? await APIService.shared.generateMealPlan(request) {
            appState.saveMealPlan(plan)
        }
    }
}
