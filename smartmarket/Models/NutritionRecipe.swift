import Foundation

struct NutritionIngredient: Codable, Hashable, Identifiable {
    var id = UUID()
    let food: NutritionFood
    var amount: Double
}
struct NutritionRecipe: Codable, Hashable {
    let ingredients: [NutritionIngredient]
    let cookedYieldG: Double
}

enum NutritionEntryError: LocalizedError {
    case invalidRecipe, invalidMenu, tooMany
    var errorDescription: String? {
        switch self {
        case .invalidRecipe: return "Enter a name, valid ingredient amounts and the weighed final dish yield in grams. Use between 1 and 50 ingredients."
        case .invalidMenu: return "Enter the dish, restaurant, calories and all three macros per menu serving. Use nonnegative numbers and an optional public HTTPS menu link."
        case .tooMany: return "You can save up to 200 custom dishes. Remove an unused dish before adding another."
        }
    }
}

extension NutritionFood {
    static func makeRecipe(name: String, ingredients: [NutritionIngredient], cookedYieldG: Double) throws -> NutritionFood {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 160,
              !ingredients.isEmpty, ingredients.count <= 50,
              cookedYieldG.isFinite, cookedYieldG >= 1, cookedYieldG <= 100000,
              ingredients.allSatisfy({ $0.food.isValid && $0.food.source != .recipe && $0.food.source != .menu &&
                  $0.amount.isFinite && $0.amount >= $0.food.minimumAmount && $0.amount <= 100000 })
        else { throw NutritionEntryError.invalidRecipe }
        let totals = ingredients.map { $0.food.portion($0.amount) }
        let factor = 100 / cookedYieldG
        let identifier = UUID().uuidString
        var food = NutritionFood(id: "recipe:" + identifier, name: name.trimmingCharacters(in: .whitespacesAndNewlines), brand: nil,
                                 basis: .grams, kcal: totals.reduce(0) { $0 + $1.kcal } * factor,
                                 protein: totals.reduce(0) { $0 + $1.protein } * factor,
                                 carbs: totals.reduce(0) { $0 + $1.carbs } * factor,
                                 fat: totals.reduce(0) { $0 + $1.fat } * factor,
                                 source: .recipe, sourceID: identifier, sourceDate: String(ISO8601DateFormatter().string(from: Date()).prefix(10)))
        food.recipeDetails = NutritionRecipe(ingredients: ingredients, cookedYieldG: cookedYieldG)
        guard food.isValid else { throw NutritionEntryError.invalidRecipe }
        return food
    }
    static func makeMenuFood(name: String, restaurant: String, kcal: Double, protein: Double, carbs: Double, fat: Double, sourceURL: String) throws -> NutritionFood {
        let link = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.isEmpty {
            guard let url = URLComponents(string: link), url.scheme == "https", url.host?.isEmpty == false,
                  url.user == nil, url.password == nil, link.count <= 1000 else { throw NutritionEntryError.invalidMenu }
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = restaurant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !place.isEmpty, title.count <= 160, place.count <= 160 else { throw NutritionEntryError.invalidMenu }
        let identifier = UUID().uuidString
        var food = NutritionFood(id: "menu:" + identifier, name: title, brand: place, basis: .serving,
                                 kcal: kcal, protein: protein, carbs: carbs, fat: fat, source: .menu,
                                 sourceID: identifier, sourceDate: String(ISO8601DateFormatter().string(from: Date()).prefix(10)))
        food.menuURL = link.isEmpty ? nil : link
        guard food.isValid else { throw NutritionEntryError.invalidMenu }
        return food
    }
}
