import Foundation
import CryptoKit

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
    var nutritionIngredients: [NutritionIngredient]? = nil
    var stockOperationID: String? = nil

    /// Protein/carbs/fat are only known when the entry has ingredient
    /// portions. Otherwise the stored 0 g values mean "not available".
    var macrosAvailable: Bool { nutritionIngredients?.isEmpty == false }

    enum CodingKeys: String, CodingKey {
        case id, calories, notes, nutritionIngredients, stockOperationID
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

    /// Macro totals are meaningful only when every entry has ingredient
    /// portions; otherwise they'd under-count, so show them as unavailable.
    var macrosAvailable: Bool {
        let entries = breakfast + lunch + dinner + snacks
        return !entries.isEmpty && entries.allSatisfy(\.macrosAvailable)
    }

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
    var priceKnown: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id, quantity, priceKnown
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

        return from(day: day, date: Date(), notes: weekly.agentMessage ?? "")
    }

    static func entry(_ item: MealItem?) -> [MealEntry] {
        guard let item else { return [] }
        let ingredients = item.nutritionIngredients.flatMap { $0.isEmpty ? nil : $0 }
        let totals = ingredients?.map { $0.food.portion($0.amount) }
        let grams = ingredients?.allSatisfy { $0.food.basis == .grams } == true
            ? Int((ingredients?.reduce(0) { $0 + $1.amount } ?? 0).rounded()) : 0
        let calories = totals.map { Int($0.reduce(0) { $0 + $1.kcal }.rounded()) } ?? item.kcal
        return [MealEntry(id: UUID().uuidString, foodName: item.pavadinimas, portionG: grams,
                          calories: calories, proteinG: totals?.reduce(0) { $0 + $1.protein } ?? 0,
                          carbsG: totals?.reduce(0) { $0 + $1.carbs } ?? 0,
                          fatG: totals?.reduce(0) { $0 + $1.fat } ?? 0,
                          notes: ingredients?.map { "\($0.food.name) · \($0.amount.formatted()) \($0.food.basis.rawValue)" }.joined(separator: ", ") ?? item.ingredientai.joined(separator: ", "),
                          nutritionIngredients: ingredients)]
    }

    static func from(day: DayPlan, date: Date, notes: String) -> MealPlan {
        func meals(_ item: MealItem?, slot: MealSlot) -> [MealEntry] {
            var entries = entry(item)
            guard let item, entries.first?.macrosAvailable == true else { return entries }
            let dayStamp = String(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
            let portions = (item.portions ?? []).map { "\($0.foodID):\($0.amount)" }.joined(separator: "|")
            let payload = dayStamp + "|" + slot.rawValue + "|" + item.pavadinimas + "|" + portions
            entries[0].stockOperationID = SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
            return entries
        }
        let breakfast = meals(day.pusryciai, slot: .breakfast), lunch = meals(day.pietus, slot: .lunch)
        let dinner = meals(day.vakariene, slot: .dinner), snacks = meals(day.uzkandziai, slot: .snack)
        let entries = breakfast + lunch + dinner + snacks
        return MealPlan(id: UUID().uuidString, date: date, breakfast: breakfast, lunch: lunch, dinner: dinner, snacks: snacks,
                        totalCalories: entries.reduce(0) { $0 + $1.calories },
                        totalProteinG: entries.reduce(0) { $0 + $1.proteinG },
                        totalCarbsG: entries.reduce(0) { $0 + $1.carbsG },
                        totalFatG: entries.reduce(0) { $0 + $1.fatG }, agentNotes: notes)
    }
}
