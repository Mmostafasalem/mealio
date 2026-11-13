import Foundation

/// On-device fallback data so the app is fully usable when the backend is
/// unreachable (offline, cold-starting, or not yet deployed).
///
/// `APIService` returns these when a network call fails, so the agent, deals,
/// map, and meal plan always have something to show. When the backend IS
/// reachable, live data is used instead.
enum FallbackData {

    // Vilnius store coordinates (match the backend's STORES table).
    private static let storeCoord: [String: (lat: Double, lon: Double)] = [
        "Maxima": (54.6872, 25.2797),
        "Rimi":   (54.6989, 25.2730),
        "Iki":    (54.6750, 25.2800),
        "Lidl":   (54.6680, 25.2750),
        "Norfa":  (54.7100, 25.2600),
    ]

    // MARK: - Deals (mirror of the on-sale items in deals_data.json)

    static let deals: [Deal] = [
        deal(101, "Chicken Breast Fillet", "Lietuviška", "🍗", "Maxima", "meat", 5.99, 3.99, 33, 165, 31, 0, 3.6, 500, "g", ["", ]),
        deal(102, "Salmon Fillet", "Rimi Fresh", "🐟", "Rimi", "fish", 9.99, 6.49, 35, 208, 25, 0, 13, 400, "g", ["fish"]),
        deal(103, "Greek Yogurt", "Biopasaka", "🥛", "Iki", "dairy", 2.49, 1.49, 40, 59, 10, 4, 0.4, 400, "g", ["milk"]),
        deal(104, "Whole Grain Bread", "Fazer", "🍞", "Maxima", "bread", 2.29, 1.59, 31, 230, 8, 41, 3, 700, "g", ["gluten"]),
        deal(105, "Eggs (12-pack)", "Vilniaus paukštynas", "🥚", "Lidl", "eggs", 3.49, 2.29, 34, 155, 13, 1, 11, 12, "vnt", ["eggs"]),
        deal(106, "Rolled Oats", "Naminė", "🌾", "Norfa", "grains", 1.99, 1.19, 40, 389, 13, 67, 7, 1, "kg", ["gluten"]),
        deal(107, "Cottage Cheese", "Rokiškio", "🥛", "Rimi", "dairy", 2.99, 1.99, 33, 98, 12, 3, 4, 500, "g", ["milk"]),
        deal(108, "Broccoli", "Lietuviška daržovė", "🥦", "Iki", "vegetables", 1.49, 0.99, 34, 34, 2.8, 7, 0.4, 500, "g", []),
        deal(109, "Canned Tuna in Water", "Starkist", "🐟", "Maxima", "fish", 2.19, 1.39, 37, 116, 26, 0, 1, 185, "g", ["fish"]),
        deal(110, "Bananas", "Chiquita", "🍌", "Lidl", "fruit", 1.29, 0.79, 39, 89, 1.1, 23, 0.3, 1, "kg", []),
        deal(111, "Pork Tenderloin", "Krekenavos", "🥩", "Norfa", "meat", 7.49, 5.49, 27, 143, 26, 0, 3.5, 600, "g", []),
        deal(113, "Semi-skimmed Milk 2.5%", "Dvaro", "🥛", "Rimi", "dairy", 1.19, 0.89, 25, 50, 3.3, 4.8, 2.5, 1, "l", ["milk"]),
    ]

    private static func deal(_ id: Int, _ name: String, _ brand: String, _ emoji: String,
                             _ store: String, _ category: String,
                             _ orig: Double, _ disc: Double, _ pct: Int,
                             _ kcal: Int, _ protein: Double, _ carbs: Double, _ fat: Double,
                             _ qty: Int, _ unit: String, _ allergens: [String]) -> Deal {
        let coord = storeCoord[store] ?? (54.6872, 25.2797)
        return Deal(
            id: id, name: name, brand: brand, emoji: emoji, store: store,
            originalPrice: orig, discountedPrice: disc, discount: pct,
            category: category, kcalPer100g: kcal, proteinPer100g: protein,
            carbsPer100g: carbs, fatPer100g: fat, weeklyQty: qty, unit: unit,
            expiresIn: "3 days", allergens: allergens.filter { !$0.isEmpty },
            latitude: coord.lat, longitude: coord.lon
        )
    }

