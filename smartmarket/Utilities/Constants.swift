import Foundation

// MARK: - Notification names used across the app
extension Notification.Name {
    static let mealPlanDidUpdate    = Notification.Name("mealPlanDidUpdate")
    static let groceryListDidChange = Notification.Name("groceryListDidChange")
    static let cartDidChange        = Notification.Name("cartDidChange")
}

// MARK: - Grocery list persistence (used by AppDelegate, ViewModels, and Views)
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

    /// Adds item only if no existing entry has the same foodId + storeName combo.
    static func add(_ item: GroceryItem) {
        var list = load()
        guard !list.contains(where: { $0.foodId == item.foodId && $0.storeName == item.storeName }) else { return }
        list.append(item)
        save(list)
    }
}

enum Constants {

    // MARK: - API
    enum API {
        /// Base URL of the backend.
        /// Read from the `API_BASE_URL` key in Info.plist so it can be set per
        /// build configuration (via an xcconfig) without touching code.
        /// Falls back to the local dev server if the key is absent/empty.
        static let baseURL: String = infoPlistValue("API_BASE_URL")
            ?? "http://localhost:5000"

        /// Shared secret that must match the backend's `APP_API_KEY` env var.
        /// Read from the `API_KEY` key in Info.plist. Empty string disables auth
        /// (dev only — the backend treats a blank key as "open").
        static let appKey: String = infoPlistValue("API_KEY") ?? ""

        /// Reads a non-empty string from the app's Info.plist, or nil.
        private static func infoPlistValue(_ key: String) -> String? {
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
                  !value.trimmingCharacters(in: .whitespaces).isEmpty
            else { return nil }
            return value
        }

        enum Endpoint {
            static let health           = "/api/health"
            static let products         = "/api/products"
            static let deals            = "/api/deals"
            static let bmr              = "/api/bmr"
            static let mealPlan         = "/api/meal-plan"
            static let gapFillers       = "/api/gap-fillers"
            static let shoppingAdvice   = "/api/shopping-advice"
            static let agentChat        = "/api/agent-chat"
            static let recipe           = "/api/recipe"
        }
    }

    // MARK: - UserDefaults keys
    enum Storage {
        static let hasCompletedOnboarding   = "hasCompletedOnboarding"
        static let userProfile              = "userProfile"
        static let bmrResponse              = "bmrResponse"
        static let favoriteFoodIDs          = "favoriteFoodIDs"
        static let selectedDietaryFilters   = "selectedDietaryFilters"
        static let groceryList              = "groceryList"
        static let groceryDeals             = "groceryDeals"
        static let caloriesConsumedToday    = "caloriesConsumedToday"
        static let loggedMealEntries        = "loggedMealEntries"
        static let currentMealPlan          = "currentMealPlan"
        static let notifiedDealIds          = "notifiedDealIds"
        static let lang                     = "lang"
    }

    // MARK: - BMR safety floors
    enum Calories {
        static let minimumFemale: Int = 1200
        static let minimumMale: Int   = 1500
        static let minimumOther: Int  = 1200
    }

    // MARK: - Onboarding limits
    enum Onboarding {
        static let minimumFavorites = 5
    }
}
