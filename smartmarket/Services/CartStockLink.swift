import Foundation

// MARK: - Cart → My Stock
//
// Putting a food in the cart also puts it in My Stock, so nobody has to add it
// twice. Each cart unit is one typical pack of that food. Taking a unit out of
// the cart takes that pack back out of the stock it created (never more than the
// cart added, and never what the person added themselves).

@MainActor
enum CartStockLink {
    private static let key = "cartStockLinks_v1"

    /// Cart catalogue id → the stock item it filled.
    private static var links: [String: UUID] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
            return raw.compactMapValues(UUID.init(uuidString:))
        }
        set { UserDefaults.standard.set(newValue.mapValues(\.uuidString), forKey: key) }
    }

    /// One more unit of `item` went into the cart.
    static func added(_ item: CatalogItem, stock: StockStore? = nil) {
        let stock = stock ?? .shared
        guard let food = food(for: item) else { return }
        let pack = packAmount(for: item, food: food)
        if let id = links[item.id], let existing = stock.items.first(where: { $0.id == id }) {
            try? stock.update(id: id, amount: existing.amount + pack, expiresAt: existing.expiresAt)
            return
        }
        let before = Set(stock.items.map(\.id))
        guard (try? stock.add(food: food, amount: pack)) != nil,
              let created = stock.items.first(where: { !before.contains($0.id) }) else { return }
        links[item.id] = created.id
    }

    /// One unit of the item with `catalogId` came out of the cart. Returns how much left My
    /// Stock, so an undo can put back exactly that.
    @discardableResult
    static func removed(_ catalogId: String, units: Int = 1, stock: StockStore? = nil) -> Double {
        let stock = stock ?? .shared
        guard let id = links[catalogId], let existing = stock.items.first(where: { $0.id == id }) else {
            links[catalogId] = nil
            return 0
        }
        let item = CatalogItem.all.first { $0.id == catalogId }
        let pack = item.flatMap { item in food(for: item).map { packAmount(for: item, food: $0) } } ?? existing.amount
        let left = existing.amount - pack * Double(units)
        if left <= 0.0001 {
            try? stock.remove(id: id)
            links[catalogId] = nil
            return existing.amount
        } else {
            try? stock.update(id: id, amount: left, expiresAt: existing.expiresAt)
            return existing.amount - left
        }
    }

    /// Undo: `amount` goes back into the stock the cart fills for `catalogId`.
    static func restore(_ catalogId: String, amount: Double, stock: StockStore? = nil) {
        let stock = stock ?? .shared
        guard amount > 0.0001 else { return }
        if let id = links[catalogId], let existing = stock.items.first(where: { $0.id == id }) {
            try? stock.update(id: id, amount: existing.amount + amount, expiresAt: existing.expiresAt)
            return
        }
        guard let item = CatalogItem.all.first(where: { $0.id == catalogId }), let food = food(for: item) else { return }
        let before = Set(stock.items.map(\.id))
        guard (try? stock.add(food: food, amount: amount)) != nil,
              let created = stock.items.first(where: { !before.contains($0.id) }) else { return }
        links[catalogId] = created.id
    }

    /// The cart let go of the item, but its food stays in My Stock as the person's own
    /// (it was bought): the link goes, so the stock is no longer the cart's to take back.
    static func forget(_ catalogId: String) { links[catalogId] = nil }

    /// The whole cart let go of its foods (cleared or a new week): My Stock keeps them all.
    static func forgetAll() { UserDefaults.standard.removeObject(forKey: key) }

    /// The plain, common food for a catalogue name ("Chicken Breast" → raw chicken breast).
    /// Shop items the search can't find well on its own: the exact USDA record.
    static let pinned: [String: String] = [
        "milk-25": "Milk, reduced fat (2%)", "skimmed-milk": "Milk, fat free (skim)",
        "eggs-6": "Egg, whole, raw, fresh", "eggs-10": "Egg, whole, raw, fresh", "eggs-12": "Egg, whole, raw, fresh",
        "free-range-eggs": "Egg, whole, raw, fresh",
        "salmon-fillet": "Fish, salmon, Atlantic, farmed, raw", "trout-fillet": "Fish, trout, rainbow, farmed, raw",
        "cod-fillet": "Fish, cod, Atlantic, raw", "hake-fillet": "Fish, cod, Atlantic, raw", "frozen-fish-fillets": "Fish, cod, Atlantic, raw",
        "tuna-steak": "Fish, tuna, fresh, yellowfin, raw", "pollock": "Fish, pollock, raw",
        "spaghetti": "Pasta, dry, enriched", "penne": "Pasta, dry, enriched", "fusilli": "Pasta, dry, enriched",
        "rigatoni": "Pasta, dry, enriched", "tagliatelle": "Pasta, dry, enriched", "orzo": "Pasta, dry, enriched",
        "lasagna-sheets": "Pasta, dry, enriched",
        "basmati-rice": "Rice, white, long-grain, regular, raw, enriched", "arborio-rice": "Rice, white, long-grain, regular, raw, enriched",
        "green-lentils": "Lentils, raw", "black-lentils": "Lentils, raw",
        "whole-chicken": "Chicken, broilers or fryers, meat and skin, raw",
        "frozen-berries": "Strawberries, frozen", "cherry-tomatoes": "Tomatoes, red, ripe, raw, year round average",
        "sour-cream-15": "Sour cream, regular", "sour-cream-30": "Sour cream, regular",
        "quinoa": "Quinoa, uncooked", "couscous": "Couscous, dry",
    ]

    /// The record for a shop item. Food is bought raw or dry, so that's preferred (raw chicken,
    /// dry rice and oats); a match only counts when the item's own word leads the record's
    /// name ("Spaghetti" is never spaghetti squash, "Milk 2.5%" never a dessert topping).
    static func food(for item: CatalogItem) -> NutritionFood? {
        let catalog = NutritionCatalogService.shared
        if let exact = pinned[item.id] {
            return catalog.searchLocal(exact).first { $0.name == exact }
        }
        let filler: Set<String> = ["canned", "frozen", "fresh", "smoked", "mixed", "pack", "whole", "dried", "plain", "free", "range"]
        let wanted = KitchenMatcher.words(item.name).subtracting(filler).filter { $0.count >= 3 }
        func fits(_ food: NutritionFood) -> Bool {
            let lead = food.name.lowercased().split(separator: ",").prefix(2).joined(separator: " ")
            return !wanted.isDisjoint(with: KitchenMatcher.words(lead))
        }
        if let raw = VoiceFoodRanker.foods(for: item.name + " raw", limit: 3).first(where: { food in
            fits(food) && !KitchenMatcher.words(food.name).isDisjoint(with: ["raw", "dry", "uncooked"])
        }) { return raw }
        return VoiceFoodRanker.foods(for: item.name, limit: 3).first(where: fits)
    }

    /// A typical pack, in the food's own unit: a dozen eggs, a 500 g pack of meat, a litre of milk…
    static func packAmount(for item: CatalogItem, food: NutritionFood) -> Double {
        if food.basis == .serving { return item.category == .eggs ? 10 : 1 }
        switch item.category {
        case .eggs: return 600
        case .meat, .seafood, .frozen: return 500
        case .dairy, .beverages: return food.basis == .millilitres ? 1000 : 400
        case .bread: return 500
        case .vegetables, .fruits: return 1000
        case .grains, .legumes, .baking: return 1000
        case .canned: return 400
        case .oils: return 500
        case .condiments, .nuts, .snacks: return 200
        case .spices: return 50
        }
    }
}
