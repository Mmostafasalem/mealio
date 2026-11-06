import Foundation
import SwiftUI

// MARK: - Cart item

struct CartItem: Codable, Identifiable, Hashable {
    let id: UUID
    let catalogId: String
    let name: String
    let store: String
    let price: Double          // single estimated price (or the real price the user entered)
    let category: String
    var quantity: Int

    var lineTotal: Double { price * Double(quantity) }
}

// MARK: - Shopping store definition

struct ShopStore: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let colorHex: String
    let priceMultiplier: Double

    var color: Color { Color(hex: colorHex) }

    static let all: [ShopStore] = [
        ShopStore(id: "rimi",   name: "Rimi",   tagline: "Fresh & quality picks",    colorHex: "#DC2626", priceMultiplier: 1.06),
        // Legacy slogans are intentionally not rendered: these are catalog estimates, not retailer price rankings.
        ShopStore(id: "maxima", name: "Maxima", tagline: "Everyday low prices",      colorHex: "#1D4ED8", priceMultiplier: 1.00),
        ShopStore(id: "iki",    name: "Iki",    tagline: "Your neighbourhood store", colorHex: "#7C3AED", priceMultiplier: 1.03),
        ShopStore(id: "lidl",   name: "Lidl",   tagline: "Best value in Lithuania",  colorHex: "#1E40AF", priceMultiplier: 0.88),
        ShopStore(id: "norfa",  name: "Norfa",  tagline: "Local & affordable",       colorHex: "#15803D", priceMultiplier: 0.92),
    ]
}

// MARK: - Price helpers for static catalog

extension CatalogItem {

