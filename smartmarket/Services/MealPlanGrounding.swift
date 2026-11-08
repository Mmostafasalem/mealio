import Foundation

struct PlannedPortion: Codable, Equatable {
    let foodID: String
    let amount: Double
}

struct PlanningFood: Encodable {
    let food: NutritionFood
    let availableAmount: Double

    private struct Reference: Encodable {
        let id: String
        let name: String
        let basis: String
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }
    private enum CodingKeys: String, CodingKey { case food, availableAmount }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Reference(id: food.id, name: food.name, basis: food.basis.rawValue,
                                       kcal: food.kcal, protein: food.protein, carbs: food.carbs, fat: food.fat), forKey: .food)
        try container.encode(availableAmount, forKey: .availableAmount)
    }
}

/// The model chooses ingredients and amounts; catalog snapshots supply nutrition.
/// An unresolved ingredient never receives made-up macros from the daily target.
enum MealPlanGrounding {
    static func resolve(_ item: MealItem, foods: [String: NutritionFood]) -> MealItem {
        var item = item
        // Never trust nutrition snapshots supplied by a remote response.
        item.nutritionIngredients = nil
        guard let portions = item.portions, !portions.isEmpty, portions.count <= 50 else { return item }
        var ingredients: [NutritionIngredient] = []
        for portion in portions {
            guard let food = foods[portion.foodID], food.isValid,
                  portion.amount.isFinite, portion.amount > 0, portion.amount <= food.maximumAmount else { return item }
            ingredients.append(NutritionIngredient(food: food, amount: portion.amount))
        }
        var resolved = item
        resolved.nutritionIngredients = ingredients
        return resolved
    }

    static func resolve(_ weekly: WeeklyMealPlan, foods: [NutritionFood]) -> WeeklyMealPlan {
        let index = Dictionary(foods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func day(_ value: DayPlan?) -> DayPlan? {
            guard let value else { return nil }
            func meal(_ item: MealItem?) -> MealItem? { item.map { resolve($0, foods: index) } }
            return DayPlan(pusryciai: meal(value.pusryciai), pietus: meal(value.pietus),
                           vakariene: meal(value.vakariene), uzkandziai: meal(value.uzkandziai), visoKcal: value.visoKcal)
        }
        return WeeklyMealPlan(generationSource: weekly.generationSource, agentMessage: weekly.agentMessage,
                              pirmadienis: day(weekly.pirmadienis), antradienis: day(weekly.antradienis),
                              treciadienis: day(weekly.treciadienis), ketvirtadienis: day(weekly.ketvirtadienis),
                              pentadienis: day(weekly.pentadienis), sestadienis: day(weekly.sestadienis), sekmadienis: day(weekly.sekmadienis))
    }
}
