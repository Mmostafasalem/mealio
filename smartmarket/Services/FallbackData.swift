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

    // MARK: - Meal plan (built on the phone)
    //
    // One set of rules for every day of the week (and so for Today): breakfast is a
    // grain, a fruit and a dairy food; lunch and dinner are a plate of half protein,
    // a quarter carb and a quarter vegetables; the snack is a fruit and nuts. The
    // day's calories are split by the person's `MealSplit`, and portions are scaled
    // to each meal's share with believable caps. Foods come from the cart and My
    // Stock first; a role nothing owned can fill takes a catalogue food, marked as
    // missing so the person can add it.

    private struct StockFood {
        let name: String
        let category: String   // lowercased category key
        let kcal100: Int       // realistic kcal per 100g
        var allergens: [String] = []
        /// In the cart or My Stock (not just suggested from the catalogue).
        var owned = true
        /// The catalogue item to add when it isn't owned.
        var catalogId: String? = nil
        /// The food record behind it (stock's own, or the cart's match), for macros and logging.
        var nutrition: NutritionFood? = nil
        /// The full name, for rules that need more than the short display name.
        var key: String? = nil
        /// The person put it in their cart or My Stock themselves (a legacy pantry list didn't),
        /// so their own choice of meat is trusted under halal.
        var chosen = false

        func isAllowed(by prefs: Set<DietaryPreference>) -> Bool {
            prefs.allows(name: key ?? name, category: category, allergens: allergens, owned: chosen)
        }
    }

    /// The catalogue foods used when nothing owned fills a role, in order of preference.
    private static func suggested(_ name: String, _ category: String, _ kcal: Int, _ id: String?) -> StockFood {
        let record = id.flatMap { catalogNutrition($0) }
        return StockFood(name: name, category: category, kcal100: record.map { max(Int($0.kcal.rounded()), 1) } ?? kcal,
                         owned: false, catalogId: id, nutrition: record)
    }

    /// How many times the person asked for another plan. Each step pairs the foods
    /// differently (a protein with another carb, other vegetables), so "Regenerate"
    /// changes the plan even when the cart and stock haven't. Rebuilds keep it.
    static let variationKey = "mealPlanVariation_v1"

    static func mealPlan(targetKcal: Int, pantry: [Deal] = [],
                         preferences: Set<DietaryPreference> = .load(), split: MealSplit? = nil,
                         variation: Int? = nil) -> WeeklyMealPlan {
        let split = split ?? .current
        let s = max(0, variation ?? UserDefaults.standard.integer(forKey: variationKey))
        let kcal = max(targetKcal, 1200)
        let stock = ownedFoods(pantry: pantry).filter { $0.isAllowed(by: preferences) }

        func role(_ categories: [String]) -> [StockFood] { stock.filter { categories.contains($0.category) } }
        let proteins = role(["meat", "poultry", "seafood", "fish", "eggs", "legumes"])
        let carbs    = role(["grains", "pasta", "bread", "rice"])
        let veg      = role(["vegetables"])
        let fruits   = role(["fruit", "fruits"])
        let dairy    = role(["dairy"])
        let nuts     = role(["nuts"])
        let grains   = carbs.filter { c in ["oat", "buckwheat", "muesli", "granola", "porridge"].contains(where: (c.key ?? c.name).lowercased().contains) }

        /// Owned foods for a role, else the first suggestion the diet allows.
        func pool(_ owned: [StockFood], _ suggestions: [StockFood]) -> [StockFood] {
            if !owned.isEmpty { return owned }
            return suggestions.first { $0.isAllowed(by: preferences) }.map { [$0] } ?? []
        }
        let proteinPool = pool(proteins, [suggested("Chicken breast", "meat", 165, "chicken-breast"), suggested("Eggs", "eggs", 155, "free-range-eggs"),
                                          suggested("Red lentils", "legumes", 116, "red-lentils"), suggested("Chickpeas", "legumes", 139, "chickpeas-canned")])
        // Breakfast grains (oats, buckwheat) stay at breakfast; plates take the other carbs.
        let plateCarbs = carbs.filter { c in !grains.contains { $0.name == c.name } }
        let carbPool    = pool(plateCarbs, [suggested("Brown rice", "grains", 123, "brown-rice"), suggested("Potatoes", "vegetables", 87, "potato")])
        let vegPool     = pool(veg, [suggested("Broccoli", "vegetables", 34, "broccoli"), suggested("Mixed vegetables", "vegetables", 42, "frozen-veg-mix")])
        let fruitPool   = pool(fruits, [suggested("Banana", "fruits", 89, "banana"), suggested("Apple", "fruits", 52, "apple")])
        let grainPool   = pool(grains, [suggested("Oats", "grains", 389, "oats"), suggested("Buckwheat", "grains", 343, "buckwheat")])
        let dairyPool   = pool(dairy, [suggested("Greek yogurt", "dairy", 97, "greek-yogurt"), suggested("Kefir", "dairy", 52, "kefir"),
                                       suggested("Oat milk", "dairy", 46, "oat-milk")])
        let nutPool     = pool(nuts, [suggested("Almonds", "nuts", 579, "almonds"), suggested("Pumpkin seeds", "nuts", 559, "pumpkin-seeds")])

        func at(_ list: [StockFood], _ i: Int) -> StockFood? { list.isEmpty ? nil : list[i % list.count] }

        typealias Component = (food: StockFood, base: Int, maxG: Int, label: String)
        let capScale = max(1, Double(kcal) / 2000)
        func compose(_ comps: [Component?], target: Int, title: (([StockFood]) -> String)? = nil) -> MealItem? {
            let comps = comps.compactMap { $0 }
            guard target > 0, !comps.isEmpty else { return nil }
            let baseKcal = comps.reduce(0) { $0 + $1.base * $1.food.kcal100 / 100 }
            let factor = baseKcal > 0 ? Double(target) / Double(baseKcal) : 1
            var caps = comps.map { Double($0.maxG) * capScale }
            var grams = zip(comps, caps).map { c, cap in min(max(Double(c.base) * factor, 20), cap) }
            func kcalNow() -> Double { zip(comps, grams).reduce(0) { $0 + $1.1 * Double($1.0.food.kcal100) / 100 } }
            // Short of the target because something hit its cap: the rest of the plate takes
            // up the difference; only if everything is capped do the caps give a little.
            var relaxed = false
            for _ in 0..<4 {
                let deficit = Double(target) - kcalNow()
                guard deficit > Double(target) * 0.03 else { break }
                let open = comps.indices.filter { grams[$0] < caps[$0] - 0.5 }
                if open.isEmpty {
                    guard !relaxed else { break }
                    caps = caps.map { $0 * 1.35 }
                    relaxed = true
                    continue
                }
                let openKcal = open.reduce(0.0) { $0 + grams[$1] * Double(comps[$1].food.kcal100) / 100 }
                guard openKcal > 0 else { break }
                for i in open { grams[i] = min(grams[i] * (1 + deficit / openKcal), caps[i]) }
            }
            var total = 0
            var ings: [String] = []
            var records: [NutritionIngredient] = []
            for (c, amount) in zip(comps, grams) {
                let g = Int(amount)
                total += g * c.food.kcal100 / 100
                // Grains and pulses planned from their dry record say so ("70 g dry" of rice is a plateful).
                let dry = ["grains", "legumes"].contains(c.food.category) && c.food.kcal100 >= 250
                ings.append("\(c.food.name) · \(c.label) (\(g)g\(dry ? " dry" : ""))")
                if let food = c.food.nutrition { records.append(NutritionIngredient(food: food, amount: Double(g))) }
            }
            let foods = comps.map(\.food)
            let missing = foods.filter { !$0.owned }
            var item = MealItem(pavadinimas: title?(foods) ?? Self.title(foods), ingredientai: ings, kcal: total)
            // Every food matched to a record: the meal shows its macros and can be logged in one go.
            if records.count == comps.count {
                item.nutritionIngredients = records
                item.portions = records.map { PlannedPortion(foodID: $0.food.id, amount: $0.amount) }
            }
            if !missing.isEmpty {
                item.missing = missing.map(\.name)
                item.missingCatalogIds = missing.compactMap(\.catalogId)
            }
            return item
        }

        // Portions by what the food is: a plate takes far less dry rice than cooked, more raw
        // chicken than dry lentils, and potatoes by the handful. (base grams, most grams)
        func proteinSize(_ f: StockFood) -> (Int, Int) {
            if f.kcal100 >= 300 { return (80, 130) }            // dry pulses
            if f.category == "eggs" { return (150, 220) }       // three to four eggs
            return f.kcal100 >= 200 ? (150, 250) : (180, 320)   // fattier cuts, then lean meat and fish
        }
        func carbSize(_ f: StockFood) -> (Int, Int) {
            switch f.kcal100 {
            case 300...: return (70, 110)      // dry rice, pasta, grains
            case 200..<300: return (80, 140)   // bread
            case 100..<200: return (150, 280)  // cooked grains
            default: return (280, 420)         // potatoes
            }
        }
        func grainSize(_ f: StockFood) -> (Int, Int) { f.kcal100 >= 300 ? (60, 100) : (150, 250) }

        let t = split.targets(for: kcal)
        func day(_ i: Int) -> DayPlan {
            let breakfast = compose([
                at(grainPool, i + s).map { ($0, grainSize($0).0, grainSize($0).1, "1 bowl") },
                at(fruitPool, i + 2 * s).map { ($0, 120, 160, "1 piece") },
                at(dairyPool, i + 3 * s).map { ($0, 150, 250, "½ cup") },
            ], target: t.breakfast)
            func plate(_ offset: Int, carbShare: Int, target: Int) -> MealItem? {
                let v = at(vegPool, i + offset + 3 * s)
                return compose([
                    at(proteinPool, i + offset + s).map { ($0, proteinSize($0).0, proteinSize($0).1, "½ plate") },
                    at(carbPool, i + offset + 2 * s).map { ($0, carbSize($0).0 * carbShare / 100, carbSize($0).1, "¼ plate") },
                    v.map { ($0, 120, 200, "¼ plate") },
                ], target: target) { foods in
                    guard let first = foods.first else { return "Vegetables" }
                    let rest = foods.dropFirst().map { $0.name == v?.name ? "veg" : $0.name.lowercased() }
                    return rest.isEmpty ? first.name : "\(first.name) with \(rest.joined(separator: " & "))"
                }
            }
            let lunch = plate(0, carbShare: 100, target: t.lunch)
            let dinner = plate(1, carbShare: 88, target: t.dinner)   // a slightly lighter carb in the evening
            let snack = compose([
                at(fruitPool, i + 1 + 2 * s).map { ($0, 120, 160, "1 piece") },
                at(nutPool, i + s).map { ($0, 25, 40, "1 handful") },
            ], target: t.snack)
            let total = [breakfast, lunch, dinner, snack].compactMap { $0?.kcal }.reduce(0, +)
            return DayPlan(pusryciai: breakfast, pietus: lunch, vakariene: dinner, uzkandziai: snack, visoKcal: total)
        }

        let days = (0..<7).map(day)
        let missing = Set(days.flatMap { [$0.pusryciai, $0.pietus, $0.vakariene, $0.uzkandziai].compactMap { $0?.missing }.flatMap { $0 } })
        // Only claim the cart when something in it actually fills a meal (oil or drinks alone don't).
        let ownedInMeals = !(proteins + carbs + veg + fruits + dairy + nuts).isEmpty
        let cartItems = ResilientStorage.loadArray(CartItem.self, key: "shoppingCart_v1")
        var message: String
        if !ownedInMeals {
            message = "Nothing in your cart or stock makes a meal yet, so this plan uses catalogue foods (\(kcal) kcal a day)."
        } else if !cartItems.isEmpty {
            let saved = UserDefaults.standard.double(forKey: "weeklyBudget")
            message = cartMessage(itemCount: cartItems.count, total: cartItems.reduce(0) { $0 + $1.lineTotal },
                                  budget: saved > 0 ? saved : 60)
        } else {
            message = "Plan built from your stock: \(kcal) kcal a day."
        }
        if ownedInMeals, !missing.isEmpty {
            message += " Not in your cart or stock yet: \(missing.sorted().joined(separator: ", "))."
        }
        return WeeklyMealPlan(agentMessage: message,
                              pirmadienis: days[0], antradienis: days[1], treciadienis: days[2], ketvirtadienis: days[3],
                              pentadienis: days[4], sestadienis: days[5], sekmadienis: days[6])
    }

    /// The food record for a catalogue item: the same match the cart uses for My Stock, so
    /// "Review and log" finds it there. Nothing until the catalogue has been read.
    private static func catalogNutrition(_ catalogId: String) -> NutritionFood? {
        guard NutritionCatalogService.isLoaded else { return nil }
        if let cached = recordCache[catalogId] { return cached }
        let found: NutritionFood? = CatalogItem.all.first(where: { $0.id == catalogId })
            .flatMap { CartStockLink.food(for: $0) }
            .flatMap { $0.basis == .serving ? nil : $0 }
        recordCache[catalogId] = .some(found)
        return found
    }
    /// One search per catalogue item, not one per plan rebuild.
    private static var recordCache: [String: NutritionFood?] = [:]

    /// "Oats, banana & greek yogurt" from the meal's component names.
    private static func title(_ foods: [StockFood]) -> String {
        let names = foods.enumerated().map { $0.offset == 0 ? $0.element.name : $0.element.name.lowercased() }
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " & " + names.last!
    }

    // MARK: - What the person has

    /// The cart, then My Stock (without the packs the cart itself put there), then any
    /// pantry passed in. Each food once.
    private static func ownedFoods(pantry: [Deal]) -> [StockFood] {
        var foods: [StockFood] = []
        var seen = Set<String>()
        func add(_ f: StockFood) { if seen.insert(f.name.lowercased()).inserted { foods.append(f) } }
        let links = UserDefaults.standard.dictionary(forKey: "cartStockLinks_v1") as? [String: String] ?? [:]
        let stockItems = StockStore.shared.items
        for item in ResilientStorage.loadArray(CartItem.self, key: "shoppingCart_v1") {
            guard let role = planRole(name: item.name, category: item.category.lowercased()) else { continue }
            // The record My Stock holds for this cart line (so "Review and log" finds it), else the match.
            let linked = links[item.catalogId].flatMap { id in stockItems.first { $0.id.uuidString == id }?.food }
            let record = linked.flatMap { $0.basis == .serving ? nil : $0 } ?? catalogNutrition(item.catalogId)
            let kcal = record.map { max(Int($0.kcal.rounded()), 1) } ?? itemKcal[item.catalogId] ?? categoryKcal[role] ?? 150
            add(StockFood(name: item.name, category: role, kcal100: kcal, catalogId: item.catalogId, nutrition: record, key: item.name, chosen: true))
        }
        let fromCart = Set(links.values)
        var seenRecords = Set(foods.compactMap { $0.nutrition?.id })
        for item in stockItems where !fromCart.contains(item.id.uuidString) && item.amount > 0 && !item.isExpired() {
            guard seenRecords.insert(item.food.id).inserted, let food = stockFood(item.food) else { continue }
            add(food)
        }
        for deal in pantry {
            add(StockFood(name: deal.name, category: deal.category.lowercased(), kcal100: max(deal.kcalPer100g, 1), allergens: deal.allergens))
        }
        return foods
    }

    /// A My Stock food as a plan food: a short name and its role.
    private static func stockFood(_ food: NutritionFood) -> StockFood? {
        guard let role = planRole(name: food.name, category: "") else { return nil }
        // "Fish, salmon, Atlantic, raw" is Salmon, not Fish: group words give way to what follows.
        let parts = food.name.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let groups: Set<String> = ["fish", "nuts", "seeds", "cheese", "cereals", "beans", "crustaceans", "mollusks", "squash",
                                   "peppers", "spices", "beverages", "soup", "babyfood", "snacks", "nut"]
        var short = parts.first ?? food.name
        if parts.count > 1, groups.contains(short.lowercased()) {
            let second = parts[1]
            let lead = short.lowercased()
            short = ["cheese", "squash", "beans", "peppers"].contains(lead) ? "\(second) \(lead)" : second
        }
        let kcal100 = food.basis == .grams ? max(Int(food.kcal.rounded()), 1) : (categoryKcal[role] ?? 150)
        let display = short.prefix(1).uppercased() + short.dropFirst()
        return StockFood(name: display, category: role, kcal100: kcal100, nutrition: food.basis == .serving ? nil : food, key: food.name, chosen: true)
    }

    /// The part of the plan a food can play, from whole words of its name (then its shop
    /// category): "eggs" (protein), "seafood", "meat", "legumes", "dairy" (spoonable or
    /// drinkable, for breakfast), "grains" (potatoes count as the plate's carb),
    /// "fruits", "nuts" (nuts and seeds only), "vegetables". Fats, cheeses, sweets,
    /// sauces and seasonings play no part (nil), so butter is never breakfast's "½ cup"
    /// and an eggplant is never the protein.
    static func planRole(name: String, category: String) -> String? {
        let words = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let set = Set(words)
        func word(_ keys: [String]) -> Bool { words.contains { w in keys.contains { w == $0 || w == $0 + "s" || w == $0 + "es" } } }
        func prefix(_ keys: [String]) -> Bool { words.contains { w in keys.contains { w.hasPrefix($0) } } }
        // Never a plan component, whatever the category says.
        let excluded = ["onion", "onions", "shallot", "shallots", "chili", "chilli", "lemon", "lemons", "lime", "limes", "coconut",
                        "croissant", "croissants", "crumbs", "broth", "paste", "puree", "coffee", "tea", "garlic", "ginger", "herb", "herbs", "seasoning", "cocoa", "butter", "ghee", "margarine", "cream", "oil", "sauce", "ketchup", "mayonnaise", "mayo", "dressing", "jam", "honey",
                        "syrup", "sugar", "salt", "flour", "spice", "spices", "chips", "crisps", "chocolate", "candy", "cookie", "cookies",
                        "biscuit", "biscuits", "cake", "doughnut", "donut", "nutella", "nutmeg", "peppermint", "graham", "crackers",
                        "juice", "soda", "cola", "stock", "bouillon", "vinegar", "mustard", "gelatin", "yeast", "powder"]
        let peanutButter = set.contains("peanut") && set.contains("butter")
        if !peanutButter && words.contains(where: excluded.contains) && !set.contains("cottage") { return nil }
        // Seasonings, drinks, sauces and baking goods by shop category play no part either.
        if ["spices", "beverages", "condiments", "oils", "baking", "snacks"].contains(category) && !peanutButter && !word(["nut", "almond", "seed"]) { return nil }
        // Ground pepper is a spice; bell and sweet peppers are vegetables.
        if word(["pepper", "peppercorn"]) && !set.isDisjoint(with: ["black", "white", "cayenne", "ground", "peppercorn", "peppercorns"]) { return nil }
        if set.contains("eggplant") || set.contains("aubergine") { return "vegetables" }
        if word(["noodle"]) { return "grains" }      // egg noodles are pasta, not eggs
        if word(["tomato"]) { return "vegetables" }  // cherry tomatoes aren't cherries
        if word(["egg"]) { return "eggs" }
        if word(["salmon", "tuna", "cod", "fish", "shrimp", "prawn", "trout", "mackerel", "herring", "sardine", "hake", "pollock", "tilapia", "bass", "seafood"]) { return "seafood" }
        if word(["chicken", "turkey", "beef", "pork", "lamb", "ham", "veal", "duck", "steak", "mince", "sausage", "meatball"]) { return "meat" }
        if word(["lentil", "chickpea", "tofu", "tempeh", "edamame"]) || (word(["bean"]) && !set.contains("green")) { return "legumes" }
        if peanutButter || word(["almond", "walnut", "cashew", "peanut", "hazelnut", "pistachio", "pecan", "nut", "seed"]) && !set.contains("milk") { return "nuts" }
        // Cheese is a topping here, not a breakfast bowl; cottage cheese and quark are.
        if word(["yogurt", "yoghurt", "kefir", "milk", "quark", "skyr", "curd", "cottage", "buttermilk"]) { return "dairy" }
        if set.contains("cheese") || word(["feta", "mozzarella", "cheddar", "parmesan", "gouda", "edam", "brie"]) { return nil }
        if word(["potato", "yam"]) { return "grains" }
        if prefix(["oat"]) || word(["rice", "pasta", "spaghetti", "penne", "fusilli", "bread", "buckwheat", "quinoa", "couscous", "noodle",
                                    "bulgur", "barley", "millet", "rigatoni", "tagliatelle", "macaroni", "tortilla", "wrap", "bagel", "granola", "muesli"]) { return "grains" }
        if prefix(["berr"]) || word(["apple", "banana", "berry", "orange", "pear", "grape", "kiwi", "mango", "peach", "plum", "melon",
                                    "cherry", "cherrie", "apricot", "pineapple", "strawberr", "raspberr", "blueberr", "lemon", "lime", "fig", "date"]) { return "fruits" }
        if word(["broccoli", "spinach", "carrot", "tomato", "cucumber", "pepper", "zucchini", "courgette", "cabbage", "onion", "lettuce", "kale",
                 "cauliflower", "pea", "beet", "beetroot", "mushroom", "squash", "vegetable", "veg", "asparagus", "celery", "leek", "radish", "salad"])
            || (set.contains("green") && word(["bean"])) { return "vegetables" }
        // Nothing in the name: trust the shop's category for the clear cases only.
        switch category {
        case "meat", "poultry": return "meat"
        case "seafood", "fish": return "seafood"
        case "eggs": return "eggs"
        case "legumes": return "legumes"
        case "vegetables": return "vegetables"
        case "fruits", "fruit": return "fruits"
        case "nuts": return "nuts"
        case "grains", "pasta", "bread": return "grains"
        default: return nil
        }
    }

    /// Mentions the budget only as it really stands against the cart total.
    static func cartMessage(itemCount: Int, total: Double, budget: Double) -> String {
        let items = "\(itemCount) item\(itemCount == 1 ? "" : "s")"
        let budgetNote: String
        if budget <= 0 {
            budgetNote = ""
        } else if total <= budget {
            budgetNote = String(format: " (€%.2f, within your €%.2f budget)", total, budget)
        } else {
            budgetNote = String(format: " (€%.2f, €%.2f over your €%.2f budget)", total, total - budget, budget)
        }
        return "Plan built around your cart — \(items)\(budgetNote)."
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
        "oats": 389, "instant-oats": 389, "buckwheat": 343, "quinoa": 120, "couscous": 112,
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
        "fruit": 55, "grains": 130, "pasta": 158, "legumes": 130, "snacks": 450,
        "nuts": 600, "beverages": 40, "frozen": 120, "oils": 880, "condiments": 150,
        "canned": 90, "spices": 100, "baking": 380,
    ]


}
