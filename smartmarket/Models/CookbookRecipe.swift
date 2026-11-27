import Foundation

// MARK: - Recipes without AI
//
// About 1,500 recipes from the Wikibooks Cookbook (CC BY-SA 4.0), read by
// scripts/build-wikibooks-recipes.py: every ingredient line is turned into grams of
// one USDA food, and the nutrition per serving is the sum divided by the servings.
// The file is `Resources/Recipes.json.zlib`. The credit and the page link must stay
// under every recipe, and the adapted recipes stay CC BY-SA 4.0.

nonisolated struct CookbookRecipe: Codable, Identifiable, Hashable, Sendable {
    struct Line: Codable, Hashable, Sendable {
        /// The line as written on the page.
        let text: String
        /// The USDA food it was read as, if any.
        let food: String?
        let grams: Double?
        /// Words a stock item's name must contain to count as this ingredient ("chicken", "sweet pepper|bell pepper").
        let match: String?
        /// A kitchen basic (salt, pepper, everyday oil, water, sugar, flour, baking powder or
        /// soda, vinegar, stock, dried spices and herbs), set by the build script.
        let pantry: Bool?
        /// The recipe works without it ("for garnish", "optional").
        var optional: Bool? = nil

        init(text: String, food: String?, grams: Double?, match: String?, pantry: Bool?, optional: Bool? = nil) {
            self.text = text; self.food = food; self.grams = grams; self.match = match
            self.pantry = pantry; self.optional = optional
        }

        enum Kind: Sendable { case basic, optional, ingredient }

        /// Only the true basics are assumed to be in the kitchen. Anything else, however
        /// small the amount (lemon juice, rose water, a spoon of cream), is an ingredient
        /// that is either in stock or missing. A line with no flag is an ingredient.
        var kind: Kind {
            if pantry == true { return .basic }
            if optional == true { return .optional }
            return .ingredient
        }
        var isBasic: Bool { kind == .basic }
        var terms: [String] { (match ?? "").split(separator: "|").map(String.init) }
    }

    struct Macros: Codable, Hashable, Sendable {
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    enum Course: String, Codable, CaseIterable, Sendable {
        case breakfast, main, soup, salad, side, bread, dessert, sauce

        var title: String {
            switch self {
            case .breakfast: return "Breakfast"
            case .main: return "Meals"
            case .soup: return "Soups and stews"
            case .salad: return "Salads"
            case .side: return "Sides and starters"
            case .bread: return "Bread and baking"
            case .dessert: return "Desserts"
            case .sauce: return "Sauces and extras"
            }
        }
    }

    let id: String
    let title: String
    let url: String
    let course: Course
    let servings: Double
    let servingsEstimated: Bool
    let minutes: Int?
    let difficulty: Double?
    let ingredients: [Line]
    let steps: [String]
    let perServing: Macros
    let gramsPerServing: Double
    let tags: [String]

    var pageURL: URL? { URL(string: url) }

    /// The ingredients that decide whether it can be cooked: everything but the kitchen
    /// basics and the optional extras.
    var keyIngredients: [Line] { ingredients.filter { $0.kind == .ingredient } }

    /// One serving as a food for the log.
    var servingFood: NutritionFood {
        var food = NutritionFood(id: "cookbook:" + id, name: title, brand: nil, basis: .serving,
                                 kcal: perServing.kcal, protein: perServing.protein, carbs: perServing.carbs, fat: perServing.fat,
                                 source: .cookbook, sourceID: id, sourceDate: nil)
        food.menuURL = url
        food.summary = "About \(Int(gramsPerServing.rounded())) g a serving"
            + (servingsEstimated ? "; the number of servings is Nourlo's estimate." : ".")
        return food
    }

    /// Fits the person's diet. Allergies are strict; the tags come from the ingredients.
    func fits(_ prefs: Set<DietaryPreference>) -> Bool {
        let has = Set(tags)
        // A second check on the ingredients themselves, whatever the tags say.
        let terms = Set(ingredients.flatMap(\.terms))
        let meat: Set<String> = ["chicken", "beef", "pork", "lamb", "turkey", "ham", "bacon", "sausage", "fish", "salmon", "tuna", "shrimp", "cod", "crayfish"]
        if (prefs.contains(.vegetarian) || prefs.contains(.vegan)) && !terms.isDisjoint(with: meat) { return false }
        if (prefs.contains(.halal) || prefs.contains(.noPork)) && !terms.isDisjoint(with: ["pork", "ham", "bacon", "sausage"]) { return false }
        for pref in prefs {
            switch pref {
            case .vegan: if !has.contains("vegan") { return false }
            case .vegetarian: if !has.contains("vegetarian") { return false }
            case .glutenFree: if !has.contains("glutenFree") { return false }
            case .lactoseFree: if !has.contains("dairyFree") { return false }
            case .nutAllergy: if !has.contains("nutFree") { return false }
            case .noPork: if !has.contains("noPork") { return false }
            case .halal: if !(has.contains("halal") || has.contains("noPorkNoAlcohol")) { return false }
            case .keto: if perServing.carbs > 20 { return false }
            case .shellfishAllergy:
                let shellfish = ["shrimp", "prawn", "crab", "lobster", "mussel", "clam", "oyster", "scallop", "crayfish"]
                if ingredients.contains(where: { line in shellfish.contains { line.text.lowercased().contains($0) } }) { return false }
            case .paleo: if !has.contains("glutenFree") || !has.contains("dairyFree") { return false }
            }
        }
        return true
    }
}

// MARK: - The library

nonisolated enum CookbookLibrary {
    struct File: Decodable, Sendable {
        let credit: String
        let license: String
        let source: String
        let recipes: [CookbookRecipe]
    }

    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!

    /// Read once, on first use (about 3 MB of JSON; call from a background task).
    static let file: File? = {
        Bundle.main.url(forResource: "Recipes.json", withExtension: "zlib")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? ($0 as NSData).decompressed(using: .zlib) as Data }
            .flatMap { try? JSONDecoder().decode(File.self, from: $0) }
    }()

    static var recipes: [CookbookRecipe] { file?.recipes ?? [] }

    static func recipe(id: String) -> CookbookRecipe? { recipes.first { $0.id == id } }
}

