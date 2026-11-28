import Foundation

// MARK: - A week of groceries for the budget
//
// Built on the phone, no AI. The list comes first and the meal plan is made from
// it (once it's in the cart, the plan uses it). It starts from the foods the person
// picked ("Build your fridge" at setup, editable in Profile), adds staples only for
// what a balanced week is still missing (a protein, a carb, two vegetables, a fruit,
// a dairy food), and fits what's left of the weekly budget after the cart.
//
// When everything fits, everything is suggested, and the money still left is used
// (`fill`) until less than `fillUntil` (€5) remains: first one more pack of each of
// the person's own foods, then round the food groups (protein, vegetables, fruit, a
// carb, dairy) with staples first and then other catalogue foods with a part in the
// plan, and last a second pack of what is already on the list. Sweets, sauces,
// drinks and seasonings never fill the list (they have no role). When the budget is
// tight, the balanced basics come first and then favourites, at most two from one
// food group, and what's left is filled the same way (without the extra packs).

struct GroceryPlanLine: Identifiable, Hashable {
    enum Reason: String {
        case favourite = "One of your foods", another = "More of one of your foods",
             staple = "For a balanced week", more = "More for the week"
    }
    var id: String { item.id }
    let item: CatalogItem
    /// One pack's price.
    let unitPrice: Double
    /// Packs to buy (a second pack of a food the person eats a lot).
    var quantity: Int
    let reason: Reason
    /// The line's total.
    var price: Double { unitPrice * Double(quantity) }

    init(item: CatalogItem, price: Double, reason: Reason, quantity: Int = 1) {
        self.item = item
        unitPrice = price
        self.quantity = quantity
        self.reason = reason
    }
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

