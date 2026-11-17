import Foundation

// MARK: - A week of groceries for the budget
//
// Built on the phone, no AI. The list comes first and the meal plan is made from
// it (once it's in the cart, the plan uses it). It starts from the foods the person
// picked ("Build your fridge" at setup, editable in Profile), adds staples only for
// what a balanced week is still missing (a protein, a carb, two vegetables, a fruit,
// a dairy food), and fits what's left of the weekly budget after the cart.
//
// When everything fits, everything is suggested. When the budget is tight, the
// balanced basics come first and then favourites, at most two from one food group,
// until the money runs out.

struct GroceryPlanLine: Identifiable, Hashable {
    enum Reason: String { case favourite = "One of your foods", staple = "For a balanced week" }
    var id: String { item.id }
    let item: CatalogItem
    let price: Double
    let reason: Reason
}

struct GroceryPlan: Equatable {
    var lines: [GroceryPlanLine]
    /// What the budget leaves after the cart.
    let available: Double
    /// True when not everything fitted and the tight-budget rules were used.
    var tight = false
    var total: Double { lines.reduce(0) { $0 + $1.price } }
}

enum WeeklyGroceryPlanner {
    enum Role: CaseIterable { case protein, carb, vegetable, fruit, dairy }

    /// A balanced week: one protein, one carb, two vegetables, one fruit, one dairy food.
    static let balancedWeek: [Role] = [.protein, .carb, .vegetable, .vegetable, .fruit, .dairy]

    /// Staples per role, in order of preference.
    static let staples: [Role: [String]] = [
        .protein: ["free-range-eggs", "chicken-breast", "red-lentils", "canned-tuna", "chickpeas-canned"],
        .carb: ["oats", "brown-rice", "whole-grain-bread", "spaghetti", "potato"],
        .vegetable: ["broccoli", "spinach", "carrot", "tomato", "frozen-veg-mix", "bell-pepper", "onion"],
        .fruit: ["banana", "apple", "frozen-berries", "orange"],
        .dairy: ["greek-yogurt", "kefir", "cottage-cheese", "oat-milk"],
    ]

    static let minimumToSuggest = 3.0

    static func role(of item: CatalogItem) -> Role? {
        switch item.category {
        case .meat, .seafood, .eggs, .legumes: return .protein
        case .grains, .bread: return .carb
        case .vegetables: return item.id.contains("potato") ? .carb : .vegetable
        case .fruits: return .fruit
        case .dairy: return .dairy
        default: return nil
        }
    }

    static func plan(budget: Double, cart: [CartItem], favourites: Set<String>,
                     preferences: Set<DietaryPreference>, excluded: Set<String> = [],
                     price: (CatalogItem) -> Double) -> GroceryPlan {
        let available = max(0, budget - cart.reduce(0) { $0 + $1.lineTotal })
        guard available >= minimumToSuggest else { return GroceryPlan(lines: [], available: available) }
        let inCart = Set(cart.map(\.catalogId))
        func usable(_ item: CatalogItem) -> Bool {
            !inCart.contains(item.id) && !excluded.contains(item.id) && allowed(item, preferences) && price(item) > 0
        }

        // The person's foods, food first (spices and drinks rarely make a meal).
        let order: [CatalogCategory] = [.meat, .seafood, .eggs, .legumes, .dairy, .vegetables, .fruits, .grains, .bread,
                                        .frozen, .canned, .nuts, .oils, .condiments, .snacks, .beverages, .baking, .spices]
        let favs = CatalogItem.all.filter { favourites.contains($0.id) && usable($0) }
            .sorted { (order.firstIndex(of: $0.category) ?? 99) < (order.firstIndex(of: $1.category) ?? 99) }

        // What the balanced week still lacks once the person's foods are counted (the cart counts too).
        var have = cart.compactMap { line in CatalogItem.all.first { $0.id == line.catalogId }.flatMap { role(of: $0) } }
        have += favs.compactMap { role(of: $0) }
        var needed: [Role] = []
        var remaining = have
        for r in balancedWeek {
            if let i = remaining.firstIndex(of: r) { remaining.remove(at: i) } else { needed.append(r) }
        }
        var chosenStaples: [CatalogItem] = []
        for r in needed {
            if let item = (staples[r] ?? []).compactMap({ id in CatalogItem.all.first { $0.id == id } })
                .first(where: { usable($0) && !chosenStaples.contains($0) && !favs.contains($0) }) {
                chosenStaples.append(item)
            }
        }

        let everything = favs.map { GroceryPlanLine(item: $0, price: price($0), reason: .favourite) }
            + chosenStaples.map { GroceryPlanLine(item: $0, price: price($0), reason: .staple) }
        if everything.reduce(0, { $0 + $1.price }) <= available + 0.001 {
            return GroceryPlan(lines: everything, available: available)
        }

        // Tight budget: the balanced basics first (the person's own food for a role
        // where there is one, else the cheapest staple), then favourites, at most
        // two from one food group, while the money lasts.
        var lines: [GroceryPlanLine] = []
        var spent = 0.0
        var perGroup: [CatalogCategory: Int] = [:]
        func take(_ line: GroceryPlanLine) {
            guard !lines.contains(where: { $0.id == line.id }), spent + line.price <= available + 0.001,
                  perGroup[line.item.category, default: 0] < 2 else { return }
            lines.append(line)
            spent += line.price
            perGroup[line.item.category, default: 0] += 1
        }
        for r in balancedWeek {
            let taken = Set(lines.map(\.id))
            if let own = favs.filter({ role(of: $0) == r && !taken.contains($0.id) }).min(by: { price($0) < price($1) }) {
                take(GroceryPlanLine(item: own, price: price(own), reason: .favourite))
                continue
            }
            let staple = (staples[r] ?? []).compactMap { id in CatalogItem.all.first { $0.id == id } }
                .filter { usable($0) && !taken.contains($0.id) }
                .min { price($0) < price($1) }
            if let staple { take(GroceryPlanLine(item: staple, price: price(staple), reason: .staple)) }
        }
        for item in favs { take(GroceryPlanLine(item: item, price: price(item), reason: .favourite)) }
        return GroceryPlan(lines: lines, available: available, tight: true)
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