    // MARK: - Meal plan (local generator)

    private struct StockFood {
        let name: String
        let category: String   // lowercased category key
        let kcal100: Int       // realistic kcal per 100g
        var allergens: [String] = []

        func isAllowed(by prefs: Set<DietaryPreference>) -> Bool {
            prefs.allows(name: name, category: category, allergens: allergens)
        }
    }

    /// Builds a realistic offline 7-day plan. Composes balanced meals
    /// (protein + carb + veg) from the user's in-stock foods at believable
    /// serving sizes — not one giant single food. Calories 25/35/30/10.
    ///
    /// Every food (cart items and built-in defaults) is checked against the
    /// user's diets and allergies; a conflicting food is substituted with a
    /// safe alternative or left out, never shown.
    static func mealPlan(targetKcal: Int, pantry: [Deal] = [],
                         preferences: Set<DietaryPreference> = .load()) -> WeeklyMealPlan {
        let kcal = max(targetKcal, 1200)
        let (allStock, baseMessage) = resolveStock(pantry: pantry)
        let stock = allStock.filter { $0.isAllowed(by: preferences) }
        guard !stock.isEmpty else { return genericMealPlan(targetKcal: kcal, preferences: preferences) }
        let planMessage = stock.count < allStock.count
            ? baseMessage + " Items that conflict with your dietary preferences were left out."
            : baseMessage

        // Group in-stock foods by culinary role.
        let proteins = stock.filter { ["meat", "poultry", "seafood", "fish", "eggs", "legumes"].contains($0.category) }
        let carbs    = stock.filter { ["grains", "pasta", "bread", "rice"].contains($0.category) }
        let veg       = stock.filter { $0.category == "vegetables" }
        let fruits   = stock.filter { ["fruit", "fruits"].contains($0.category) }
        let dairy    = stock.filter { $0.category == "dairy" }
        let nutsSnacks = stock.filter { ["nuts", "snacks", "seeds"].contains($0.category) }

        func firstSafe(_ options: [StockFood]) -> StockFood? {
            options.first { $0.isAllowed(by: preferences) }
        }
        // Balanced defaults so meals stay realistic even if the cart is one-note.
        // Each slot lists safe-for-more-diets alternatives after the usual pick.
        let mixedVeg = StockFood(name: "Mixed vegetables", category: "vegetables", kcal100: 42)
        let defCarb  = firstSafe(carbs + [StockFood(name: "Rice", category: "grains", kcal100: 130),
                                          StockFood(name: "Potatoes", category: "vegetables", kcal100: 87)])
        let defVeg   = firstSafe(veg) ?? mixedVeg
        let defFruit = firstSafe(fruits + [StockFood(name: "Banana", category: "fruits", kcal100: 89),
                                           StockFood(name: "Strawberries", category: "fruits", kcal100: 32)])
        let grain    = firstSafe([StockFood(name: "Oats", category: "grains", kcal100: 389),
                                  StockFood(name: "Buckwheat", category: "grains", kcal100: 343)])
        let yogurt   = firstSafe(dairy + [StockFood(name: "Greek yogurt", category: "dairy", kcal100: 97),
                                          StockFood(name: "Soy yogurt", category: "legumes", kcal100: 60),
                                          StockFood(name: "Chia pudding", category: "seeds", kcal100: 120)])
        let snackNut = firstSafe(nutsSnacks + [StockFood(name: "Almonds", category: "nuts", kcal100: 579),
                                               StockFood(name: "Pumpkin seeds", category: "seeds", kcal100: 559)])
        let defaultProteins = [StockFood(name: "Chicken breast", category: "meat", kcal100: 165),
                               StockFood(name: "Baked cod", category: "fish", kcal100: 105),
                               StockFood(name: "Eggs", category: "eggs", kcal100: 155),
                               StockFood(name: "Tofu", category: "legumes", kcal100: 144),
                               StockFood(name: "Lentils", category: "legumes", kcal100: 116)]
        let safeProteins = proteins.isEmpty ? defaultProteins.filter { $0.isAllowed(by: preferences) } : proteins
        func protein(_ i: Int) -> StockFood? {
            safeProteins.isEmpty ? nil : safeProteins[i % safeProteins.count]
        }

        typealias Component = (food: StockFood, base: Int, maxG: Int, label: String)
        // Compose a meal from components, nudging portions toward the calorie
        // target but capping them so servings stay believable.
        func compose(_ comps: [Component?], target: Int, name: (([StockFood]) -> String)? = nil) -> MealItem {
            var comps = comps.compactMap { $0 }
            if comps.isEmpty { comps = [(mixedVeg, 200, 300, "1 bowl")] }
            let baseKcal = comps.reduce(0) { $0 + $1.base * $1.food.kcal100 / 100 }
            let factor = baseKcal > 0 ? Double(target) / Double(baseKcal) : 1
            var total = 0
            var ings: [String] = []
            for c in comps {
                let g = min(max(Int(Double(c.base) * factor), 20), c.maxG)
                total += g * c.food.kcal100 / 100
                ings.append("\(c.food.name) · \(c.label) (\(g)g)")
            }
            let foods = comps.map(\.food)
            let title = name?(foods) ?? Self.title(foods)
            return MealItem(pavadinimas: title, ingredientai: ings, kcal: total)
        }
        func plate(_ p: StockFood?, carbBase: Int, carbMax: Int, target: Int) -> MealItem {
            compose([
                p.map { ($0, 170, 250, "½ plate") },
                defCarb.map { ($0, carbBase, carbMax, "¼ plate") },
                (defVeg, 120, 200, "¼ plate"),
            ], target: target) { foods in
                guard let first = foods.first else { return "Vegetables" }
                let rest = foods.dropFirst().map { $0.name == defVeg.name ? "veg" : $0.name.lowercased() }
                return rest.isEmpty ? first.name : "\(first.name) with \(rest.joined(separator: " & "))"
            }
        }

        let bT = Int(Double(kcal) * 0.25)
        let lT = Int(Double(kcal) * 0.35)
        let dT = Int(Double(kcal) * 0.30)
        let sT = kcal - bT - lT - dT

        func day(_ i: Int) -> DayPlan {
            let breakfast = compose([
                grain.map    { ($0, 60, 100, "1 bowl") },
                defFruit.map { ($0, 120, 160, "1 piece") },
                yogurt.map   { ($0, 150, 250, "½ cup") },
            ], target: bT)
            let lunch  = plate(protein(i),     carbBase: 150, carbMax: 250, target: lT)
            let dinner = plate(protein(i + 1), carbBase: 130, carbMax: 220, target: dT)
            let snack = compose([
                defFruit.map { ($0, 120, 160, "1 piece") },
                snackNut.map { ($0, 25, 40, "1 handful") },
            ], target: sT)
            let total = breakfast.kcal + lunch.kcal + dinner.kcal + snack.kcal
            return DayPlan(pusryciai: breakfast, pietus: lunch, vakariene: dinner, uzkandziai: snack, visoKcal: total)
        }

        return WeeklyMealPlan(
            agentMessage: planMessage,
            pirmadienis:    day(0),
            antradienis:    day(1),
            treciadienis:   day(2),
            ketvirtadienis: day(3),
            pentadienis:    day(4),
            sestadienis:    day(5),
            sekmadienis:    day(6)
        )
    }

