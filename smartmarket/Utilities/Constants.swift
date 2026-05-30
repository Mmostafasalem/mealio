import Foundation

enum Constants {

    // MARK: - API
    enum API {
        /// Update this when the ngrok tunnel restarts.
        static let baseURL = "https://pastime-diagram-chalice.ngrok-free.dev"

        enum Endpoint {
            static let health           = "/api/health"
            static let deals            = "/api/deals"
            static let bmr              = "/api/bmr"
            static let mealPlan         = "/api/meal-plan"
            static let gapFillers       = "/api/gap-fillers"
            static let shoppingAdvice   = "/api/shopping-advice"
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
