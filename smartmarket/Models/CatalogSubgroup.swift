import Foundation

// MARK: - Subgroups inside a catalogue category
//
// Favourite foods are listed by category (Meat & Poultry, Dairy …) and, inside each,
// by a subgroup that says what the food is (Chicken, Pork, Beef …), so related foods sit
// together and can be picked all at once. A subgroup is found from words in the item's
// name, first rule that matches wins; anything else goes to "Other".

extension CatalogItem {
    /// The subgroup this item is listed under inside its category.
    var subgroup: String {
        let name = self.name.lowercased()
        for rule in CatalogSubgroups.rules[category] ?? []
        where rule.words.contains(where: { name.contains($0) }) && !rule.except.contains(where: { name.contains($0) }) {
            return rule.title
        }
        return CatalogSubgroups.fallback[category] ?? "Other"
    }
}

enum CatalogSubgroups {
    struct Rule {
        let title: String
        let words: [String]
        /// Names with one of these words don't belong here ("pineapple" isn't an apple).
        var except: [String] = []
    }

    /// The items of one category, grouped and in the order of its rules ("Other" last).
    static func groups(of items: [CatalogItem], in category: CatalogCategory) -> [(title: String, items: [CatalogItem])] {
        var order = (rules[category] ?? []).map(\.title)
        let last = fallback[category] ?? "Other"
        if !order.contains(last) { order.append(last) }
        let byGroup = Dictionary(grouping: items, by: \.subgroup)
        return order.compactMap { title in
            guard let list = byGroup[title], !list.isEmpty else { return nil }
            return (title, list)
        }
    }

    /// What an item that matches no rule is called, per category.
    static let fallback: [CatalogCategory: String] = [
        .seafood: "Fish", .bread: "Loaves", .vegetables: "Other vegetables", .fruits: "Other fruit",
        .grains: "Other grains", .legumes: "Peas and chickpeas", .canned: "Other tins and jars",
        .frozen: "Other frozen", .oils: "Oils", .condiments: "Sauces", .spices: "Spices",
        .nuts: "Nuts", .snacks: "Other snacks", .beverages: "Other drinks", .baking: "Other baking",
        .eggs: "Eggs", .dairy: "Other dairy", .meat: "Other meat",
    ]

