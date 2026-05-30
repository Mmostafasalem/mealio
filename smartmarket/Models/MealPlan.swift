import Foundation

// MARK: - Meal entry (one food item inside a meal)
struct MealEntry: Codable, Identifiable {
    let id: String
    let foodName: String
    let portionG: Int
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let notes: String?          // e.g. "grilled", "steamed"

    enum CodingKeys: String, CodingKey {
        case id, calories, notes
        case foodName  = "food_name"
        case portionG  = "portion_g"
        case proteinG  = "protein_g"
        case carbsG    = "carbs_g"
        case fatG      = "fat_g"
    }
}

// MARK: - Full meal plan for one day (matches Python POST /meal-plan response)
struct MealPlan: Codable, Identifiable {
    let id: String
    let date: Date
    let breakfast: [MealEntry]
    let lunch: [MealEntry]
    let dinner: [MealEntry]
    let snacks: [MealEntry]
    let totalCalories: Int
    let totalProteinG: Double
    let totalCarbsG: Double
    let totalFatG: Double
    let agentNotes: String      // agent explains why this plan was chosen

    var allMeals: [(title: String, sfSymbol: String, entries: [MealEntry])] {
        [
            ("Breakfast", "sunrise.fill",   breakfast),
            ("Lunch",     "sun.max.fill",   lunch),
            ("Dinner",    "moon.fill",      dinner),
            ("Snacks",    "sparkles",       snacks),
        ]
    }

    enum CodingKeys: String, CodingKey {
        case id, date, breakfast, lunch, dinner, snacks
        case totalCalories = "total_calories"
        case totalProteinG = "total_protein_g"
        case totalCarbsG   = "total_carbs_g"
        case totalFatG     = "total_fat_g"
        case agentNotes    = "agent_notes"
    }
}

// MARK: - Grocery item
struct GroceryItem: Codable, Identifiable {
    var id: String
    var foodId: String
    var foodName: String
    var quantity: String        // "500g", "1kg", "2 units"
    var estimatedPrice: Double  // EUR
    var storeId: String
    var storeName: String
    var isBought: Bool

    enum CodingKeys: String, CodingKey {
        case id, quantity
        case foodId         = "food_id"
        case foodName       = "food_name"
        case estimatedPrice = "estimated_price"
        case storeId        = "store_id"
        case storeName      = "store_name"
        case isBought       = "is_bought"
    }
}

// MARK: - Shopping recommendation (from Python POST /recommendations)
struct ShoppingRecommendation: Codable, Identifiable {
    let id: String
    let foodName: String
    let reason: String
    let storeName: String
    let estimatedPrice: Double
    let priority: Int           // 1 = high, 3 = low

    enum CodingKeys: String, CodingKey {
        case id, reason, priority
        case foodName       = "food_name"
        case storeName      = "store_name"
        case estimatedPrice = "estimated_price"
    }
}

struct RecommendationsResponse: Codable {
    let items: [ShoppingRecommendation]
    let reasoning: String
}

// MARK: - Bridge from backend WeeklyMealPlan to legacy MealPlan

extension MealPlan {
    static func from(weekly: WeeklyMealPlan) -> MealPlan? {
        // weekday: 1=Sun 2=Mon 3=Tue 4=Wed 5=Thu 6=Fri 7=Sat
        let today = Calendar.current.component(.weekday, from: Date())
        let dayPlans: [DayPlan?] = [
            weekly.sekmadienis,   // 1 Sun
            weekly.pirmadienis,   // 2 Mon
            weekly.antradienis,   // 3 Tue
            weekly.treciadienis,  // 4 Wed
            weekly.ketvirtadienis,// 5 Thu
            weekly.pentadienis,   // 6 Fri
            weekly.sestadienis    // 7 Sat
        ]
        guard today >= 1 && today <= 7, let day = dayPlans[today - 1] else { return nil }

        func entry(_ item: MealItem?) -> [MealEntry] {
            guard let item else { return [] }
            return [MealEntry(
                id: UUID().uuidString,
                foodName: item.pavadinimas,
                portionG: 0,
                calories: item.kcal,
                proteinG: 0, carbsG: 0, fatG: 0,
                notes: item.ingredientai.joined(separator: ", ")
            )]
        }

        return MealPlan(
            id: UUID().uuidString,
            date: Date(),
            breakfast: entry(day.pusryciai),
            lunch:     entry(day.pietus),
            dinner:    entry(day.vakariene),
            snacks:    entry(day.uzkandziai),
            totalCalories:  day.visoKcal ?? 0,
            totalProteinG:  0,
            totalCarbsG:    0,
            totalFatG:      0,
            agentNotes:     weekly.agentMessage ?? ""
        )
    }
}