// MARK: - What you have

/// Whether an ingredient is in the kitchen, by the words of the stock's food names.
/// "Peppers, sweet, red, raw" has a "sweet pepper"; "Eggs, Grade A, Large" has an "egg".
nonisolated struct KitchenMatcher: Sendable {
    /// Each stock item's name as singular words: the words that say what it is (its leading
    /// part: "Peppers, sweet" for "Peppers, sweet, red, raw") and all of its words.
    let names: [Set<String>]
    private let leads: [Set<String>]

    /// First segments that only name a group; the food is in the next one.
    static let groups: Set<String> = ["fish", "nut", "seed", "cheese", "cereal", "bean", "crustacean", "mollusk",
                                              "squash", "pepper", "spice", "soup", "beverage", "snack", "bread", "oil"]
    /// A name with one of these words isn't the plain ingredient ("peanut butter" isn't butter).
    private static let blockers: [String: Set<String>] = [
        "butter": ["peanut", "almond", "sesame", "cocoa", "apple", "nut", "cashew"],
        "egg": ["noodle", "roll", "bread", "eggnog", "substitute"],
        "tomato": ["paste", "sauce", "juice", "soup", "ketchup", "puree"],
        "chicken": ["broth", "soup", "liver", "stock", "nugget", "bouillon"],
        "beef": ["broth", "soup", "stock", "bouillon", "jerky"],
        "rice": ["noodle", "milk", "flour", "cake", "cracker", "vinegar", "paper"],
        "oat": ["milk", "bran", "drink"],
        "cheese": ["cottage", "cream"],
        "potato": ["sweet", "chip", "fry", "starch", "flour"],
        "bean": ["green", "sprout", "coffee"],
        "milk": ["coconut", "almond", "oat", "soy", "rice", "condensed", "evaporated", "chocolate", "powder", "dry", "butter"],
        "cream": ["ice", "sour", "cheese", "coconut"],
        "onion": ["powder", "ring", "soup"],
        "pepper": ["black", "white", "cayenne", "ground", "sauce"],
        "corn": ["starch", "syrup", "flour", "oil", "chip", "tortilla"],
        "apple": ["juice", "sauce", "pie", "cider"],
        "orange": ["juice"], "lemon": ["juice"], "lime": ["juice"],
    ]

    init(names: [String]) {
        self.names = names.map(Self.words)
        leads = names.map { name in
            let parts = name.lowercased().split(separator: ",").map(String.init)
            var lead = Self.words(parts.first ?? name)
            if parts.count > 1, lead.count == 1, !lead.isDisjoint(with: Self.groups) { lead.formUnion(Self.words(parts[1])) }
            return lead
        }
    }

    static func words(_ text: String) -> Set<String> {
        let parts = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.letters.inverted).filter { $0.count > 1 }
        return Set(parts.map(singular))
    }

    static func singular(_ word: String) -> String {
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") || word.hasSuffix("ches") || word.hasSuffix("shes") { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 3 { return String(word.dropLast()) }
        return word
    }

    func has(_ line: CookbookRecipe.Line) -> Bool {
        line.terms.contains { term in
            let want = Self.words(term)
            guard !want.isEmpty else { return false }
            let blocked = want.reduce(into: Set<String>()) { $0.formUnion(Self.blockers[$1] ?? []) }.subtracting(want)
            return names.indices.contains { i in
                want.isSubset(of: names[i]) && !want.isDisjoint(with: leads[i]) && names[i].isDisjoint(with: blocked)
            }
        }
    }

    /// What a recipe needs that isn't in the kitchen (basics and optional extras never
    /// count; an ingredient no stock name can match, like rose water, is always missing).
    func missing(in recipe: CookbookRecipe) -> [CookbookRecipe.Line] {
        recipe.keyIngredients.filter { !has($0) }
    }
}

