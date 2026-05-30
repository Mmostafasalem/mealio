import Foundation

// MARK: - Deal (from GET /api/deals)

struct Deal: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let brand: String
    let emoji: String
    let store: String
    let originalPrice: Double
    let discountedPrice: Double
    let discount: Int
    let category: String
    let kcalPer100g: Int
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
    let weeklyQty: Int
    let unit: String
    let expiresIn: String
    let allergens: [String]
    let latitude: Double?
    let longitude: Double?
}

// MARK: - BMR (POST /api/bmr request)

struct BMRRequest: Codable {
    let weight: Double
    let height: Double
    let age: Int
    let gender: String       // "male" | "female"
    let activityLevel: String
}

// MARK: - BMR Response

struct BMRResponse: Codable {
    let bmr: Int
    let tdee: Int
    let loseCalories: Int
    let maintainCalories: Int
    let gainCalories: Int
    let macros: MacroTargets

    struct MacroTargets: Codable {
        let protein: Int
        let carbs: Int
        let fat: Int
    }
}

// MARK: - Meal Plan (POST /api/meal-plan)

struct MealPlanRequest: Codable {
    let user: MealPlanUser
    let bmrData: BMRResponse
    let groceryList: [Deal]
    let goal: String   // "lose" | "maintain" | "gain"
    let lang: String   // "en" | "lt"
}

struct MealPlanUser: Codable {
    let name: String
    let age: Int
    let gender: String
    let weight: Double
    let height: Double
    let goal: String
    let activityLevel: String
    let dietaryOptions: [String]
    let allergies: [String]
    let favoriteFoods: [Int]
}

/// Full 7-day plan. Keys are always Lithuanian day names.
struct WeeklyMealPlan: Codable, Equatable {
    let agentMessage: String?
    let pirmadienis: DayPlan?
    let antradienis: DayPlan?
    let treciadienis: DayPlan?
    let ketvirtadienis: DayPlan?
    let pentadienis: DayPlan?
    let sestadienis: DayPlan?
    let sekmadienis: DayPlan?

    var allDays: [(label: String, plan: DayPlan)] {
        let pairs: [(String, DayPlan?)] = [
            ("Monday",    pirmadienis),
            ("Tuesday",   antradienis),
            ("Wednesday", treciadienis),
            ("Thursday",  ketvirtadienis),
            ("Friday",    pentadienis),
            ("Saturday",  sestadienis),
            ("Sunday",    sekmadienis)
        ]
        return pairs.compactMap { label, plan in plan.map { (label, $0) } }
    }
}

struct DayPlan: Codable, Equatable {
    let pusryciai: MealItem?   // breakfast
    let pietus: MealItem?      // lunch
    let vakariene: MealItem?   // dinner
    let uzkandziai: MealItem?  // snacks
    let visoKcal: Int?

    enum CodingKeys: String, CodingKey {
        case pusryciai
        case pietus = "pietūs"
        case vakariene
        case uzkandziai
        case visoKcal
    }
}

struct MealItem: Codable, Equatable {
    let pavadinimas: String    // name
    let ingredientai: [String] // ingredients
    let kcal: Int
}

// MARK: - Gap Fillers (POST /api/gap-fillers)

struct GapFillerRequest: Codable {
    let targetCalories: Int
    let macros: BMRResponse.MacroTargets
    let lang: String
}

struct GapFiller: Codable, Identifiable {
    var id: String { pavadinimas }
    let pavadinimas: String     // name
    let aprasymas: String       // description
    let kcal: Int
    let baltymai: Int           // protein
    let angliavandeniai: Int    // carbs
    let riebalai: Int           // fat
}

// MARK: - Nutritional gaps (computed locally, passed to shopping advice)

struct NutritionalGaps {
    let caloriesNeeded: Int
    let proteinNeeded: Double
    let carbsNeeded: Double
    let fatNeeded: Double
}

// MARK: - Shopping Advice (POST /api/shopping-advice)

struct ShoppingAdviceRequest: Codable {
    let groceryList: [Deal]
    let goal: String
    let macros: BMRResponse.MacroTargets
    let lang: String
}

struct ShoppingAdvice: Codable, Identifiable {
    var id: String { produktas }
    let produktas: String       // product name
    let priezastis: String      // reason
    let apytiksleCena: String   // estimated price
    let kurPirkti: String       // where to buy
    let makroNauda: String      // macro benefit
}