    /// "Oats, banana & greek yogurt" from the meal's component names.
    private static func title(_ foods: [StockFood]) -> String {
        let names = foods.enumerated().map { $0.offset == 0 ? $0.element.name : $0.element.name.lowercased() }
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " & " + names.last!
    }

    // MARK: - Stock resolution

    private static func resolveStock(pantry: [Deal]) -> (stock: [StockFood], message: String) {
        if let cart = cartPantry(), !cart.isEmpty {
            let budget = UserDefaults.standard.double(forKey: "weeklyBudget")
            let budgetStr = budget > 0 ? String(format: " (within your €%.0f budget)", budget) : ""
            return (cart, "Offline plan built around your cart — \(cart.count) item\(cart.count == 1 ? "" : "s")\(budgetStr).")
        }
        let groceries = groceryPantry()
        if !groceries.isEmpty {
            return (groceries, "Offline plan built around your shopping list — \(groceries.count) items.")
        }
        let deals = pantry.map {
            StockFood(name: $0.name, category: $0.category.lowercased(), kcal100: max($0.kcalPer100g, 1),
                      allergens: $0.allergens)
        }
        if !deals.isEmpty {
            return (deals, "Offline plan built from this week's deals.")
        }
        return ([], "")
    }

    /// Shop-tab cart (ShoppingCartService) read from disk, with real per-item
    /// calories via the catalog id.
    private static func cartPantry() -> [StockFood]? {
        let items = ResilientStorage.loadArray(CartItem.self, key: "shoppingCart_v1")
        guard !items.isEmpty else { return nil }
        return items.map { item in
            let cat = item.category.lowercased()
            let kcal = itemKcal[item.catalogId] ?? categoryKcal[cat] ?? 150
            return StockFood(name: item.name, category: cat, kcal100: kcal)
        }
    }