    // Hand-curated budget estimates (€) per typical unit/package, not a live
    // retailer feed or verified current shelf prices. Store multipliers are
    // heuristics; shoppers can enter a correction for a specific store.
    static let itemBasePrices: [String: Double] = [
        // Meat & Poultry
        "chicken-breast": 5.49, "chicken-thighs": 4.29, "chicken-wings": 3.79,
        "whole-chicken": 5.99, "ground-chicken": 3.99, "pork-tenderloin": 7.99,
        "pork-belly": 5.49, "pork-ribs": 8.49, "pork-chops": 5.99,
        "ground-pork": 4.49, "beef-steak": 10.99, "ground-beef": 6.99,
        "beef-ribs": 8.99, "lamb-chops": 13.99, "ground-lamb": 10.49,
        "turkey-breast": 7.99, "ground-turkey": 5.99, "duck-breast": 9.99,
        "bacon": 3.29, "ham": 3.49, "salami": 3.29, "sausages": 3.79,
        "hot-dogs": 2.79, "chicken-liver": 2.29,
        // Fish & Seafood
        "salmon-fillet": 5.99, "trout-fillet": 4.99, "cod-fillet": 4.49,
        "hake-fillet": 3.99, "pollock": 3.49, "tilapia": 3.99,
        "sea-bass": 6.99, "tuna-steak": 7.99, "herring": 3.49,
        "mackerel": 3.99, "canned-tuna": 1.29, "canned-sardines": 1.09,
        "canned-herring": 1.49, "shrimp": 5.99, "prawns": 7.49,
        "mussels": 4.99, "crab-sticks": 2.49, "smoked-salmon": 5.49,
        "smoked-mackerel": 3.49, "anchovies": 2.49,
        // Dairy
        "milk-25": 0.99, "milk-35": 1.09, "skimmed-milk": 0.89,
        "oat-milk": 1.89, "almond-milk": 1.99, "kefir": 0.99,
        "greek-yogurt": 1.79, "plain-yogurt": 0.89, "sour-cream-15": 0.99,
        "sour-cream-30": 1.29, "heavy-cream": 1.49, "cottage-cheese": 1.49,
        "ricotta": 2.49, "cream-cheese": 1.99, "butter": 2.49,
        "ghee": 6.99, "gouda": 3.99, "edam": 3.49, "cheddar": 3.99,
        "mozzarella": 1.99, "feta": 2.99, "parmesan": 4.99,
        "brie": 3.49, "dziugas": 5.99,
        // Eggs
        "eggs-6": 1.49, "eggs-10": 2.29, "eggs-12": 2.79, "free-range-eggs": 3.29,
        // Bread & Bakery
        "whole-grain-bread": 1.99, "rye-bread": 1.69, "white-bread": 1.29,
        "sourdough-bread": 2.49, "baguette": 0.79, "ciabatta": 1.49,
        "pita-bread": 1.29, "tortillas": 1.49, "bagels": 1.99,
        "crispbread": 1.79, "english-muffins": 1.99, "croissants": 2.49,
        "flatbread": 1.29, "bread-rolls": 1.49,
        // Vegetables
        "potato": 1.09, "sweet-potato": 1.49, "onion": 0.79,
        "red-onion": 1.09, "spring-onion": 0.79, "leek": 0.99,
        "garlic": 1.29, "shallots": 1.49, "carrot": 0.89,
        "beet": 0.99, "parsnip": 1.29, "radish": 0.79,
        "cabbage": 0.89, "red-cabbage": 1.09, "sauerkraut": 0.99,
        "broccoli": 1.49, "cauliflower": 1.29, "brussels-sprouts": 1.49,
        "spinach": 1.29, "kale": 1.49, "lettuce": 1.09,
        "arugula": 1.49, "cucumber": 0.59, "tomato": 1.29,
        "cherry-tomatoes": 1.99, "bell-pepper": 0.99, "chili-pepper": 0.79,
        "zucchini": 0.99, "eggplant": 1.29, "asparagus": 2.49,
        "celery": 1.09, "corn": 0.79, "mushrooms": 1.99,
        "green-beans": 1.29, "pumpkin": 1.49, "butternut-squash": 1.79,
        // Fruits
        "apple": 1.29, "pear": 1.49, "banana": 1.09,
        "orange": 1.49, "mandarin": 1.69, "grapefruit": 0.79,
        "lemon": 0.49, "lime": 0.39, "grapes-green": 2.49,
        "grapes-red": 2.99, "strawberries": 2.99, "blueberries": 3.49,
        "raspberries": 2.99, "blackberries": 2.49, "cherries": 3.99,
        "peach": 1.99, "nectarine": 1.99, "plum": 1.49,
        "apricot": 1.79, "mango": 1.49, "pineapple": 1.99,
        "kiwi": 0.49, "avocado": 0.99, "watermelon": 2.99,
        "melon": 2.49, "pomegranate": 1.99, "dates": 2.99, "figs": 2.49,
        // Grains & Pasta
        "white-rice": 1.49, "brown-rice": 1.99, "basmati-rice": 2.99,
        "arborio-rice": 2.49, "oats": 1.29, "instant-oats": 1.49,
        "buckwheat": 1.49, "millet": 1.49, "barley": 1.29,
        "bulgur": 1.79, "couscous": 1.99, "quinoa": 3.99,
        "polenta": 1.49, "spaghetti": 0.99, "penne": 0.99,
        "fusilli": 0.99, "rigatoni": 1.09, "tagliatelle": 1.49,
        "lasagna-sheets": 1.29, "orzo": 1.49, "egg-noodles": 1.29,
        "rice-noodles": 1.49, "soba-noodles": 2.49, "bread-crumbs": 0.99,
        // Legumes
        "red-lentils": 1.49, "green-lentils": 1.49, "black-lentils": 1.79,
        "chickpeas-dried": 1.29, "chickpeas-canned": 0.89, "black-beans": 0.89,
        "white-beans": 0.89, "red-kidney-beans": 0.99, "cannellini-beans": 0.99,
        "pinto-beans": 0.99, "green-peas-frozen": 1.09, "green-peas-canned": 0.79,
        "edamame": 2.49, "soybeans": 1.49,
        // Canned & Preserved
        "canned-tomatoes": 0.79, "tomato-paste": 0.59, "tomato-sauce": 0.99,
        "canned-corn": 0.79, "canned-mushrooms": 0.99, "canned-salmon": 2.99,
        "coconut-milk": 1.49, "vegetable-broth": 1.29, "chicken-broth": 1.49,
        "beef-broth": 1.49, "pickles": 1.29, "olives": 1.99,
        "artichoke-hearts": 2.99, "sun-dried-tomatoes": 2.49, "capers": 1.99,
        "roasted-peppers": 1.79, "bamboo-shoots": 1.29, "water-chestnuts": 1.49,
        // Frozen
        "frozen-peas": 1.49, "frozen-corn": 1.29, "frozen-spinach": 1.49,
        "frozen-broccoli": 1.79, "frozen-veg-mix": 1.99, "frozen-berries": 3.49,
        "frozen-mango": 2.99, "frozen-fish-fillets": 4.99, "frozen-shrimp": 5.99,
        "frozen-pizza": 4.99, "frozen-fries": 1.99, "frozen-dumplings": 3.99,
        "frozen-edamame": 2.99, "ice-cream": 2.99,
        // Oils & Fats
        "extra-virgin-olive": 7.99, "olive-oil": 5.49, "sunflower-oil": 1.79,
        "rapeseed-oil": 1.99, "coconut-oil": 5.99, "avocado-oil": 7.99,
        "sesame-oil": 3.99, "truffle-oil": 14.99, "margarine": 1.79, "lard": 1.49,
        // Condiments & Sauces
        "ketchup": 1.29, "yellow-mustard": 0.89, "dijon-mustard": 1.79,
        "mayonnaise": 1.49, "balsamic-vinegar": 2.49, "apple-cider-vinegar": 1.99,
        "white-wine-vinegar": 1.29, "soy-sauce": 1.69, "tamari": 2.99,
        "oyster-sauce": 2.49, "fish-sauce": 2.49, "worcestershire": 2.29,
        "hot-sauce": 1.99, "sriracha": 2.49, "hoisin-sauce": 2.29,
        "bbq-sauce": 2.49, "pesto": 2.49, "tahini": 3.49,
        "honey": 4.99, "maple-syrup": 5.99, "peanut-butter": 3.49, "almond-butter": 5.99,
        // Spices & Herbs
        "salt": 0.59, "black-pepper": 1.29, "cayenne-pepper": 1.49,
        "paprika": 1.29, "smoked-paprika": 1.49, "cumin": 1.29,
        "coriander": 1.29, "turmeric": 1.49, "curry-powder": 1.79,
        "garam-masala": 2.49, "chili-flakes": 1.29, "oregano": 0.99,
        "basil": 0.99, "thyme": 0.99, "rosemary": 1.09,
        "bay-leaves": 0.89, "dill": 0.99, "cinnamon": 1.29,
        "nutmeg": 1.79, "cardamom": 2.99, "vanilla": 2.99,
        "garlic-powder": 1.49, "onion-powder": 1.29, "dried-ginger": 1.49,
        // Nuts & Seeds
        "almonds": 3.99, "walnuts": 3.49, "cashews": 4.99,
        "peanuts": 1.99, "hazelnuts": 3.99, "pecans": 5.99,
        "pistachios": 5.49, "pine-nuts": 4.99, "sunflower-seeds": 1.29,
        "pumpkin-seeds": 1.79, "sesame-seeds": 1.29, "chia-seeds": 2.99,
        "flaxseeds": 1.49, "mixed-nuts": 4.49,
        // Snacks
        "potato-chips": 1.49, "tortilla-chips": 1.79, "rice-cakes": 1.49,
        "crackers": 1.29, "pretzels": 1.29, "popcorn": 1.29,
        "dark-chocolate": 1.49, "milk-chocolate": 1.49, "granola-bars": 2.99,
        "protein-bars": 2.49, "dried-fruit": 2.49, "beef-jerky": 3.99,
        // Beverages
        "still-water": 0.49, "sparkling-water": 0.59, "orange-juice": 1.49,
        "apple-juice": 1.29, "grapefruit-juice": 1.49, "tomato-juice": 1.09,
        "green-tea": 1.49, "black-tea": 1.29, "herbal-tea": 1.79,
        "coffee-beans": 6.99, "ground-coffee": 4.99, "instant-coffee": 3.99,
        "beer": 0.89, "red-wine": 5.99, "white-wine": 5.49,
        "sparkling-wine": 7.99, "kombucha": 2.49, "energy-drink": 1.09,
        "coconut-water": 1.99, "protein-shake": 3.49,
        // Baking
        "all-purpose-flour": 0.89, "whole-wheat-flour": 1.29, "bread-flour": 1.09,
        "almond-flour": 4.99, "baking-powder": 0.59, "baking-soda": 0.49,
        "yeast": 0.39, "cocoa-powder": 1.99, "dark-chocolate-chips": 2.49,
        "white-sugar": 0.79, "brown-sugar": 1.49, "powdered-sugar": 0.99,
        "cornstarch": 0.89, "vanilla-pod": 2.99,
    ]

