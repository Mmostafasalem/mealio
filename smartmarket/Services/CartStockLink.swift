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
    static func added(_ item: CatalogItem, stock: StockStore = .shared) {
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

    /// One unit of the item with `catalogId` came out of the cart.
    static func removed(_ catalogId: String, units: Int = 1, stock: StockStore = .shared) {
        guard let id = links[catalogId], let existing = stock.items.first(where: { $0.id == id }) else {
            links[catalogId] = nil
            return
        }
        let item = CatalogItem.all.first { $0.id == catalogId }
        let pack = item.flatMap { item in food(for: item).map { packAmount(for: item, food: $0) } } ?? existing.amount
        let left = existing.amount - pack * Double(units)
        if left <= 0.0001 {
            try? stock.remove(id: id)
            links[catalogId] = nil
        } else {
            try? stock.update(id: id, amount: left, expiresAt: existing.expiresAt)
        }
    }

    /// The plain, common food for a catalogue name ("Chicken Breast" → raw chicken breast).
    static func food(for item: CatalogItem) -> NutritionFood? {
        VoiceFoodRanker.foods(for: item.name, limit: 1).first
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
