import Foundation

// MARK: - A week of groceries for the budget
//
// Built on the phone, no AI: what this week's meal plan needs first, then the
// person's favourite foods, then the staples a balanced week is missing (a
// protein, a carb, vegetables, fruit, dairy), priced with the catalogue's
// estimates and fitted to what's left of the weekly budget. Skips what's
// already in the cart and anything the person's diet rules out.

struct GroceryPlanLine: Identifiable, Hashable {
    enum Reason: String { case plan = "In your meal plan", favourite = "A favourite", staple = "For a balanced week" }
    var id: String { item.id }
    let item: CatalogItem
    let price: Double
    let reason: Reason
}

struct GroceryPlan: Equatable {
    var lines: [GroceryPlanLine]
    /// What the budget leaves after the cart.
    let available: Double
    var total: Double { lines.reduce(0) { $0 + $1.price } }
}

enum WeeklyGroceryPlanner {
    /// Staples per role, in order of preference; one of each fills a gap.
    static let staples: [(role: String, ids: [String])] = [
        ("protein", ["free-range-eggs", "chicken-breast", "red-lentils", "canned-tuna", "chickpeas-canned"]),
        ("carb", ["oats", "brown-rice", "whole-grain-bread", "spaghetti", "potato"]),
        ("vegetables", ["broccoli", "spinach", "carrot", "tomato", "frozen-veg-mix"]),
        ("vegetables", ["bell-pepper", "onion", "cucumber", "zucchini"]),
        ("fruit", ["banana", "apple", "frozen-berries", "orange"]),
        ("dairy", ["greek-yogurt", "kefir", "cottage-cheese", "oat-milk"]),
        ("protein", ["salmon-fillet", "turkey-breast", "black-beans", "cottage-cheese"]),
    ]

    static let minimumToSuggest = 3.0

    static func plan(budget: Double, cart: [CartItem], favourites: Set<String>, mealPlan: WeeklyMealPlan?,
                     preferences: Set<DietaryPreference>, excluded: Set<String> = [],
                     price: (CatalogItem) -> Double) -> GroceryPlan {
        let available = max(0, budget - cart.reduce(0) { $0 + $1.lineTotal })
        // A few euros of change isn't worth a shopping suggestion.
        guard available >= minimumToSuggest else { return GroceryPlan(lines: [], available: available) }
        let inCart = Set(cart.map(\.catalogId))
        var taken = Set<String>()
        var lines: [GroceryPlanLine] = []
        var spent = 0.0

        func consider(_ item: CatalogItem, _ reason: GroceryPlanLine.Reason) -> Bool {
            guard !taken.contains(item.id), !inCart.contains(item.id), !excluded.contains(item.id),
                  allowed(item, preferences) else { return false }
            let cost = price(item)
            guard cost > 0, spent + cost <= available + 0.001 else { return false }
            taken.insert(item.id)
            spent += cost
            lines.append(GroceryPlanLine(item: item, price: cost, reason: reason))
            return true
        }

        // 1. What the meal plan's meals are made of.
        for item in ingredients(of: mealPlan) { _ = consider(item, .plan) }
        // 2. Favourites, food first (spices and drinks rarely matter for a week's meals).
        let foodFirst: [CatalogCategory] = [.meat, .seafood, .eggs, .legumes, .dairy, .vegetables, .fruits, .grains, .bread, .frozen, .canned, .nuts]
        let favs = CatalogItem.all.filter { favourites.contains($0.id) }
            .sorted { (foodFirst.firstIndex(of: $0.category) ?? 99) < (foodFirst.firstIndex(of: $1.category) ?? 99) }
        // At most two favourites from one food group, so five kinds of chicken don't fill the week.
        var perGroup: [CatalogCategory: Int] = [:]
        for item in favs where perGroup[item.category, default: 0] < 2 {
            if consider(item, .favourite) { perGroup[item.category, default: 0] += 1 }
        }
        // 3. Staples for whatever role the list doesn't cover yet.
        for staple in staples where !covers(lines, role: staple.role) || staple.role == "vegetables" || staple.role == "protein" {
            for id in staple.ids {
                guard let item = CatalogItem.all.first(where: { $0.id == id }) else { continue }
                if consider(item, .staple) { break }
            }
        }
        return GroceryPlan(lines: lines, available: available)
    }

    /// Catalogue items whose name appears in the plan's ingredients ("Chicken Breast" in "chicken breast, grilled").
    static func ingredients(of plan: WeeklyMealPlan?) -> [CatalogItem] {
        guard let plan else { return [] }
        let text = plan.allDays.map(\.plan).flatMap { day in
            [day.pusryciai, day.pietus, day.vakariene, day.uzkandziai].compactMap { $0 }.flatMap { meal in
                meal.ingredientai + (meal.nutritionIngredients?.map(\.food.name) ?? [])
            }
        }.joined(separator: " | ").lowercased()
        guard !text.isEmpty else { return [] }
        let food: Set<CatalogCategory> = [.meat, .seafood, .eggs, .legumes, .dairy, .vegetables, .fruits, .grains, .bread, .frozen, .canned]
        return CatalogItem.all.filter { food.contains($0.category) && text.contains(singular($0.name.lowercased())) }
    }

    private static func singular(_ name: String) -> String {
        name.hasSuffix("es") && name.count > 4 ? String(name.dropLast(2)) : name.hasSuffix("s") ? String(name.dropLast()) : name
    }

    private static func covers(_ lines: [GroceryPlanLine], role: String) -> Bool {
        lines.contains { line in
            switch role {
            case "protein": return [.meat, .seafood, .eggs, .legumes].contains(line.item.category)
            case "carb": return [.grains, .bread].contains(line.item.category) || line.item.id.contains("potato")
            case "vegetables": return line.item.category == .vegetables
            case "fruit": return line.item.category == .fruits
            case "dairy": return line.item.category == .dairy
            default: return false
            }
        }
    }

    /// Diet rules on catalogue categories and names (allergies are strict, preferences are close enough).
    static func allowed(_ item: CatalogItem, _ prefs: Set<DietaryPreference>) -> Bool {
        let name = item.name.lowercased(), id = item.id
        let pork = ["pork", "bacon", "ham", "salami", "lard", "hot-dogs", "sausages"].contains { id.contains($0) || name.contains($0) }
        if prefs.contains(.vegan) && [.meat, .seafood, .eggs, .dairy].contains(item.category) && !id.contains("oat-milk") && !id.contains("almond-milk") { return false }
        if prefs.contains(.vegetarian) && [.meat, .seafood].contains(item.category) { return false }
        if (prefs.contains(.halal) || prefs.contains(.noPork)) && pork { return false }
        if prefs.contains(.nutAllergy) && (item.category == .nuts || name.contains("nut") || name.contains("almond") || name.contains("pesto")) { return false }
        if prefs.contains(.shellfishAllergy) && ["shrimp", "prawns", "mussels", "crab"].contains(where: id.contains) { return false }
        if prefs.contains(.glutenFree) && (item.category == .bread || ["spaghetti", "penne", "fusilli", "couscous", "bulgur", "barley", "flour", "noodles", "orzo", "lasagna", "rigatoni", "tagliatelle"].contains(where: id.contains)) { return false }
        if prefs.contains(.lactoseFree) && item.category == .dairy && !["oat-milk", "almond-milk"].contains(id) { return false }
        if prefs.contains(.keto) && [.grains, .bread, .fruits].contains(item.category) && !["avocado", "strawberries", "raspberries", "blueberries"].contains(id) { return false }
        return true
    }
}