    /// A single estimated shelf price. There is no real price feed, so nothing is
    /// ever presented as a "sale" or compared against a fabricated "regular" price.
    func estimatedPrice(for store: ShopStore) -> Double {
        let base = CatalogItem.itemBasePrices[id] ?? 1.99
        // ±5% variation per item so identical categories aren't identical prices.
        // Uses a STABLE hash so prices don't change between app launches.
        let nudge = 1.0 + (Double(id.stableHash % 10) - 5) / 100.0
        return (base * store.priceMultiplier * nudge).roundedTo2()
    }
}

private extension Double {
    func roundedTo2() -> Double { (self * 100).rounded() / 100 }
}

private extension String {
    /// Deterministic FNV-1a hash — stable across app launches, unlike the
    /// randomly-seeded `hashValue`. Returns a non-negative Int.
    var stableHash: Int {
        var h: UInt64 = 1469598103934665603
        for byte in utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
        return Int(truncatingIfNeeded: h & 0x7FFF_FFFF)
    }
}

// MARK: - Cart service

@MainActor
@Observable
final class ShoppingCartService {

    static let shared = ShoppingCartService()
    private init() { load() }

    var cartItems: [CartItem] = []
    var weeklyBudget: Double = 60.0 { didSet { saveSettings() } }

