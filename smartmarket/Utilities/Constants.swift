import Foundation

// MARK: - Notification names used across the app
extension Notification.Name {
    static let mealPlanDidUpdate    = Notification.Name("mealPlanDidUpdate")
    static let groceryListDidChange = Notification.Name("groceryListDidChange")
    static let cartDidChange        = Notification.Name("cartDidChange")
    /// Ask Home to show Profile (it lives behind the avatar, not in the tab bar).
    static let openProfile          = Notification.Name("openProfile")
    /// Ask the tab bar to show Train (from a workout reminder).
    static let openTrain            = Notification.Name("openTrain")
    /// The bowl in Home's header was tapped: open or close its guide.
    static let toggleBowlGuide      = Notification.Name("toggleBowlGuide")
    static let personalDataDidChange = Notification.Name("personalDataDidChange")
}

// MARK: - Grocery list persistence (used by AppDelegate, ViewModels, and Views)
enum GroceryStorage {
    static func load() -> [GroceryItem] {
        ResilientStorage.loadArray(GroceryItem.self, key: Constants.Storage.groceryList)
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

    // MARK: - Support
    enum Support {
        static let email = "nourlo.app.support@gmail.com"
        static let mailURL = URL(string: "mailto:nourlo.app.support@gmail.com?subject=Nourlo%20support")!
    }

    // MARK: - API
    enum API {
        /// Base URL of the backend.
        /// Read from the `API_BASE_URL` key in Info.plist so it can be set per
        /// build configuration (via an xcconfig) without touching code.
        static let baseURL: String = infoPlistValue("API_BASE_URL") ?? defaultBaseURL

        /// Fallback used only when `API_BASE_URL` is absent/empty. In DEBUG this
        /// is the local dev server; in release we fall back to the production
        /// HTTPS backend rather than a cleartext localhost URL, so a misconfigured
        /// build can never silently downgrade the connection to HTTP.
        #if DEBUG
        private static let defaultBaseURL = "http://localhost:5000"
        #else
        private static let defaultBaseURL = "https://mealio-backend-d7aa.onrender.com"
        #endif

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
            static let mealPlan         = "/api/meal-plan"
            static let shoppingAdvice   = "/api/shopping-advice"
            static let agentChat        = "/api/agent-chat"
            static let recipe           = "/api/recipe"
            static let workout          = "/api/workout"
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
        /// "" follows the iPhone setting, otherwise "light" or "dark" (set by the pull cord in Profile).
        static let appearanceOverride       = "appearanceOverride_v1"
        /// "kg" or "lb" — display only; weight is always stored in kg.
        static let weightUnit               = "weightUnit_v1"
        /// "cm" or "ft" — display only; height is always stored in cm.
        static let heightUnit               = "heightUnit_v1"
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
