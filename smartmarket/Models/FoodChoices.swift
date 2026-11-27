import Foundation

// MARK: - Which foods are offered, and the ready-made starting list
//
// "Pick your foods" (onboarding) and Profile › Favourite foods offer only what the
// person's diet allows, with the same rule the meal plan and the weekly groceries use
// (`DietaryPreference.conflicts`). A section the diet rules out completely is not shown
// at all; when a diet leaves only plant milks in Dairy (vegan, lactose-free), the
// section becomes "Plant milk" so no Dairy section is offered.
//
// The starting list is what this person most likely buys: everyday staples for every
// part the plan gives a food (breakfast grain, fruit, dairy or plant milk, proteins,
// the plate's carb, vegetables, nuts), chosen by diet and goal, about 25 to 40 foods.

/// A section of the food picker: a catalogue category, or Dairy shown as "Plant milk".
struct FoodSection: Identifiable, Hashable {
    let category: CatalogCategory
    let items: [CatalogItem]
    /// True when only plant milks are left of Dairy.
    let isPlantMilk: Bool

    var id: String { isPlantMilk ? "plantMilk" : category.rawValue }
    var title: String { isPlantMilk ? "Plant milk" : category.displayName }
    var symbol: String { isPlantMilk ? "leaf.circle.fill" : category.symbol }
}

enum FoodChoices {

    /// True when the diet allows the food. A halal diet still offers meat (the person
    /// buys halal meat); pork, alcohol and gelatin are never offered.
    static func offers(_ item: CatalogItem, diets: Set<DietaryPreference>) -> Bool {
        diets.allows(name: item.name, category: item.category.rawValue, owned: true)
    }

    /// Every food the diet allows, in catalogue order.
    static func offeredItems(diets: Set<DietaryPreference>) -> [CatalogItem] {
        CatalogItem.all.filter { offers($0, diets: diets) }
    }

    /// The sections that still have a food for this diet, in catalogue order.
    static func sections(diets: Set<DietaryPreference>) -> [FoodSection] {
        let offered = offeredItems(diets: diets)
        return CatalogCategory.allCases.compactMap { cat in
            let items = offered.filter { $0.category == cat }
            guard !items.isEmpty else { return nil }
            let plantOnly = cat == .dairy && items.allSatisfy(isPlantMilk)
            return FoodSection(category: cat, items: items, isPlantMilk: plantOnly)
        }
    }

    static func isPlantMilk(_ item: CatalogItem) -> Bool {
        let name = item.name.lowercased()
        return name.hasSuffix(" milk") && ["oat", "almond", "soy", "soya", "rice", "coconut"].contains { name.hasPrefix($0) }
    }

    // MARK: Starting list

    /// The part a food plays in the day, for the starting list.
    enum Role: CaseIterable { case breakfastGrain, fruit, dairy, protein, carb, vegetable, nuts, basics }

    /// Everyday staples per part, most likely first (catalogue ids).
    static let staples: [Role: [String]] = [
        .breakfastGrain: ["oats", "whole-grain-bread", "buckwheat", "rye-bread", "millet", "quinoa"],
        .fruit: ["banana", "apple", "frozen-berries", "orange", "blueberries", "strawberries", "avocado", "raspberries", "pear", "grapes-green"],
        .dairy: ["greek-yogurt", "milk-25", "kefir", "cottage-cheese", "plain-yogurt", "oat-milk", "almond-milk"],
        .protein: ["eggs-10", "chicken-breast", "salmon-fillet", "canned-tuna", "red-lentils", "chickpeas-canned",
                   "turkey-breast", "ground-beef", "cod-fillet", "black-beans", "frozen-edamame", "green-lentils",
                   "white-beans", "soybeans", "mackerel"],
        .carb: ["brown-rice", "potato", "spaghetti", "sweet-potato", "basmati-rice", "whole-grain-bread", "quinoa", "buckwheat"],
        .vegetable: ["broccoli", "spinach", "carrot", "tomato", "bell-pepper", "cucumber", "onion", "frozen-veg-mix",
                     "zucchini", "mushrooms", "lettuce", "cauliflower", "green-beans", "kale"],
        .nuts: ["mixed-nuts", "almonds", "walnuts", "peanut-butter", "pumpkin-seeds", "chia-seeds", "sunflower-seeds"],
        .basics: ["olive-oil", "garlic", "cheddar", "butter"],
    ]