    // Store-scoped corrections use cartRowId keys in the existing Sync dictionary.
    // Legacy catalog-only entries are retained for compatibility, but cannot
    // verify any store or supply new estimates. Re-enter them for a chosen store.
    private(set) var priceOverrides: [String: Double] = [:]

    func setRealPrice(_ price: Double, for catalogId: String, store: String) {
        guard price.isFinite, price > 0 else { return }
        priceOverrides[Self.cartRowId(catalogId: catalogId, store: store)] = price
        savePriceOverrides()
        // Update any matching cart items immediately
        for i in cartItems.indices where cartItems[i].catalogId == catalogId && cartItems[i].store == store {
            cartItems[i] = CartItem(
                id: cartItems[i].id, catalogId: catalogId,
                name: cartItems[i].name, store: cartItems[i].store,
                price: price, category: cartItems[i].category,
                quantity: cartItems[i].quantity
            )
        }
        save()
    }

    func isEstimated(_ catalogId: String, store: String) -> Bool {
        correctedPrice(for: catalogId, store: store) == nil
    }

    private func correctedPrice(for catalogId: String, store: String) -> Double? {
        guard let price = priceOverrides[Self.cartRowId(catalogId: catalogId, store: store)],
              price.isFinite, price > 0 else { return nil }
        return price
    }

    func effectivePrice(for item: CatalogItem, store: ShopStore) -> Double {
        correctedPrice(for: item.id, store: store.name) ?? item.estimatedPrice(for: store)
    }

    var total: Double { cartItems.reduce(0) { $0 + $1.lineTotal } }
    var itemCount: Int { cartItems.reduce(0) { $0 + $1.quantity } }
    var budgetRemaining: Double { weeklyBudget - total }
    var budgetFraction: Double { min(total / max(weeklyBudget, 1), 1) }

    var budgetColor: Color {
        switch budgetFraction {
        case ..<0.7:   return .brandPrimary
        case 0.7..<0.9: return .brandAmber
        default:       return .brandDanger
        }
    }

    // MARK: - Mutations

    func quantity(of catalogId: String, store: String) -> Int {
        cartItems.first { $0.catalogId == catalogId && $0.store == store }?.quantity ?? 0
    }

    func add(_ item: CatalogItem, store: ShopStore) {
        let price = effectivePrice(for: item, store: store)
        if let idx = cartItems.firstIndex(where: { $0.catalogId == item.id && $0.store == store.name }) {
            cartItems[idx].quantity += 1
        } else {
            cartItems.append(CartItem(
                id: UUID(), catalogId: item.id, name: item.name, store: store.name,
                price: price, category: item.category.rawValue, quantity: 1
            ))
        }
        save()
    }

    func remove(_ catalogId: String, store: String) {
        if let idx = cartItems.firstIndex(where: { $0.catalogId == catalogId && $0.store == store }) {
            if cartItems[idx].quantity > 1 {
                cartItems[idx].quantity -= 1
            } else {
                cartItems.remove(at: idx)
            }
        }
        save()
    }

    /// Undo merges removed quantities with current edits; never overwrite a newer cart.
    func restoreRemovedLines(_ lines: [CartItem]) {
        guard !lines.isEmpty else { return }
        for line in lines {
            if let index = cartItems.firstIndex(where: { $0.catalogId == line.catalogId && $0.store == line.store }) {
                cartItems[index].quantity += line.quantity
            } else {
                cartItems.append(CartItem(id: line.id, catalogId: line.catalogId, name: line.name,
                    store: line.store, price: correctedPrice(for: line.catalogId, store: line.store) ?? line.price,
                    category: line.category, quantity: line.quantity))
            }
        }
        save()
    }

    func clear() { cartItems = []; save() }

    func resetAll() {
        cartItems = []
        priceOverrides = [:]
        weeklyBudget = 60.0
        UserDefaults.standard.removeObject(forKey: cartKey)
        UserDefaults.standard.removeObject(forKey: budgetKey)
        UserDefaults.standard.removeObject(forKey: overridesKey)
        NotificationCenter.default.post(name: .cartDidChange, object: nil)
    }

