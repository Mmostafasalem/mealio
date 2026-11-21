import Foundation

// MARK: - Kinds of food inside a catalogue section
//
// "Pick your foods" shows each section in smaller groups (all chicken together,
// all pork together…). A food goes to the first group with one of its words
// (whole words, plurals count); anything left over goes under "Other".

struct CatalogGroup: Identifiable {
    let name: String
    let items: [CatalogItem]
    var id: String { name }
}

extension CatalogCategory {

    /// Group name and the words that put a food in it, in matching order.
    var groupRules: [(name: String, words: [String])] {
        switch self {
        case .meat: return [("Chicken", ["chicken"]), ("Pork", ["pork", "bacon", "ham"]), ("Beef", ["beef"]),
                            ("Lamb", ["lamb"]), ("Turkey", ["turkey"]), ("Duck", ["duck"]),
                            ("Sausages and cold cuts", ["salami", "sausage", "hot"])]
        case .seafood: return [("Canned", ["canned", "anchovy", "anchovies"]), ("Smoked", ["smoked"]),
                               ("Shellfish", ["shrimp", "prawn", "mussel", "crab"]),
                               ("Fish", ["fillet", "pollock", "tilapia", "bass", "tuna", "herring", "mackerel"])]
        case .dairy: return [("Cheese", ["cheese", "ricotta", "gouda", "edam", "cheddar", "mozzarella", "feta", "parmesan", "brie", "džiugas"]),
                             ("Milk", ["milk"]), ("Yogurt and kefir", ["yogurt", "kefir"]),
                             ("Cream", ["cream"]), ("Butter", ["butter", "ghee"])]
        case .eggs: return []
        case .bread: return [("Rolls and pastries", ["roll", "bagel", "muffin", "croissant"]),
                             ("Wraps and flatbreads", ["pita", "tortilla", "flatbread"]),
                             ("Loaves", ["bread", "baguette", "ciabatta"])]
        case .vegetables: return [("Onions and garlic", ["onion", "leek", "garlic", "shallot"]),
                                  ("Root vegetables", ["potato", "carrot", "beetroot", "parsnip", "radish"]),
                                  ("Cabbage and broccoli", ["cabbage", "sauerkraut", "broccoli", "cauliflower", "sprout", "kale"]),
                                  ("Leafy greens", ["spinach", "lettuce", "arugula"]),
                                  ("Tomatoes and peppers", ["tomato", "tomatoes", "pepper"]),
                                  ("Squash and cucumber", ["zucchini", "eggplant", "pumpkin", "squash", "cucumber"])]
        case .fruits: return [("Apples and pears", ["apple", "pear"]),
                              ("Citrus", ["orange", "mandarin", "grapefruit", "lemon", "lime"]),
                              ("Berries and grapes", ["grape", "strawberry", "strawberries", "blueberry", "blueberries",
                                                      "raspberry", "raspberries", "blackberry", "blackberries"]),
                              ("Stone fruit", ["cherry", "cherries", "peach", "peaches", "nectarine", "plum", "apricot"]),
                              ("Tropical", ["banana", "mango", "pineapple", "kiwi", "avocado"]),
                              ("Melons", ["watermelon", "melon"])]
        case .grains: return [("Pasta", ["spaghetti", "penne", "fusilli", "rigatoni", "tagliatelle", "lasagna", "orzo"]),
                              ("Noodles", ["noodle"]), ("Rice", ["rice"]), ("Oats", ["oat"])]
        case .legumes: return [("Lentils", ["lentil"]), ("Chickpeas", ["chickpea"]), ("Beans", ["bean"]),
                               ("Peas and soy", ["pea", "edamame", "soybean"])]
        case .canned: return [("Tomatoes", ["tomato", "tomatoes"]), ("Broths", ["broth"])]
        case .frozen: return [("Vegetables", ["pea", "corn", "spinach", "broccoli", "vegetable", "edamame"]),
                              ("Fruit", ["berry", "mango"]), ("Fish", ["fish", "shrimp"]),
                              ("Ready to cook", ["pizza", "fries", "dumpling"])]
        case .oils: return [("Oils", ["oil"]), ("Margarine and lard", ["margarine", "lard"])]
        case .condiments: return [("Vinegar", ["vinegar"]),
                                  ("Spreads and sweeteners", ["honey", "syrup", "butter", "tahini"]),
                                  ("Sauces", ["sauce", "ketchup", "mustard", "mayonnaise", "tamari", "sriracha", "pesto"])]
        case .spices: return [("Herbs", ["oregano", "basil", "thyme", "rosemary", "bay", "dill"]),
                              ("Pepper and chili", ["pepper", "paprika", "chili"])]
        case .nuts: return [("Seeds", ["seed", "flaxseed"]), ("Nuts", ["almond", "walnut", "cashew", "peanut", "hazelnut", "pecan", "pistachio", "nut"])]
        case .snacks: return [("Chocolate", ["chocolate"]), ("Bars", ["bar"]),
                              ("Chips and crackers", ["chip", "cracker", "pretzel", "popcorn", "cake"])]
        case .beverages: return [("Water", ["water"]), ("Juice", ["juice"]), ("Tea", ["tea"]), ("Coffee", ["coffee"]),
                                 ("Beer and wine", ["beer", "wine"])]
        case .baking: return [("Flour", ["flour"]), ("Sugar", ["sugar"])]
        }
    }

    /// The section's foods in groups, in the rules' order, "Other" last. A section
    /// with no rules (Eggs) is one group named after the section.
    func groups(of items: [CatalogItem]) -> [CatalogGroup] {
        let rules = groupRules
        var buckets = Array(repeating: [CatalogItem](), count: rules.count)
        var other: [CatalogItem] = []
        for item in items {
            let words = Set(item.name.lowercased().split { !$0.isLetter }.map(String.init))
            if let i = rules.firstIndex(where: { rule in
                rule.words.contains { w in words.contains(w) || words.contains(w + "s") || words.contains(w + "es") }
            }) {
                buckets[i].append(item)
            } else {
                other.append(item)
            }
        }
        var out = zip(rules, buckets).filter { !$0.1.isEmpty }.map { CatalogGroup(name: $0.0.name, items: $0.1) }
        if !other.isEmpty { out.append(CatalogGroup(name: out.isEmpty ? displayName : "Other", items: other)) }
        return out
    }
}
