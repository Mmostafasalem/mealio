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
    @MainActor static func from(weekly: WeeklyMealPlan) -> MealPlan? {
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

        // Use stored BMR macro targets to estimate per-meal macros proportionally
        let bmrMacros = AppState.shared.bmrData?.macros
        let targetKcal = Double(AppState.shared.bmrData?.loseCalories ?? AppState.shared.bmrData?.maintainCalories ?? 1800)
        let dayKcal = Double(day.visoKcal ?? Int(targetKcal))

        func scaledMacro(_ target: Double) -> Double {
            guard targetKcal > 0 else { return 0 }
            return (target * dayKcal / targetKcal).rounded()
        }

        let totalProtein = scaledMacro(Double(bmrMacros?.protein ?? 150))
        let totalCarbs   = scaledMacro(Double(bmrMacros?.carbs   ?? 200))
        let totalFat     = scaledMacro(Double(bmrMacros?.fat     ?? 60))

        func entry(_ item: MealItem?, mealFraction: Double) -> [MealEntry] {
            guard let item else { return [] }
            let kcal = item.kcal
            let fraction = dayKcal > 0 ? Double(kcal) / dayKcal : mealFraction
            return [MealEntry(
                id: UUID().uuidString,
                foodName: item.pavadinimas,
                portionG: Int((Double(kcal) / 2.0).rounded()),
                calories: kcal,
                proteinG: (totalProtein * fraction).rounded(),
                carbsG:   (totalCarbs   * fraction).rounded(),
                fatG:     (totalFat     * fraction).rounded(),
                notes: item.ingredientai.joined(separator: ", ")
            )]
        }

        return MealPlan(
            id: UUID().uuidString,
            date: Date(),
            breakfast: entry(day.pusryciai, mealFraction: 0.25),
            lunch:     entry(day.pietus,    mealFraction: 0.35),
            dinner:    entry(day.vakariene, mealFraction: 0.30),
            snacks:    entry(day.uzkandziai, mealFraction: 0.10),
            totalCalories:  day.visoKcal ?? 0,
            totalProteinG:  totalProtein,
            totalCarbsG:    totalCarbs,
            totalFatG:      totalFat,
            agentNotes:     weekly.agentMessage ?? ""
        )
    }
}