    // MARK: - Persistence

    private let cartKey      = "shoppingCart_v1"
    private let budgetKey    = "weeklyBudget"
    private let overridesKey = "priceOverrides_v1"

    private func save() {
        guard let data = try? JSONEncoder().encode(cartItems) else { return }
        UserDefaults.standard.set(data, forKey: cartKey)
        syncToGroceryList()                                                 // mirror into Groceries tab
        NotificationCenter.default.post(name: .cartDidChange, object: nil)  // AgentLoop regenerates plan
    }

    /// Mirrors the cart into the unified grocery list so Shop items appear in the
    /// Groceries tab. Cart-sourced rows use a "cart_" id prefix and are replaced
    /// wholesale on every change (one-way sync — the cart is the source of truth).
    private func syncToGroceryList() {
        let existing = GroceryStorage.load()
        // Preserve "bought" state on cart-sourced rows across re-syncs.
        let boughtIds = Set(existing.filter { $0.id.hasPrefix("cart_") && $0.isBought }.map(\.id))
        var list = existing.filter { !$0.id.hasPrefix("cart_") }
        for ci in cartItems {
            let id = Self.cartRowId(catalogId: ci.catalogId, store: ci.store)
            list.append(GroceryItem(
                id: id,
                foodId: ci.catalogId,
                foodName: ci.name,
                quantity: String(ci.quantity),
                estimatedPrice: ci.lineTotal,
                storeId: ci.store.lowercased(),
                storeName: ci.store,
                isBought: boughtIds.contains(id)
            ))
        }
        GroceryStorage.save(list)
        NotificationCenter.default.post(name: .groceryListDidChange, object: nil)
    }

    /// Removes an entire cart line (all quantities) — used when the Groceries tab
    /// deletes a cart-sourced row, so the deletion round-trips back to the cart.
    func removeLine(catalogId: String, store: String) {
        cartItems.removeAll { $0.catalogId == catalogId && $0.store == store }
        save()
    }

    /// The grocery-row id format for cart-sourced rows (see `syncToGroceryList`).
    nonisolated static func cartRowId(catalogId: String, store: String) -> String {
        "cart_\(catalogId)_\(store)"
    }

    /// Parses a `cart_<catalogId>_<store>` grocery-row id back into its cart
    /// coordinates so a Groceries-tab removal can round-trip to the cart. Store
    /// names contain no underscore and catalog ids use dashes, so the LAST
    /// underscore is the separator. Returns nil for non-cart ids.
    nonisolated static func parseCartRowId(_ id: String) -> (catalogId: String, store: String)? {
        let prefix = "cart_"
        guard id.hasPrefix(prefix) else { return nil }
        let body = id.dropFirst(prefix.count)
        guard let sep = body.lastIndex(of: "_") else { return nil }
        let catalogId = String(body[..<sep])
        let store = String(body[body.index(after: sep)...])
        guard !catalogId.isEmpty, !store.isEmpty else { return nil }
        return (catalogId, store)
    }

    /// The cart expressed as `[Deal]` for the meal-plan request, so the *online*
    /// AI plan also prioritises what the user is buying (offline already does).
    func planDeals() -> [Deal] {
        cartItems.map { ci in
            Deal(
                id: ci.catalogId.stableHash % 1_000_000,
                name: ci.name, brand: "", emoji: "🛒", store: ci.store,
                originalPrice: ci.price, discountedPrice: ci.price,
                discount: 0,
                category: ci.category, kcalPer100g: 0, proteinPer100g: 0,
                carbsPer100g: 0, fatPer100g: 0, weeklyQty: ci.quantity, unit: "",
                expiresIn: "7 days", allergens: [], latitude: nil, longitude: nil
            )
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(weeklyBudget, forKey: budgetKey)
    }

    private func savePriceOverrides() {
        guard let data = try? JSONEncoder().encode(priceOverrides) else { return }
        UserDefaults.standard.set(data, forKey: overridesKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: cartKey),
           let items = try? JSONDecoder().decode([CartItem].self, from: data) {
            cartItems = items
        }
        let saved = UserDefaults.standard.double(forKey: budgetKey)
        weeklyBudget = saved > 0 ? saved : 60.0
        if let data = UserDefaults.standard.data(forKey: overridesKey),
           let overrides = try? JSONDecoder().decode([String: Double].self, from: data) {
            priceOverrides = overrides
        }
        syncToGroceryList()   // ensure the Groceries tab reflects the cart on launch
    }

    func reloadFromStorage() {
        cartItems = []
        priceOverrides = [:]
        load()
    }
}