    static let rules: [CatalogCategory: [Rule]] = [
        .meat: [
            Rule(title: "Chicken", words: ["chicken"]),
            Rule(title: "Pork", words: ["pork"]),
            Rule(title: "Beef", words: ["beef"]),
            Rule(title: "Lamb", words: ["lamb"]),
            Rule(title: "Turkey and duck", words: ["turkey", "duck"]),
            Rule(title: "Cured meat and sausages", words: ["bacon", "ham", "salami", "sausage", "hot dog"]),
        ],
        .seafood: [
            Rule(title: "Shellfish", words: ["shrimp", "prawn", "mussel", "crab"]),
            Rule(title: "Tinned and smoked", words: ["canned", "smoked", "anchov"]),
            Rule(title: "Fish", words: ["fillet", "pollock", "tilapia", "bass", "tuna", "herring", "mackerel"]),
        ],
        .dairy: [
            Rule(title: "Cheese", words: ["cheese", "ricotta", "gouda", "edam", "cheddar", "mozzarella", "feta", "parmesan", "brie", "džiugas"]),
            Rule(title: "Milk", words: ["milk"]),
            Rule(title: "Yogurt and kefir", words: ["yogurt", "kefir"]),
            Rule(title: "Cream", words: ["cream"]),
            Rule(title: "Butter and ghee", words: ["butter", "ghee"]),
        ],
        .bread: [
            Rule(title: "Flatbreads and wraps", words: ["pita", "tortilla", "flatbread"]),
            Rule(title: "Rolls and pastries", words: ["bagel", "muffin", "croissant", "roll", "crispbread"]),
            Rule(title: "Loaves", words: ["bread", "baguette", "ciabatta"]),
        ],
        .vegetables: [
            Rule(title: "Potatoes and roots", words: ["potato", "beetroot", "parsnip", "radish", "carrot"]),
            Rule(title: "Onions and garlic", words: ["onion", "leek", "garlic", "shallot"]),
            Rule(title: "Cabbage and broccoli", words: ["cabbage", "sauerkraut", "broccoli", "cauliflower", "sprout"]),
            Rule(title: "Leafy greens", words: ["spinach", "kale", "lettuce", "arugula"]),
            Rule(title: "Tomatoes, peppers and squash", words: ["tomato", "pepper", "cucumber", "zucchini", "eggplant", "pumpkin", "squash", "corn"]),
        ],
        .fruits: [
            Rule(title: "Apples and pears", words: ["apple", "pear"], except: ["pineapple"]),
            Rule(title: "Citrus", words: ["orange", "mandarin", "grapefruit", "lemon", "lime"]),
            Rule(title: "Berries and grapes", words: ["berr", "grape", "cherr"]),
            Rule(title: "Stone fruit", words: ["peach", "nectarine", "plum", "apricot"]),
            Rule(title: "Melons", words: ["melon"]),
            Rule(title: "Tropical and other", words: ["banana", "mango", "pineapple", "kiwi", "avocado", "pomegranate", "date", "fig"]),
        ],
        .grains: [
            Rule(title: "Pasta and noodles", words: ["spaghetti", "penne", "fusilli", "rigatoni", "tagliatelle", "lasagna", "orzo", "noodle"]),
            Rule(title: "Rice", words: ["rice"]),
            Rule(title: "Oats", words: ["oat"]),
        ],
        .legumes: [
            Rule(title: "Lentils", words: ["lentil"]),
            Rule(title: "Beans", words: ["bean", "edamame"]),
        ],
        .canned: [
            Rule(title: "Tomatoes", words: ["tomato"]),
            Rule(title: "Broths and coconut milk", words: ["broth", "coconut"]),
            Rule(title: "Pickles and olives", words: ["pickle", "olive", "caper", "artichoke", "pepper"]),
        ],
        .frozen: [
            Rule(title: "Fish and seafood", words: ["fish", "shrimp"]),
            Rule(title: "Fruit", words: ["berry", "mango"]),
            Rule(title: "Vegetables", words: ["pea", "corn", "spinach", "broccoli", "vegetable", "edamame", "fries"]),
            Rule(title: "Ready meals and treats", words: ["pizza", "dumpling", "ice cream"]),
        ],
        .oils: [
            Rule(title: "Fats", words: ["margarine", "lard"]),
            Rule(title: "Oils", words: ["oil"]),
        ],
        .condiments: [
            Rule(title: "Spreads and sweeteners", words: ["honey", "syrup", "butter", "tahini"]),
            Rule(title: "Mustard and vinegar", words: ["mustard", "vinegar"]),
            Rule(title: "Sauces", words: ["sauce", "ketchup", "mayonnaise", "pesto", "tamari", "sriracha"]),
        ],
        .spices: [
            Rule(title: "Salt and pepper", words: ["salt", "black pepper"]),
            Rule(title: "Dried herbs", words: ["oregano", "basil", "thyme", "rosemary", "bay", "dill"]),
            Rule(title: "Spices", words: ["paprika", "cumin", "coriander", "turmeric", "curry", "masala", "chili", "cayenne",
                                         "cinnamon", "nutmeg", "cardamom", "vanilla", "powder", "ginger"]),
        ],
        .nuts: [
            Rule(title: "Seeds", words: ["seed"]),
            Rule(title: "Nuts", words: ["nut", "almond", "pecan", "pistachio", "cashew"]),
        ],
        .snacks: [
            Rule(title: "Chips and crackers", words: ["chips", "cracker", "pretzel", "popcorn", "rice cake"]),
            Rule(title: "Sweet", words: ["chocolate", "dried fruit"]),
            Rule(title: "Bars and jerky", words: ["bar", "jerky"]),
        ],
        .beverages: [
            Rule(title: "Water", words: ["water"]),
            Rule(title: "Juices", words: ["juice"]),
            Rule(title: "Tea and coffee", words: ["tea", "coffee"]),
            Rule(title: "Alcohol", words: ["beer", "wine"]),
        ],
        .baking: [
            Rule(title: "Flour and starch", words: ["flour", "cornstarch"]),
            Rule(title: "Sugar", words: ["sugar"]),
            Rule(title: "Raising agents", words: ["baking", "yeast"]),
            Rule(title: "Chocolate and vanilla", words: ["cocoa", "chocolate", "vanilla"]),
        ],
    ]
}
