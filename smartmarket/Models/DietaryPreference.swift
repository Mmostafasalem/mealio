import Foundation

enum DietaryPreference: String, Codable, CaseIterable, Identifiable {
    case glutenFree      = "gluten_free"
    case lactoseFree     = "lactose_free"
    case vegan           = "vegan"
    case vegetarian      = "vegetarian"
    case keto            = "keto"
    case paleo           = "paleo"
    case nutAllergy      = "nut_allergy"
    case shellfishAllergy = "shellfish_allergy"
    case halal           = "halal"
    case noPork          = "no_pork"

    var id: String { rawValue }

    var isAllergy: Bool {
        switch self {
        case .nutAllergy, .shellfishAllergy: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .glutenFree:       return "Gluten Free"
        case .lactoseFree:      return "Lactose Free"
        case .vegan:            return "Vegan"
        case .vegetarian:       return "Vegetarian"
        case .keto:             return "Keto"
        case .paleo:            return "Paleo"
        case .nutAllergy:       return "Nut Allergy"
        case .shellfishAllergy: return "Shellfish Allergy"
        case .halal:            return "Halal"
        case .noPork:           return "No Pork"
        }
    }

    var sfSymbol: String {
        switch self {
        case .glutenFree:       return "xmark.circle"
        case .lactoseFree:      return "drop.fill"
        case .vegan:            return "leaf.fill"
        case .vegetarian:       return "leaf"
        case .keto:             return "bolt.fill"
        case .paleo:            return "fossil.shell.fill"
        case .nutAllergy:       return "exclamationmark.triangle.fill"
        case .shellfishAllergy: return "exclamationmark.triangle"
        case .halal:            return "moon.fill"
        case .noPork:           return "nosign"
        }
    }
}

// MARK: - Persistence
extension Set where Element == DietaryPreference {
    static func load() -> Set<DietaryPreference> {
        guard let raw = UserDefaults.standard.stringArray(forKey: Constants.Storage.selectedDietaryFilters) else {
            return []
        }
        return Set(raw.compactMap { DietaryPreference(rawValue: $0) })
    }

    func save() {
        let raw = map(\.rawValue)
        UserDefaults.standard.set(raw, forKey: Constants.Storage.selectedDietaryFilters)
    }
}

// MARK: - Conflict check (offline meal suggestions)
extension DietaryPreference {
    /// Conservative keyword match over a food's name, category and allergen
    /// tags. False positives are acceptable; a missed conflict is not, so
    /// anything ambiguous (e.g. a "snacks" category for nut allergy) counts.
    func conflicts(name: String, category: String = "", allergens: [String] = []) -> Bool {
        let text = ([name, category] + allergens).joined(separator: " ").lowercased()
        let cat = category.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        typealias K = DietaryPreference.Keywords
        switch self {
        case .nutAllergy:
            return has(K.nuts) || ["nuts", "snacks", "bakery"].contains(cat)
        case .shellfishAllergy:
            return has(K.shellfish) || cat == "seafood"
        case .glutenFree:
            if has(["gluten-free", "gluten free"]) { return false }
            return has(K.gluten) || ["bread", "bakery", "pasta", "baking"].contains(cat)
                || (cat == "grains" && !has(K.glutenFreeGrains))
        case .lactoseFree:
            if has(["lactose-free", "lactose free"]) { return false }
            return has(K.dairy) || cat == "dairy"
        case .vegetarian:
            return has(K.meat + K.pork + K.fish + K.shellfish + ["gelatin"])
                || ["meat", "poultry", "fish", "seafood"].contains(cat)
        case .vegan:
            return DietaryPreference.vegetarian.conflicts(name: name, category: category, allergens: allergens)
                || has(K.dairy + K.eggs + ["honey"]) || ["dairy", "eggs", "bakery"].contains(cat)
        case .keto:
            return has(K.highCarb + K.gluten)
                || ["grains", "pasta", "bread", "bakery", "rice", "legumes", "baking"].contains(cat)
                || (["fruit", "fruits"].contains(cat) && !has(K.ketoFruit))
        case .paleo:
            return has(K.gluten + K.glutenFreeGrains + K.legumes + K.dairy)
                || ["grains", "pasta", "bread", "bakery", "rice", "legumes", "dairy", "baking"].contains(cat)
        case .halal:
            // Pork and alcohol are never halal; other meat is only safe when labelled.
            if has(K.pork + K.alcohol + ["gelatin"]) { return true }
            return (has(K.meat) || ["meat", "poultry"].contains(cat)) && !text.contains("halal")
        case .noPork:
            return has(K.pork + ["gelatin"])
        }
    }

    private enum Keywords {
        static let nuts = ["nut", "almond", "peanut", "cashew", "pistachio", "pecan", "hazelnut",
                           "macadamia", "praline", "marzipan", "pesto", "muesli", "granola", "nutella"]
        static let shellfish = ["shrimp", "prawn", "crab", "lobster", "mussel", "oyster", "clam",
                                "scallop", "squid", "octopus", "calamari", "shellfish", "crayfish", "seafood"]
        static let pork = ["pork", "bacon", "ham", "salami", "prosciutto", "pancetta", "chorizo",
                           "sausage", "lard", "kiaul", "pepperoni"]
        static let meat = ["chicken", "turkey", "beef", "lamb", "duck", "veal", "steak", "burger",
                           "meat", "mince", "kebab", "goose", "venison", "jerky"]
        static let fish = ["fish", "salmon", "tuna", "cod", "hake", "pollock", "tilapia", "bass",
                           "trout", "mackerel", "herring", "sardine", "anchov", "caesar"]
        static let dairy = ["milk", "yogurt", "yoghurt", "cheese", "cottage", "feta", "mozzarella",
                            "cheddar", "parmesan", "butter", "cream", "kefir", "whey", "curd",
                            "caesar", "pancake", "latte"]
        static let eggs = ["egg", "omelette", "omelet", "mayonnaise", "pancake", "caesar"]
        static let gluten = ["gluten", "bread", "toast", "pasta", "spaghetti", "penne", "fusilli", "noodle",
                             "wheat", "rye", "barley", "couscous", "oat", "muesli", "granola", "wrap",
                             "pancake", "bun", "burger", "flour", "bulgur", "seitan", "cracker",
                             "biscuit", "cereal", "croissant", "pizza", "spelt", "semolina"]
        static let glutenFreeGrains = ["rice", "buckwheat", "quinoa", "corn", "millet", "amaranth", "potato"]
        static let legumes = ["lentil", "bean", "chickpea", "pea", "soy", "tofu", "tempeh",
                              "edamame", "hummus", "peanut"]
        static let highCarb = ["rice", "potato", "banana", "apple", "pear", "orange", "grape",
                               "mango", "quinoa", "buckwheat", "corn", "lentil", "bean", "chickpea",
                               "hummus", "honey", "sugar", "juice", "jam", "oat", "muesli"]
        static let ketoFruit = ["berr", "strawberr", "raspberr", "blackberr", "avocado", "lemon", "olive"]
        static let alcohol = ["wine", "beer", "rum", "vodka", "liqueur", "brandy", "whisky"]
    }
}

extension Set where Element == DietaryPreference {
    /// True when no selected diet or allergy conflicts with the food.
    func allows(name: String, category: String = "", allergens: [String] = []) -> Bool {
        !contains { $0.conflicts(name: name, category: category, allergens: allergens) }
    }
}