    private static func groceryPantry() -> [StockFood] {
        GroceryStorage.load().map { item in
            if let f = Food.catalog.first(where: {
                $0.id == item.foodId
                || "\($0.backendId ?? -1)" == item.foodId
                || $0.nameEn.lowercased() == item.foodName.lowercased()
            }) {
                return StockFood(name: f.nameEn, category: f.category.rawValue.lowercased(), kcal100: max(f.caloriesPer100g, 1))
            }
            return StockFood(name: item.foodName, category: "other", kcal100: 150)
        }
    }

    // MARK: - Nutrition tables

    /// Realistic kcal/100g (cooked where relevant) for common catalog items.
    private static let itemKcal: [String: Int] = [
        // Meat & poultry
        "chicken-breast": 165, "chicken-thighs": 209, "chicken-wings": 203,
        "whole-chicken": 215, "ground-chicken": 143, "turkey-breast": 135,
        "ground-turkey": 150, "pork-tenderloin": 143, "pork-chops": 231,
        "pork-belly": 518, "ground-pork": 263, "beef-steak": 215, "ground-beef": 215,
        "lamb-chops": 294, "bacon": 541, "ham": 145, "sausages": 300, "duck-breast": 337,
        // Fish & seafood
        "salmon-fillet": 208, "trout-fillet": 141, "cod-fillet": 105, "hake-fillet": 90,
        "pollock": 92, "tilapia": 96, "sea-bass": 124, "tuna-steak": 132,
        "canned-tuna": 116, "shrimp": 99, "prawns": 99, "mackerel": 205,
        // Eggs
        "eggs-6": 155, "eggs-10": 155, "eggs-12": 155, "free-range-eggs": 155,
        // Carbs / grains
        "white-rice": 130, "brown-rice": 123, "basmati-rice": 130, "potato": 87,
        "sweet-potato": 90, "spaghetti": 158, "penne": 158, "fusilli": 158,
        "oats": 389, "instant-oats": 389, "buckwheat": 92, "quinoa": 120, "couscous": 112,
        // Bread
        "whole-grain-bread": 247, "rye-bread": 259, "white-bread": 265, "sourdough-bread": 250,
        // Veg
        "broccoli": 34, "cauliflower": 25, "spinach": 23, "carrot": 41, "tomato": 18,
        "cucumber": 15, "bell-pepper": 31, "zucchini": 17, "green-beans": 31, "mushrooms": 22,
        // Fruit
        "banana": 89, "apple": 52, "orange": 47, "pear": 57, "strawberries": 32,
        // Dairy
        "greek-yogurt": 97, "plain-yogurt": 61, "cottage-cheese": 98, "milk-25": 50,
        "cheddar": 402, "feta": 264, "mozzarella": 280,
        // Nuts
        "almonds": 579, "walnuts": 654, "peanuts": 567, "mixed-nuts": 607, "cashews": 553,
        // Oils
        "olive-oil": 884, "extra-virgin-olive": 884,
    ]