nonisolated struct CookbookSuggestion: Identifiable, Hashable, Sendable {
    var id: String { recipe.id }
    let recipe: CookbookRecipe
    let have: Int
    let missing: [CookbookRecipe.Line]
}

nonisolated enum CookbookSuggester {
    /// Recipes the kitchen can make, or nearly: at least one key ingredient in stock,
    /// at most `maxMissing` missing and at least half of them there. Ready ones first,
    /// then the ones using most of what you have. Sauces and extras are left out.
    static func suggestions(stock: [String], recipes: [CookbookRecipe], prefs: Set<DietaryPreference>,
                            maxMissing: Int = 2) -> [CookbookSuggestion] {
        let kitchen = KitchenMatcher(names: stock)
        guard !kitchen.names.isEmpty else { return [] }
        var out: [CookbookSuggestion] = []
        for recipe in recipes where recipe.course != .sauce && recipe.fits(prefs) {
            let key = recipe.keyIngredients
            guard !key.isEmpty else { continue }
            let missing = key.filter { !kitchen.has($0) }
            let have = key.count - missing.count
            guard have >= 1, missing.count <= maxMissing, Double(have) >= Double(key.count) / 2 else { continue }
            out.append(CookbookSuggestion(recipe: recipe, have: have, missing: missing))
        }
        return out.sorted {
            if $0.missing.count != $1.missing.count { return $0.missing.count < $1.missing.count }
            if $0.have != $1.have { return $0.have > $1.have }
            return $0.recipe.title < $1.recipe.title
        }
    }

    static let basicsNote = "Kitchen basics are assumed: salt, pepper, oil, water, sugar, flour, baking powder and soda, vinegar, stock, and dried spices and herbs. Everything else must be in My Stock."

    /// The line under a recipe's ingredients. "You have everything" only when every
    /// ingredient that isn't a basic or optional is in stock.
    static func stockSummary(_ recipe: CookbookRecipe, missing: [CookbookRecipe.Line]) -> String {
        if missing.isEmpty {
            return recipe.ingredients.contains(where: \.isBasic)
                ? "You have everything for this, plus the kitchen basics." : "You have everything for this."
        }
        return "\(missing.count) missing from My Stock."
    }

    /// A shop catalogue item for a missing ingredient, to put in the cart.
    @MainActor
    static func catalogItem(for line: CookbookRecipe.Line) -> CatalogItem? {
        for term in line.terms {
            let want = KitchenMatcher.words(term)
            let hits = CatalogItem.all.filter { want.isSubset(of: KitchenMatcher.words($0.name)) }
            if let best = hits.min(by: { $0.name.count < $1.name.count }) { return best }
        }
        return nil
    }
}