    /// How many foods of each part the list starts with, by goal.
    static func counts(for goal: WeightGoal) -> [Role: Int] {
        switch goal {
        case .lose:     return [.breakfastGrain: 2, .fruit: 4, .dairy: 3, .protein: 7, .carb: 2, .vegetable: 8, .nuts: 1, .basics: 3]
        case .maintain: return [.breakfastGrain: 2, .fruit: 4, .dairy: 3, .protein: 6, .carb: 3, .vegetable: 7, .nuts: 2, .basics: 3]
        case .gain:     return [.breakfastGrain: 2, .fruit: 4, .dairy: 3, .protein: 8, .carb: 4, .vegetable: 6, .nuts: 3, .basics: 3]
        }
    }

    /// Lean proteins lead when losing weight.
    private static func proteinOrder(_ goal: WeightGoal) -> [String] {
        let list = staples[.protein] ?? []
        guard goal == .lose else { return list }
        let lean = ["chicken-breast", "turkey-breast", "cod-fillet", "canned-tuna", "eggs-10", "red-lentils"]
        return lean + list.filter { !lean.contains($0) }
    }

    /// The fewest foods the list holds; topped up with more staples when a strict diet
    /// leaves fewer.
    static let minimumStarter = 25

    /// The ready-made list for this diet and goal, most likely first. Uses the meal
    /// plan's own rule (a halal list holds no unlabelled meat, as the plan wouldn't use it).
    static func starterList(diets: Set<DietaryPreference>, goal: WeightGoal) -> [CatalogItem] {
        let byID = Dictionary(uniqueKeysWithValues: CatalogItem.all.map { ($0.id, $0) })
        func usable(_ item: CatalogItem) -> Bool {
            offers(item, diets: diets) && diets.allows(name: item.name, category: item.category.rawValue)
        }
        var picked: [CatalogItem] = []
        var leftovers: [[CatalogItem]] = []
        let counts = counts(for: goal)
        for role in Role.allCases {
            let ids = role == .protein ? proteinOrder(goal) : (staples[role] ?? [])
            let options = ids.compactMap { byID[$0] }.filter { usable($0) && !picked.contains($0) }
            let n = counts[role] ?? 0
            picked += options.prefix(n)
            leftovers.append(Array(options.dropFirst(n)))
        }
        // A strict diet leaves gaps: more of the other staples, one part at a time.
        var round = 0
        while picked.count < minimumStarter, leftovers.contains(where: { !$0.isEmpty }) {
            let i = round % leftovers.count
            if let next = leftovers[i].first {
                leftovers[i].removeFirst()
                if !picked.contains(next) { picked.append(next) }
            }
            round += 1
        }
        // Still short: any food the diet allows that has a part in the plan.
        if picked.count < minimumStarter {
            for item in CatalogItem.all where picked.count < minimumStarter && usable(item) && !picked.contains(item)
                && FallbackData.planRole(name: item.name, category: item.category.rawValue) != nil {
                picked.append(item)
            }
        }
        return picked
    }
}

// MARK: - Starred foods

/// Foods the person starred as the ones they buy most. The weekly groceries keep
/// them first when the budget is tight.
enum StarredFoods {
    static let storageKey = "starredFoodIDs_v1"

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
    }

    static func save(_ ids: Set<String>) {
        UserDefaults.standard.set(ids.sorted(), forKey: storageKey)
    }
}
