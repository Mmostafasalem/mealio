import Foundation

// MARK: - A week of groceries for the budget
//
// Built on the phone, no AI. The list comes first and the meal plan is made from
// it (once it's in the cart, the plan uses it). It starts from the foods the person
// picked ("Build your fridge" at setup, editable in Profile), adds staples only for
// what a balanced week is still missing (a protein, a carb, two vegetables, a fruit,
// a dairy food), and fits what's left of the weekly budget after the cart.
//
// When everything fits, everything is suggested, and money still left buys more
// for the week: staples round the food groups (protein, vegetables, fruit, a carb,
// dairy), each one only once, while they fit. When the budget is tight, the
// balanced basics come first and then favourites, at most two from one food group,
// until the money runs out.

struct GroceryPlanLine: Identifiable, Hashable {
    enum Reason: String {
        case favourite = "One of your foods", staple = "For a balanced week", more = "More for the week"
    }
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
        // The plate's carb (oats and buckwheat stay at breakfast, so they don't count here).
        .carb: ["brown-rice", "potato", "spaghetti", "whole-grain-bread", "basmati-rice"],
        .vegetable: ["broccoli", "spinach", "carrot", "tomato", "frozen-veg-mix", "bell-pepper", "onion"],
        .fruit: ["banana", "apple", "frozen-berries", "orange"],
        .dairy: ["greek-yogurt", "kefir", "cottage-cheese", "oat-milk"],
    ]

    static let minimumToSuggest = 3.0

    /// The same roles the meal plan gives foods (`FallbackData.planRole`), so what is
    /// bought here is what the plan uses: potatoes are the plate's carb, frozen
    /// vegetables are vegetables, butter and cheese are no one's dairy.
    static func role(of item: CatalogItem) -> Role? {
        switch FallbackData.planRole(name: item.name, category: item.category.rawValue) {
        case "eggs", "seafood", "meat", "legumes": return .protein
        case "grains":
            let breakfastOnly = ["oat", "buckwheat", "muesli", "granola", "porridge"].contains { item.name.lowercased().contains($0) }
            return breakfastOnly ? nil : .carb
        case "vegetables": return .vegetable
        case "fruits": return .fruit
        case "dairy": return .dairy
        default: return nil
        }
    }

    static func plan(budget: Double, cart: [CartItem], favourites: Set<String>,
                     preferences: Set<DietaryPreference>, excluded: Set<String> = [],
                     stock: [String] = [],
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
        // Food already in My Stock (not put there by the cart) covers its part of the week too.
        have += stock.compactMap { name -> Role? in
            switch FallbackData.planRole(name: name, category: "") {
            case "eggs", "seafood", "meat", "legumes": return .protein
            case "grains": return ["oat", "buckwheat", "muesli", "granola", "porridge"].contains { name.lowercased().contains($0) } ? nil : .carb
            case "vegetables": return .vegetable
            case "fruits": return .fruit
            case "dairy": return .dairy
            default: return nil
            }
        }
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
        let spentOnBasics = everything.reduce(0, { $0 + $1.price })
        if spentOnBasics <= available + 0.001 {
            return GroceryPlan(lines: everything + more(after: everything, left: available - spentOnBasics, usable: usable, price: price),
                               available: available)
        }

        // Tight budget: the balanced basics first (the person's own food for a role
        // where there is one, else the cheapest staple), then favourites, at most
        // two from one food group, while the money lasts.
        var lines: [GroceryPlanLine] = []
        var spent = 0.0
        var perGroup: [CatalogCategory: Int] = [:]
        @discardableResult
        func take(_ line: GroceryPlanLine) -> Bool {
            guard !lines.contains(where: { $0.id == line.id }), spent + line.price <= available + 0.001,
                  perGroup[line.item.category, default: 0] < 2 else { return false }
            lines.append(line)
            spent += line.price
            perGroup[line.item.category, default: 0] += 1
            return true
        }
        for r in balancedWeek {
            let taken = Set(lines.map(\.id))
            // The person's own food for the role if it fits the money, else the cheapest staple.
            if let own = favs.filter({ role(of: $0) == r && !taken.contains($0.id) }).min(by: { price($0) < price($1) }),
               take(GroceryPlanLine(item: own, price: price(own), reason: .favourite)) {
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

    /// The order money left over is spent in: the plate first, then the rest of the day.
    static let topUpOrder: [Role] = [.protein, .vegetable, .fruit, .carb, .vegetable, .dairy, .protein, .fruit, .vegetable]
    static let maxMore = 9

    /// Staples not yet in the cart or the list, round the food groups, while the money lasts.
    static func more(after lines: [GroceryPlanLine], left: Double, usable: (CatalogItem) -> Bool,
                     price: (CatalogItem) -> Double) -> [GroceryPlanLine] {
        var taken = Set(lines.map(\.id)), left = left, out: [GroceryPlanLine] = []
        var stuck = Set<Role>()
        while out.count < maxMore, left >= minimumToSuggest, stuck.count < Role.allCases.count {
            var added = false
            for r in topUpOrder where out.count < maxMore && !stuck.contains(r) {
                let next = (staples[r] ?? []).compactMap { id in CatalogItem.all.first { $0.id == id } }
                    .first { usable($0) && !taken.contains($0.id) && price($0) <= left + 0.001 }
                guard let next else { stuck.insert(r); continue }
                out.append(GroceryPlanLine(item: next, price: price(next), reason: .more))
                taken.insert(next.id)
                left -= price(next)
                added = true
            }
            if !added { break }
        }
        return out
    }

    /// The same diet rule the meal plan uses (`DietaryPreference.conflicts`), so nothing
    /// suggested here is then refused by the plan. Allergies are strict.
    static func allowed(_ item: CatalogItem, _ prefs: Set<DietaryPreference>) -> Bool {
        prefs.allows(name: item.name, category: item.category.rawValue)
    }
}
