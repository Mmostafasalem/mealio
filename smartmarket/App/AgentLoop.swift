import Foundation
import CoreLocation

@MainActor
final class AgentLoop {

    private var task: Task<Void, Never>?

    func start(appState: AppState) {
        stop()
        task = Task { [weak appState] in
            while !Task.isCancelled {
                if let appState { await tick(appState: appState) }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    // MARK: - Tick

    private func tick(appState: AppState) async {
        // 1. Refresh deals — pass user location for server-side proximity filter
        let userLoc = LocationService.shared.userLocation
        let deals: [Deal]
        if let loc = userLoc {
            deals = (try? await APIService.shared.getDeals(near: loc.coordinate.latitude,
                                                           lon: loc.coordinate.longitude,
                                                           radiusKm: 8)) ?? []
        } else {
            deals = (try? await APIService.shared.getDeals()) ?? []
        }
        if !deals.isEmpty { appState.activeDeals = deals }

        // 2. User's favourite catalog-string IDs → backend Int IDs
        let favStringIDs = appState.favoriteFoodIDs
        let favBackendIDs: Set<Int> = Set(
            Food.catalog
                .filter { favStringIDs.contains($0.id) }
                .compactMap { $0.backendId }
        )

        // 3. Match deals that are for a favourite food and nearby
        let matched = deals.filter { deal in
            guard favBackendIDs.contains(deal.id) else { return false }
            guard let loc = userLoc else { return true }

            let storeLat = deal.latitude ?? APIService.storeCoordinates(for: deal.store).lat
            let storeLon = deal.longitude ?? APIService.storeCoordinates(for: deal.store).lon
            let storeLoc = CLLocation(latitude: storeLat, longitude: storeLon)
            return loc.distance(from: storeLoc) <= 8_000
        }

        // 4. Fire push notification for each new match
        for deal in matched where !appState.notifiedDealIds.contains(deal.id) {
            appState.dealNotifications.append(deal)
            appState.notifiedDealIds.insert(deal.id)
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
            name:           profile.name,
            age:            profile.age,
            gender:         profile.gender.rawValue,
            weight:         Double(Int(profile.weight)),
            height:         Double(Int(profile.height)),
            goal:           goalString,
            activityLevel:  profile.activityLevel.rawValue,
            dietaryOptions: [],
            allergies:      [],
            favoriteFoods:  Food.catalog
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