    /// Per-category fallback energy density (kcal/100g).
    private static let categoryKcal: [String: Int] = [
        "meat": 200, "poultry": 170, "fish": 130, "seafood": 110, "dairy": 90,
        "eggs": 155, "bread": 260, "bakery": 300, "vegetables": 35, "fruits": 55,
        "fruit": 55, "grains": 360, "pasta": 360, "legumes": 130, "snacks": 450,
        "nuts": 600, "beverages": 40, "frozen": 120, "oils": 880, "condiments": 150,
        "canned": 90, "spices": 100, "baking": 380,
    ]

    /// 7 balanced template days — used when no groceries are logged yet.
    /// A template meal that conflicts with the user's diets/allergies is
    /// replaced by the next safe alternative for that slot.
    private static func genericMealPlan(targetKcal: Int, preferences: Set<DietaryPreference>) -> WeeklyMealPlan {
        let kcal = max(targetKcal, 1200)
        let b = Int(Double(kcal) * 0.25)
        let l = Int(Double(kcal) * 0.35)
        let d = Int(Double(kcal) * 0.30)
        let s = kcal - b - l - d

        // (breakfast, lunch, dinner, snack)
        let days: [(String, String, String, String)] = [
            ("Oatmeal with banana",     "Chicken breast with rice",  "Salmon with vegetables",     "Greek yogurt"),
            ("Scrambled eggs on toast", "Tuna salad wrap",           "Beef stir-fry with noodles", "Cottage cheese"),
            ("Greek yogurt & berries",  "Lentil soup",               "Baked cod with broccoli",    "Handful of almonds"),
            ("Protein pancakes",        "Turkey & rice bowl",        "Pork tenderloin & potatoes", "Banana"),
            ("Avocado toast with eggs", "Chicken Caesar salad",      "Pasta with tomato sauce",    "Oats with milk"),
            ("Cottage cheese & fruit",  "Salmon rice bowl",          "Beef burger (no bun)",       "Apple & peanut butter"),
            ("Muesli with milk",        "Vegetable omelette",        "Roast chicken & veggies",    "Mixed nuts"),
        ]
        // Substitutes in rough order of how many diets they suit. The last
        // entry in each list conflicts with no DietaryPreference case.
        let alternatives: [[String]] = [
            ["Tofu scramble with spinach", "Buckwheat porridge with berries", "Chia pudding with berries",
             "Avocado, tomato & cucumber plate"],
            ["Chickpea & vegetable stew", "Quinoa & roasted vegetable bowl", "Baked cod with green beans",
             "Mixed vegetable salad with olive oil"],
            ["Vegetable curry with rice", "Stuffed peppers with rice", "Grilled salmon with broccoli",
             "Roasted vegetables with olive oil"],
            ["Apple", "Hummus & carrot sticks", "Strawberries", "Cucumber & carrot sticks"],
        ]
        func safe(_ name: String) -> Bool { preferences.allows(name: name) }
        func pick(_ name: String, slot: Int, day: Int) -> String {
            if safe(name) { return name }
            let options = alternatives[slot].filter(safe)
            return options.isEmpty ? alternatives[slot].last! : options[day % options.count]
        }

        func meal(_ name: String, _ c: Int) -> MealItem {
            MealItem(pavadinimas: name, ingredientai: [], kcal: c)
        }
        func day(_ i: Int) -> DayPlan {
            let t = days[i]
            return DayPlan(pusryciai: meal(pick(t.0, slot: 0, day: i), b), pietus: meal(pick(t.1, slot: 1, day: i), l),
                           vakariene: meal(pick(t.2, slot: 2, day: i), d), uzkandziai: meal(pick(t.3, slot: 3, day: i), s),
                           visoKcal: kcal)
        }

        let note = preferences.isEmpty ? "" : " Meals follow your dietary preferences."
        return WeeklyMealPlan(
            agentMessage: "Offline plan targeting \(kcal) kcal/day.\(note) Connect to get AI-personalised plans.",
            pirmadienis:  day(0),
            antradienis:  day(1),
            treciadienis: day(2),
            ketvirtadienis: day(3),
            pentadienis:  day(4),
            sestadienis:  day(5),
            sekmadienis:  day(6)
        )
    }
}