    /// Money left below this isn't planned: the list stops here, and a cart that leaves
    /// less than this gets no suggestions at all.
    static let fillUntil = 5.0
    /// At most this many packs of one food in a week (cart and list together).
    static let maxPacks = 2

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
                     stock: [String] = [], starred: Set<String> = [],
                     price: (CatalogItem) -> Double) -> GroceryPlan {
        let available = max(0, budget - cart.reduce(0) { $0 + $1.lineTotal })
        guard available >= fillUntil else { return GroceryPlan(lines: [], available: available) }
        let cartPacks = cart.reduce(into: [String: Int]()) { $0[$1.catalogId, default: 0] += max(1, $1.quantity) }
        let inCart = Set(cartPacks.keys)
        /// Fits the diet, has a price and wasn't removed by the person.
        func fits(_ item: CatalogItem) -> Bool {
            !excluded.contains(item.id) && allowed(item, preferences) && price(item) > 0
        }
        /// A food not in the cart yet.
        func usable(_ item: CatalogItem) -> Bool { !inCart.contains(item.id) && fits(item) }

        // The person's foods, food first (spices and drinks rarely make a meal).
        let order: [CatalogCategory] = [.meat, .seafood, .eggs, .legumes, .dairy, .vegetables, .fruits, .grains, .bread,
                                        .frozen, .canned, .nuts, .oils, .condiments, .snacks, .beverages, .baking, .spices]
        // Starred foods (the ones bought most) first, so a tight budget keeps them.
        let favs = CatalogItem.all.filter { favourites.contains($0.id) && usable($0) }
            .sorted { (order.firstIndex(of: $0.category) ?? 99) < (order.firstIndex(of: $1.category) ?? 99) }
            .sorted { starred.contains($0.id) && !starred.contains($1.id) }

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
        // The person's own foods, for more packs: their picks (in the cart or not) that
        // have a part in the plan, plate foods first.
        let own = CatalogItem.all.filter { favourites.contains($0.id) && role(of: $0) != nil && fits($0) }
            .sorted { (order.firstIndex(of: $0.category) ?? 99) < (order.firstIndex(of: $1.category) ?? 99) }
        if spentOnBasics <= available + 0.001 {
            var lines = everything
            fill(&lines, left: available - spentOnBasics, own: own, cartPacks: cartPacks,
                 usable: usable, repeatable: fits, price: price)
            return GroceryPlan(lines: lines, available: available)
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
            // A starred food for the role wins over a cheaper unstarred one.
            let forRole = favs.filter { role(of: $0) == r && !taken.contains($0.id) }
            let starredForRole = forRole.filter { starred.contains($0.id) }
            if let own = (starredForRole.isEmpty ? forRole : starredForRole).min(by: { price($0) < price($1) }),
               take(GroceryPlanLine(item: own, price: price(own), reason: .favourite)) {
                continue
            }
            let staple = (staples[r] ?? []).compactMap { id in CatalogItem.all.first { $0.id == id } }
                .filter { usable($0) && !taken.contains($0.id) }
                .min { price($0) < price($1) }
            if let staple { take(GroceryPlanLine(item: staple, price: price(staple), reason: .staple)) }
        }
        for item in favs { take(GroceryPlanLine(item: item, price: price(item), reason: .favourite)) }
        // Whatever the picked foods left unspent still buys food for the week (new foods
        // keep the two-of-a-kind limit; no extra packs of favourites on a tight budget).
        fill(&lines, left: available - spent, own: [], cartPacks: cartPacks,
             usable: { usable($0) && perGroup[$0.category, default: 0] < 2 }, repeatable: fits, price: price)
        return GroceryPlan(lines: lines, available: available, tight: true)
    }

    /// The order money left over is spent in: the plate first, then the rest of the day.
    static let topUpOrder: [Role] = [.protein, .vegetable, .fruit, .carb, .vegetable, .dairy, .protein, .fruit, .vegetable]
    /// A stop for the loop only; the money runs out long before.
    static let maxMore = 60

    /// Spends what is left until less than `fillUntil` remains, in this order:
    /// 1. one more pack of each of the person's own foods (`own`), so they get more of
    ///    what they eat;
    /// 2. new foods round the food groups: the staples first, then any other catalogue
    ///    food with a part in the plan (never sweets, sauces, drinks or seasonings);
    /// 3. a second pack of a food already in the cart or on the list (staples first),
    ///    when the new foods have run out or cost too much.
    /// No food goes above `maxPacks` packs for the week, and the total never passes `left`.
    static func fill(_ lines: inout [GroceryPlanLine], left: Double, own: [CatalogItem], cartPacks: [String: Int],
                     usable: (CatalogItem) -> Bool, repeatable: (CatalogItem) -> Bool,
                     price: (CatalogItem) -> Double) {
        var left = left
        var added = 0
        func packs(_ id: String) -> Int { cartPacks[id, default: 0] + (lines.first { $0.id == id }?.quantity ?? 0) }
        @discardableResult
        func addPack(_ item: CatalogItem, reason: GroceryPlanLine.Reason) -> Bool {
            let p = price(item)
            guard added < maxMore, left >= fillUntil, p > 0, p <= left + 0.001, packs(item.id) < maxPacks else { return false }
            if let i = lines.firstIndex(where: { $0.id == item.id }) { lines[i].quantity += 1 }
            else { lines.append(GroceryPlanLine(item: item, price: p, reason: reason)) }
            left -= p
            added += 1
            return true
        }

        // 1. More of the person's own foods.
        for item in own where repeatable(item) { addPack(item, reason: .another) }

        // 2. New foods, round the food groups.
        var pool: [Role: [CatalogItem]] = [:]
        for r in Role.allCases {
            let first = (staples[r] ?? []).compactMap { id in CatalogItem.all.first { $0.id == id } }
            let firstIDs = Set(first.map(\.id))
            let rest = CatalogItem.all.filter { !firstIDs.contains($0.id) && role(of: $0) == r }
            // Only foods the plan gives this part (onion is on the staples list but is a seasoning there).
            pool[r] = (first + rest).filter { role(of: $0) == r && usable($0) && packs($0.id) == 0 }
        }
        var stuck = Set<Role>()
        while left >= fillUntil, added < maxMore, stuck.count < Role.allCases.count {
            var any = false
            for r in topUpOrder where left >= fillUntil && !stuck.contains(r) {
                guard let next = pool[r]?.first(where: { packs($0.id) == 0 && price($0) <= left + 0.001 }),
                      addPack(next, reason: .more) else {
                    stuck.insert(r); continue
                }
                any = true
            }
            if !any { break }
        }

        // 3. Second packs of what the week already has, staples and plate foods first.
        guard left >= fillUntil else { return }
        let stapleIDs = Set(staples.values.flatMap { $0 })
        let already = (lines.map(\.item) + CatalogItem.all.filter { cartPacks[$0.id] != nil && !lines.map(\.id).contains($0.id) })
            .filter { role(of: $0) != nil && repeatable($0) }
            .sorted { (stapleIDs.contains($0.id) ? 0 : 1, price($0)) < (stapleIDs.contains($1.id) ? 0 : 1, price($1)) }
        for item in already where left >= fillUntil {
            addPack(item, reason: lines.contains { $0.id == item.id } ? .more : .another)
        }
    }

    /// The same diet rule the meal plan uses (`DietaryPreference.conflicts`), so nothing
    /// suggested here is then refused by the plan. Allergies are strict.
    static func allowed(_ item: CatalogItem, _ prefs: Set<DietaryPreference>) -> Bool {
        prefs.allows(name: item.name, category: item.category.rawValue)
    }
}
