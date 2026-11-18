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
            try? stock.update(id: id, amount: existing.amount + pack, expiresAt: existing.expiryDay())
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
            try? stock.update(id: id, amount: left, expiresAt: existing.expiryDay())
            return existing.amount - left
        }
    }

    /// Undo: `amount` goes back into the stock the cart fills for `catalogId`.
    static func restore(_ catalogId: String, amount: Double, stock: StockStore? = nil) {
        let stock = stock ?? .shared
        guard amount > 0.0001 else { return }
        if let id = links[catalogId], let existing = stock.items.first(where: { $0.id == id }) {
            try? stock.update(id: id, amount: existing.amount + amount, expiresAt: existing.expiryDay())
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
    @discardableResult
    static func forget(_ catalogId: String) -> UUID? {
        let id = links[catalogId]
        links[catalogId] = nil
        return id
    }

    /// Undo of `forget`: the cart line owns its stock item again (if it's still there).
    static func relink(_ catalogId: String, to id: UUID, stock: StockStore? = nil) {
        guard (stock ?? .shared).items.contains(where: { $0.id == id }) else { return }
        links[catalogId] = id
    }

    /// The whole cart let go of its foods (cleared or a new week): My Stock keeps them all.
    static func forgetAll() { UserDefaults.standard.removeObject(forKey: key) }

    /// The plain, common food for a catalogue name ("Chicken Breast" → raw chicken breast).
    /// Shop items the search can't find well on its own: the exact USDA record.
    static let pinned: [String: String] = [
        "milk-35": "Milk, whole", "milk-25": "Milk, reduced fat (2%)", "skimmed-milk": "Milk, fat free (skim)",
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
        "shrimp": "Crustaceans, shrimp, raw", "prawns": "Crustaceans, shrimp, raw", "frozen-shrimp": "Crustaceans, shrimp, raw",
        "beet": "Beets, raw", "baguette": "Bread, French or Vienna", "ciabatta": "Bread, Italian",
        "polenta": "Cornmeal, yellow (Navajo)", "canned-herring": "Fish, herring, Atlantic, pickled",
        "smoked-mackerel": "Fish, mackerel, canned", "crab-sticks": "Imitation crab meat", "dziugas": "Cheese, parmesan, hard",
        "artichoke-hearts": "Artichoke", "roasted-peppers": "Peppers, sweet, red, canned, solids and liquids",
        "water-chestnuts": "Waterchestnuts, chinese, canned, solids and liquids",
        "chicken-broth": "Soup, chicken broth, ready-to-serve", "beef-broth": "Soup, SWANSON, beef broth, lower sodium",
        "pinto-beans": "Beans, pinto, mature seeds, raw (Includes foods for USDA's Food Distribution Program)",
        "chickpeas-dried": "Chickpeas (garbanzo beans, bengal gram), mature seeds, raw",
        "sesame-seeds": "Seeds, sesame seeds, whole, dried", "potato": "Potatoes, flesh and skin, raw",
        "sausages": "Sausage, Italian, pork, mild, raw", "bread-rolls": "Rolls, dinner, wheat",
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
        if let raw = VoiceFoodRanker.foods(for: item.name + " raw", limit: 3, recentIDs: []).first(where: { food in
            fits(food) && !KitchenMatcher.words(food.name).isDisjoint(with: ["raw", "dry", "uncooked"])
        }) { return raw }
        return VoiceFoodRanker.foods(for: item.name, limit: 3, recentIDs: []).first(where: fits)
    }

    /// A typical pack, in the food's own unit: a dozen eggs, a 500 g pack of meat, a litre of milk…
    static func packAmount(for item: CatalogItem, food: NutritionFood) -> Double {
        if food.basis == .serving { return item.category == .eggs ? 10 : 1 }
        if let own = packs[item.id] { return own }
        let name = item.name.lowercased()
        if name.contains("canned") || name.contains("(canned)") { return 400 }
        if name.contains("milk") || name.contains("kefir") || name.contains("broth") { return 1000 }
        switch item.category {
        case .eggs: return 600
        case .meat, .seafood, .frozen: return 500
        case .dairy, .beverages: return food.basis == .millilitres ? 1000 : 400
        case .bread: return 500
        case .vegetables, .fruits: return 1000
        case .grains, .legumes, .baking: return 500
        case .canned: return 400
        case .oils: return 500
        case .condiments, .nuts, .snacks: return 200
        case .spices: return 50
        }
    }

    /// Packs that the category rule gets badly wrong: single pieces, egg boxes, small tubs.
    static let packs: [String: Double] = [
        "eggs-6": 330, "eggs-10": 550, "eggs-12": 660, "free-range-eggs": 550,
        "lemon": 100, "lime": 70, "kiwi": 300, "avocado": 200, "cucumber": 300, "garlic": 60, "ginger": 100,
        "mango": 350, "pomegranate": 300, "grapefruit": 300, "pineapple": 900, "melon": 1200, "watermelon": 3000,
        "eggplant": 400, "zucchini": 500, "bell-pepper": 500, "chili-pepper": 50, "spring-onion": 100, "radish": 250,
        "celery": 500, "lettuce": 400, "arugula": 125, "spinach": 250, "kale": 250, "mushrooms": 400, "asparagus": 400,
        "cherry-tomatoes": 250, "strawberries": 400, "blueberries": 250, "raspberries": 150, "blackberries": 150,
        "cherries": 500, "figs": 250, "dates": 250, "grapes-green": 500, "grapes-red": 500,
        "butter": 200, "ghee": 250, "heavy-cream": 250, "sour-cream-15": 300, "sour-cream-30": 300, "cream-cheese": 200,
        "cottage-cheese": 250, "ricotta": 250, "feta": 200, "mozzarella": 125, "parmesan": 150, "brie": 125,
        "gouda": 250, "edam": 250, "cheddar": 250, "dziugas": 180,
        "white-rice": 1000, "brown-rice": 1000, "basmati-rice": 1000, "oats": 500, "instant-oats": 500, "buckwheat": 800,
        "bacon": 200, "ham": 200, "salami": 150, "smoked-salmon": 150, "canned-tuna": 160, "canned-sardines": 120,
        "whole-chicken": 1500, "tofu": 300,
    ]
}
