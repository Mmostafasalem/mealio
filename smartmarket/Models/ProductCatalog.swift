import SwiftUI

// MARK: - Category

enum CatalogCategory: String, CaseIterable, Identifiable {
    case meat       = "meat"
    case seafood    = "seafood"
    case dairy      = "dairy"
    case eggs       = "eggs"
    case bread      = "bread"
    case vegetables = "vegetables"
    case fruits     = "fruits"
    case grains     = "grains"
    case legumes    = "legumes"
    case canned     = "canned"
    case frozen     = "frozen"
    case oils       = "oils"
    case condiments = "condiments"
    case spices     = "spices"
    case nuts       = "nuts"
    case snacks     = "snacks"
    case beverages  = "beverages"
    case baking     = "baking"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .meat:       return "Meat & Poultry"
        case .seafood:    return "Fish & Seafood"
        case .dairy:      return "Dairy"
        case .eggs:       return "Eggs"
        case .bread:      return "Bread & Bakery"
        case .vegetables: return "Vegetables"
        case .fruits:     return "Fruits"
        case .grains:     return "Grains & Pasta"
        case .legumes:    return "Legumes"
        case .canned:     return "Canned & Preserved"
        case .frozen:     return "Frozen"
        case .oils:       return "Oils & Fats"
        case .condiments: return "Condiments & Sauces"
        case .spices:     return "Spices & Herbs"
        case .nuts:       return "Nuts & Seeds"
        case .snacks:     return "Snacks"
        case .beverages:  return "Beverages"
        case .baking:     return "Baking"
        }
    }

    var symbol: String {
        switch self {
        case .meat:       return "fork.knife"
        case .seafood:    return "fish.fill"
        case .dairy:      return "drop.fill"
        case .eggs:       return "oval.fill"
        case .bread:      return "birthday.cake.fill"
        case .vegetables: return "leaf.fill"
        case .fruits:     return "apple.logo"
        case .grains:     return "square.3.layers.3d"
        case .legumes:    return "circle.grid.2x2.fill"
        case .canned:     return "archivebox.fill"
        case .frozen:     return "snowflake"
        case .oils:       return "drop.triangle.fill"
        case .condiments: return "waterbottle.fill"
        case .spices:     return "star.fill"
        case .nuts:       return "oval.portrait.fill"
        case .snacks:     return "popcorn.fill"
        case .beverages:  return "cup.and.saucer.fill"
        case .baking:     return "chart.pie.fill"
        }
    }

    var color: Color {
        switch self {
        case .meat:       return Color(hex: "#DC2626")
        case .seafood:    return Color(hex: "#0EA5E9")
        case .dairy:      return Color(hex: "#7C3AED")
        case .eggs:       return Color(hex: "#D97706")
        case .bread:      return Color(hex: "#B45309")
        case .vegetables: return Color(hex: "#16A34A")
        case .fruits:     return Color(hex: "#E11D48")
        case .grains:     return Color(hex: "#CA8A04")
        case .legumes:    return Color(hex: "#15803D")
        case .canned:     return Color(hex: "#6B7280")
        case .frozen:     return Color(hex: "#2563EB")
        case .oils:       return Color(hex: "#84CC16")
        case .condiments: return Color(hex: "#EA580C")
        case .spices:     return Color(hex: "#9333EA")
        case .nuts:       return Color(hex: "#92400E")
        case .snacks:     return Color(hex: "#EC4899")
        case .beverages:  return Color(hex: "#0891B2")
        case .baking:     return Color(hex: "#C2410C")
        }
    }
}

// MARK: - Catalog item

struct CatalogItem: Identifiable, Hashable {
    let id: String
    let name: String
    let category: CatalogCategory
}

// MARK: - Full catalog

extension CatalogItem {

    static let all: [CatalogItem] = meat + seafood + dairy + eggs + bread
        + vegetables + fruits + grains + legumes + canned
        + frozen + oils + condiments + spices + nuts
        + snacks + beverages + baking

    // MARK: Meat & Poultry (24 items)
    static let meat: [CatalogItem] = [
        CatalogItem(id: "chicken-breast",      name: "Chicken Breast",       category: .meat),
        CatalogItem(id: "chicken-thighs",      name: "Chicken Thighs",       category: .meat),
        CatalogItem(id: "chicken-wings",       name: "Chicken Wings",        category: .meat),
        CatalogItem(id: "whole-chicken",       name: "Whole Chicken",        category: .meat),
        CatalogItem(id: "ground-chicken",      name: "Ground Chicken",       category: .meat),
        CatalogItem(id: "pork-tenderloin",     name: "Pork Tenderloin",      category: .meat),
        CatalogItem(id: "pork-belly",          name: "Pork Belly",           category: .meat),
        CatalogItem(id: "pork-ribs",           name: "Pork Ribs",            category: .meat),
        CatalogItem(id: "pork-chops",          name: "Pork Chops",           category: .meat),
        CatalogItem(id: "ground-pork",         name: "Ground Pork",          category: .meat),
        CatalogItem(id: "beef-steak",          name: "Beef Steak",           category: .meat),
        CatalogItem(id: "ground-beef",         name: "Ground Beef",          category: .meat),
        CatalogItem(id: "beef-ribs",           name: "Beef Ribs",            category: .meat),
        CatalogItem(id: "lamb-chops",          name: "Lamb Chops",           category: .meat),
        CatalogItem(id: "ground-lamb",         name: "Ground Lamb",          category: .meat),
        CatalogItem(id: "turkey-breast",       name: "Turkey Breast",        category: .meat),
        CatalogItem(id: "ground-turkey",       name: "Ground Turkey",        category: .meat),
        CatalogItem(id: "duck-breast",         name: "Duck Breast",          category: .meat),
        CatalogItem(id: "bacon",               name: "Bacon",                category: .meat),
        CatalogItem(id: "ham",                 name: "Ham",                  category: .meat),
        CatalogItem(id: "salami",              name: "Salami",               category: .meat),
        CatalogItem(id: "sausages",            name: "Sausages",             category: .meat),
        CatalogItem(id: "hot-dogs",            name: "Hot Dogs",             category: .meat),
        CatalogItem(id: "chicken-liver",       name: "Chicken Liver",        category: .meat),
    ]

    // MARK: Fish & Seafood (20 items)
    static let seafood: [CatalogItem] = [
        CatalogItem(id: "salmon-fillet",       name: "Salmon Fillet",        category: .seafood),
        CatalogItem(id: "trout-fillet",        name: "Trout Fillet",         category: .seafood),
        CatalogItem(id: "cod-fillet",          name: "Cod Fillet",           category: .seafood),
        CatalogItem(id: "hake-fillet",         name: "Hake Fillet",          category: .seafood),
        CatalogItem(id: "pollock",             name: "Pollock",              category: .seafood),
        CatalogItem(id: "tilapia",             name: "Tilapia",              category: .seafood),
        CatalogItem(id: "sea-bass",            name: "Sea Bass",             category: .seafood),
        CatalogItem(id: "tuna-steak",          name: "Tuna Steak",           category: .seafood),
        CatalogItem(id: "herring",             name: "Herring",              category: .seafood),
        CatalogItem(id: "mackerel",            name: "Mackerel",             category: .seafood),
        CatalogItem(id: "canned-tuna",         name: "Canned Tuna",          category: .seafood),
        CatalogItem(id: "canned-sardines",     name: "Canned Sardines",      category: .seafood),
        CatalogItem(id: "canned-herring",      name: "Canned Herring",       category: .seafood),
        CatalogItem(id: "shrimp",              name: "Shrimp",               category: .seafood),
        CatalogItem(id: "prawns",              name: "Prawns",               category: .seafood),
        CatalogItem(id: "mussels",             name: "Mussels",              category: .seafood),
        CatalogItem(id: "crab-sticks",         name: "Crab Sticks",          category: .seafood),
        CatalogItem(id: "smoked-salmon",       name: "Smoked Salmon",        category: .seafood),
        CatalogItem(id: "smoked-mackerel",     name: "Smoked Mackerel",      category: .seafood),
        CatalogItem(id: "anchovies",           name: "Anchovies",            category: .seafood),
    ]

    // MARK: Dairy (24 items)
    static let dairy: [CatalogItem] = [
        CatalogItem(id: "milk-25",             name: "Milk 2.5%",            category: .dairy),
        CatalogItem(id: "milk-35",             name: "Milk 3.5%",            category: .dairy),
        CatalogItem(id: "skimmed-milk",        name: "Skimmed Milk",         category: .dairy),
        CatalogItem(id: "oat-milk",            name: "Oat Milk",             category: .dairy),
        CatalogItem(id: "almond-milk",         name: "Almond Milk",          category: .dairy),
        CatalogItem(id: "kefir",               name: "Kefir",                category: .dairy),
        CatalogItem(id: "greek-yogurt",        name: "Greek Yogurt",         category: .dairy),
        CatalogItem(id: "plain-yogurt",        name: "Plain Yogurt",         category: .dairy),
        CatalogItem(id: "sour-cream-15",       name: "Sour Cream 15%",       category: .dairy),
        CatalogItem(id: "sour-cream-30",       name: "Sour Cream 30%",       category: .dairy),
        CatalogItem(id: "heavy-cream",         name: "Heavy Cream",          category: .dairy),
        CatalogItem(id: "cottage-cheese",      name: "Cottage Cheese",       category: .dairy),
        CatalogItem(id: "ricotta",             name: "Ricotta",              category: .dairy),
        CatalogItem(id: "cream-cheese",        name: "Cream Cheese",         category: .dairy),
        CatalogItem(id: "butter",              name: "Butter",               category: .dairy),
        CatalogItem(id: "ghee",                name: "Ghee",                 category: .dairy),
        CatalogItem(id: "gouda",               name: "Gouda",                category: .dairy),
        CatalogItem(id: "edam",                name: "Edam",                 category: .dairy),
        CatalogItem(id: "cheddar",             name: "Cheddar",              category: .dairy),
        CatalogItem(id: "mozzarella",          name: "Mozzarella",           category: .dairy),
        CatalogItem(id: "feta",                name: "Feta",                 category: .dairy),
        CatalogItem(id: "parmesan",            name: "Parmesan",             category: .dairy),
        CatalogItem(id: "brie",                name: "Brie",                 category: .dairy),
        CatalogItem(id: "dziugas",             name: "Džiugas",              category: .dairy),
    ]

    // MARK: Eggs (4 items)
    static let eggs: [CatalogItem] = [
        CatalogItem(id: "eggs-6",              name: "Eggs 6-pack",          category: .eggs),
        CatalogItem(id: "eggs-10",             name: "Eggs 10-pack",         category: .eggs),
        CatalogItem(id: "eggs-12",             name: "Eggs 12-pack",         category: .eggs),
        CatalogItem(id: "free-range-eggs",     name: "Free-range Eggs",      category: .eggs),
    ]

    // MARK: Bread & Bakery (14 items)
    static let bread: [CatalogItem] = [
        CatalogItem(id: "whole-grain-bread",   name: "Whole Grain Bread",    category: .bread),
        CatalogItem(id: "rye-bread",           name: "Rye Bread",            category: .bread),
        CatalogItem(id: "white-bread",         name: "White Bread",          category: .bread),
        CatalogItem(id: "sourdough-bread",     name: "Sourdough Bread",      category: .bread),
        CatalogItem(id: "baguette",            name: "Baguette",             category: .bread),
        CatalogItem(id: "ciabatta",            name: "Ciabatta",             category: .bread),
        CatalogItem(id: "pita-bread",          name: "Pita Bread",           category: .bread),
        CatalogItem(id: "tortillas",           name: "Tortillas",            category: .bread),
        CatalogItem(id: "bagels",              name: "Bagels",               category: .bread),
        CatalogItem(id: "crispbread",          name: "Crispbread",           category: .bread),
        CatalogItem(id: "english-muffins",     name: "English Muffins",      category: .bread),
        CatalogItem(id: "croissants",          name: "Croissants",           category: .bread),
        CatalogItem(id: "flatbread",           name: "Flatbread",            category: .bread),
        CatalogItem(id: "bread-rolls",         name: "Bread Rolls",          category: .bread),
    ]

    // MARK: Vegetables (36 items)
    static let vegetables: [CatalogItem] = [
        CatalogItem(id: "potato",              name: "Potato",               category: .vegetables),
        CatalogItem(id: "sweet-potato",        name: "Sweet Potato",         category: .vegetables),
        CatalogItem(id: "onion",               name: "Onion",                category: .vegetables),
        CatalogItem(id: "red-onion",           name: "Red Onion",            category: .vegetables),
        CatalogItem(id: "spring-onion",        name: "Spring Onion",         category: .vegetables),
        CatalogItem(id: "leek",                name: "Leek",                 category: .vegetables),
        CatalogItem(id: "garlic",              name: "Garlic",               category: .vegetables),
        CatalogItem(id: "shallots",            name: "Shallots",             category: .vegetables),
        CatalogItem(id: "carrot",              name: "Carrot",               category: .vegetables),
        CatalogItem(id: "beet",                name: "Beetroot",             category: .vegetables),
        CatalogItem(id: "parsnip",             name: "Parsnip",              category: .vegetables),
        CatalogItem(id: "radish",              name: "Radish",               category: .vegetables),
        CatalogItem(id: "cabbage",             name: "Cabbage",              category: .vegetables),
        CatalogItem(id: "red-cabbage",         name: "Red Cabbage",          category: .vegetables),
        CatalogItem(id: "sauerkraut",          name: "Sauerkraut",           category: .vegetables),
        CatalogItem(id: "broccoli",            name: "Broccoli",             category: .vegetables),
        CatalogItem(id: "cauliflower",         name: "Cauliflower",          category: .vegetables),
        CatalogItem(id: "brussels-sprouts",    name: "Brussels Sprouts",     category: .vegetables),
        CatalogItem(id: "spinach",             name: "Spinach",              category: .vegetables),
        CatalogItem(id: "kale",                name: "Kale",                 category: .vegetables),
        CatalogItem(id: "lettuce",             name: "Lettuce",              category: .vegetables),
        CatalogItem(id: "arugula",             name: "Arugula",              category: .vegetables),
        CatalogItem(id: "cucumber",            name: "Cucumber",             category: .vegetables),
        CatalogItem(id: "tomato",              name: "Tomato",               category: .vegetables),
        CatalogItem(id: "cherry-tomatoes",     name: "Cherry Tomatoes",      category: .vegetables),
        CatalogItem(id: "bell-pepper",         name: "Bell Pepper",          category: .vegetables),
        CatalogItem(id: "chili-pepper",        name: "Chili Pepper",         category: .vegetables),
        CatalogItem(id: "zucchini",            name: "Zucchini",             category: .vegetables),
        CatalogItem(id: "eggplant",            name: "Eggplant",             category: .vegetables),
        CatalogItem(id: "asparagus",           name: "Asparagus",            category: .vegetables),
        CatalogItem(id: "celery",              name: "Celery",               category: .vegetables),
        CatalogItem(id: "corn",                name: "Corn",                 category: .vegetables),
        CatalogItem(id: "mushrooms",           name: "Mushrooms",            category: .vegetables),
        CatalogItem(id: "green-beans",         name: "Green Beans",          category: .vegetables),
        CatalogItem(id: "pumpkin",             name: "Pumpkin",              category: .vegetables),
        CatalogItem(id: "butternut-squash",    name: "Butternut Squash",     category: .vegetables),
    ]

    // MARK: Fruits (28 items)
    static let fruits: [CatalogItem] = [
        CatalogItem(id: "apple",               name: "Apple",                category: .fruits),
        CatalogItem(id: "pear",                name: "Pear",                 category: .fruits),
        CatalogItem(id: "banana",              name: "Banana",               category: .fruits),
        CatalogItem(id: "orange",              name: "Orange",               category: .fruits),
        CatalogItem(id: "mandarin",            name: "Mandarin",             category: .fruits),
        CatalogItem(id: "grapefruit",          name: "Grapefruit",           category: .fruits),
        CatalogItem(id: "lemon",               name: "Lemon",                category: .fruits),
        CatalogItem(id: "lime",                name: "Lime",                 category: .fruits),
        CatalogItem(id: "grapes-green",        name: "Green Grapes",         category: .fruits),
        CatalogItem(id: "grapes-red",          name: "Red Grapes",           category: .fruits),
        CatalogItem(id: "strawberries",        name: "Strawberries",         category: .fruits),
        CatalogItem(id: "blueberries",         name: "Blueberries",          category: .fruits),
        CatalogItem(id: "raspberries",         name: "Raspberries",          category: .fruits),
        CatalogItem(id: "blackberries",        name: "Blackberries",         category: .fruits),
        CatalogItem(id: "cherries",            name: "Cherries",             category: .fruits),
        CatalogItem(id: "peach",               name: "Peach",                category: .fruits),
        CatalogItem(id: "nectarine",           name: "Nectarine",            category: .fruits),
        CatalogItem(id: "plum",                name: "Plum",                 category: .fruits),
        CatalogItem(id: "apricot",             name: "Apricot",              category: .fruits),
        CatalogItem(id: "mango",               name: "Mango",                category: .fruits),
        CatalogItem(id: "pineapple",           name: "Pineapple",            category: .fruits),
        CatalogItem(id: "kiwi",                name: "Kiwi",                 category: .fruits),
        CatalogItem(id: "avocado",             name: "Avocado",              category: .fruits),
        CatalogItem(id: "watermelon",          name: "Watermelon",           category: .fruits),
        CatalogItem(id: "melon",               name: "Melon",                category: .fruits),
        CatalogItem(id: "pomegranate",         name: "Pomegranate",          category: .fruits),
        CatalogItem(id: "dates",               name: "Dates",                category: .fruits),
        CatalogItem(id: "figs",                name: "Figs",                 category: .fruits),
    ]

    // MARK: Grains & Pasta (24 items)
    static let grains: [CatalogItem] = [
        CatalogItem(id: "white-rice",          name: "White Rice",           category: .grains),
        CatalogItem(id: "brown-rice",          name: "Brown Rice",           category: .grains),
        CatalogItem(id: "basmati-rice",        name: "Basmati Rice",         category: .grains),
        CatalogItem(id: "arborio-rice",        name: "Arborio Rice",         category: .grains),
        CatalogItem(id: "oats",                name: "Oats",                 category: .grains),
        CatalogItem(id: "instant-oats",        name: "Instant Oats",         category: .grains),
        CatalogItem(id: "buckwheat",           name: "Buckwheat",            category: .grains),
        CatalogItem(id: "millet",              name: "Millet",               category: .grains),
        CatalogItem(id: "barley",              name: "Barley",               category: .grains),
        CatalogItem(id: "bulgur",              name: "Bulgur",               category: .grains),
        CatalogItem(id: "couscous",            name: "Couscous",             category: .grains),
        CatalogItem(id: "quinoa",              name: "Quinoa",               category: .grains),
        CatalogItem(id: "polenta",             name: "Polenta",              category: .grains),
        CatalogItem(id: "spaghetti",           name: "Spaghetti",            category: .grains),
        CatalogItem(id: "penne",               name: "Penne",                category: .grains),
        CatalogItem(id: "fusilli",             name: "Fusilli",              category: .grains),
        CatalogItem(id: "rigatoni",            name: "Rigatoni",             category: .grains),
        CatalogItem(id: "tagliatelle",         name: "Tagliatelle",          category: .grains),
        CatalogItem(id: "lasagna-sheets",      name: "Lasagna Sheets",       category: .grains),
        CatalogItem(id: "orzo",                name: "Orzo",                 category: .grains),
        CatalogItem(id: "egg-noodles",         name: "Egg Noodles",          category: .grains),
        CatalogItem(id: "rice-noodles",        name: "Rice Noodles",         category: .grains),
        CatalogItem(id: "soba-noodles",        name: "Soba Noodles",         category: .grains),
        CatalogItem(id: "bread-crumbs",        name: "Bread Crumbs",         category: .grains),
    ]

    // MARK: Legumes (14 items)
    static let legumes: [CatalogItem] = [
        CatalogItem(id: "red-lentils",         name: "Red Lentils",          category: .legumes),
        CatalogItem(id: "green-lentils",       name: "Green Lentils",        category: .legumes),
        CatalogItem(id: "black-lentils",       name: "Black Lentils",        category: .legumes),
        CatalogItem(id: "chickpeas-dried",     name: "Chickpeas (Dried)",    category: .legumes),
        CatalogItem(id: "chickpeas-canned",    name: "Chickpeas (Canned)",   category: .legumes),
        CatalogItem(id: "black-beans",         name: "Black Beans",          category: .legumes),
        CatalogItem(id: "white-beans",         name: "White Beans",          category: .legumes),
        CatalogItem(id: "red-kidney-beans",    name: "Red Kidney Beans",     category: .legumes),
        CatalogItem(id: "cannellini-beans",    name: "Cannellini Beans",     category: .legumes),
        CatalogItem(id: "pinto-beans",         name: "Pinto Beans",          category: .legumes),
        CatalogItem(id: "green-peas-frozen",   name: "Green Peas (Frozen)",  category: .legumes),
        CatalogItem(id: "green-peas-canned",   name: "Green Peas (Canned)",  category: .legumes),
        CatalogItem(id: "edamame",             name: "Edamame",              category: .legumes),
        CatalogItem(id: "soybeans",            name: "Soybeans",             category: .legumes),
    ]

    // MARK: Canned & Preserved (18 items)
    static let canned: [CatalogItem] = [
        CatalogItem(id: "canned-tomatoes",     name: "Canned Tomatoes",      category: .canned),
        CatalogItem(id: "tomato-paste",        name: "Tomato Paste",         category: .canned),
        CatalogItem(id: "tomato-sauce",        name: "Tomato Sauce",         category: .canned),
        CatalogItem(id: "canned-corn",         name: "Canned Corn",          category: .canned),
        CatalogItem(id: "canned-mushrooms",    name: "Canned Mushrooms",     category: .canned),
        CatalogItem(id: "canned-salmon",       name: "Canned Salmon",        category: .canned),
        CatalogItem(id: "coconut-milk",        name: "Coconut Milk",         category: .canned),
        CatalogItem(id: "vegetable-broth",     name: "Vegetable Broth",      category: .canned),
        CatalogItem(id: "chicken-broth",       name: "Chicken Broth",        category: .canned),
        CatalogItem(id: "beef-broth",          name: "Beef Broth",           category: .canned),
        CatalogItem(id: "pickles",             name: "Pickles",              category: .canned),
        CatalogItem(id: "olives",              name: "Olives",               category: .canned),
        CatalogItem(id: "artichoke-hearts",    name: "Artichoke Hearts",     category: .canned),
        CatalogItem(id: "sun-dried-tomatoes",  name: "Sun-dried Tomatoes",   category: .canned),
        CatalogItem(id: "capers",              name: "Capers",               category: .canned),
        CatalogItem(id: "roasted-peppers",     name: "Roasted Peppers",      category: .canned),
        CatalogItem(id: "bamboo-shoots",       name: "Bamboo Shoots",        category: .canned),
        CatalogItem(id: "water-chestnuts",     name: "Water Chestnuts",      category: .canned),
    ]

    // MARK: Frozen (14 items)
    static let frozen: [CatalogItem] = [
        CatalogItem(id: "frozen-peas",         name: "Frozen Peas",          category: .frozen),
        CatalogItem(id: "frozen-corn",         name: "Frozen Corn",          category: .frozen),
        CatalogItem(id: "frozen-spinach",      name: "Frozen Spinach",       category: .frozen),
        CatalogItem(id: "frozen-broccoli",     name: "Frozen Broccoli",      category: .frozen),
        CatalogItem(id: "frozen-veg-mix",      name: "Frozen Vegetable Mix", category: .frozen),
        CatalogItem(id: "frozen-berries",      name: "Frozen Berry Mix",     category: .frozen),
        CatalogItem(id: "frozen-mango",        name: "Frozen Mango",         category: .frozen),
        CatalogItem(id: "frozen-fish-fillets", name: "Frozen Fish Fillets",  category: .frozen),
        CatalogItem(id: "frozen-shrimp",       name: "Frozen Shrimp",        category: .frozen),
        CatalogItem(id: "frozen-pizza",        name: "Frozen Pizza",         category: .frozen),
        CatalogItem(id: "frozen-fries",        name: "Frozen Fries",         category: .frozen),
        CatalogItem(id: "frozen-dumplings",    name: "Frozen Dumplings",     category: .frozen),
        CatalogItem(id: "frozen-edamame",      name: "Frozen Edamame",       category: .frozen),
        CatalogItem(id: "ice-cream",           name: "Ice Cream",            category: .frozen),
    ]

    // MARK: Oils & Fats (10 items)
    static let oils: [CatalogItem] = [
        CatalogItem(id: "extra-virgin-olive",  name: "Extra Virgin Olive Oil",category: .oils),
        CatalogItem(id: "olive-oil",           name: "Olive Oil",            category: .oils),
        CatalogItem(id: "sunflower-oil",       name: "Sunflower Oil",        category: .oils),
        CatalogItem(id: "rapeseed-oil",        name: "Rapeseed Oil",         category: .oils),
        CatalogItem(id: "coconut-oil",         name: "Coconut Oil",          category: .oils),
        CatalogItem(id: "avocado-oil",         name: "Avocado Oil",          category: .oils),
        CatalogItem(id: "sesame-oil",          name: "Sesame Oil",           category: .oils),
        CatalogItem(id: "truffle-oil",         name: "Truffle Oil",          category: .oils),
        CatalogItem(id: "margarine",           name: "Margarine",            category: .oils),
        CatalogItem(id: "lard",                name: "Lard",                 category: .oils),
    ]

    // MARK: Condiments & Sauces (22 items)
    static let condiments: [CatalogItem] = [
        CatalogItem(id: "ketchup",             name: "Ketchup",              category: .condiments),
        CatalogItem(id: "yellow-mustard",      name: "Yellow Mustard",       category: .condiments),
        CatalogItem(id: "dijon-mustard",       name: "Dijon Mustard",        category: .condiments),
        CatalogItem(id: "mayonnaise",          name: "Mayonnaise",           category: .condiments),
        CatalogItem(id: "balsamic-vinegar",    name: "Balsamic Vinegar",     category: .condiments),
        CatalogItem(id: "apple-cider-vinegar", name: "Apple Cider Vinegar",  category: .condiments),
        CatalogItem(id: "white-wine-vinegar",  name: "White Wine Vinegar",   category: .condiments),
        CatalogItem(id: "soy-sauce",           name: "Soy Sauce",            category: .condiments),
        CatalogItem(id: "tamari",              name: "Tamari",               category: .condiments),
        CatalogItem(id: "oyster-sauce",        name: "Oyster Sauce",         category: .condiments),
        CatalogItem(id: "fish-sauce",          name: "Fish Sauce",           category: .condiments),
        CatalogItem(id: "worcestershire",      name: "Worcestershire Sauce", category: .condiments),
        CatalogItem(id: "hot-sauce",           name: "Hot Sauce",            category: .condiments),
        CatalogItem(id: "sriracha",            name: "Sriracha",             category: .condiments),
        CatalogItem(id: "hoisin-sauce",        name: "Hoisin Sauce",         category: .condiments),
        CatalogItem(id: "bbq-sauce",           name: "BBQ Sauce",            category: .condiments),
        CatalogItem(id: "pesto",               name: "Pesto",                category: .condiments),
        CatalogItem(id: "tahini",              name: "Tahini",               category: .condiments),
        CatalogItem(id: "honey",               name: "Honey",                category: .condiments),
        CatalogItem(id: "maple-syrup",         name: "Maple Syrup",          category: .condiments),
        CatalogItem(id: "peanut-butter",       name: "Peanut Butter",        category: .condiments),
        CatalogItem(id: "almond-butter",       name: "Almond Butter",        category: .condiments),
    ]

    // MARK: Spices & Herbs (24 items)
    static let spices: [CatalogItem] = [
        CatalogItem(id: "salt",                name: "Salt",                 category: .spices),
        CatalogItem(id: "black-pepper",        name: "Black Pepper",         category: .spices),
        CatalogItem(id: "cayenne-pepper",      name: "Cayenne Pepper",       category: .spices),
        CatalogItem(id: "paprika",             name: "Paprika",              category: .spices),
        CatalogItem(id: "smoked-paprika",      name: "Smoked Paprika",       category: .spices),
        CatalogItem(id: "cumin",               name: "Cumin",                category: .spices),
        CatalogItem(id: "coriander",           name: "Ground Coriander",     category: .spices),
        CatalogItem(id: "turmeric",            name: "Turmeric",             category: .spices),
        CatalogItem(id: "curry-powder",        name: "Curry Powder",         category: .spices),
        CatalogItem(id: "garam-masala",        name: "Garam Masala",         category: .spices),
        CatalogItem(id: "chili-flakes",        name: "Chili Flakes",         category: .spices),
        CatalogItem(id: "oregano",             name: "Oregano",              category: .spices),
        CatalogItem(id: "basil",               name: "Basil",                category: .spices),
        CatalogItem(id: "thyme",               name: "Thyme",                category: .spices),
        CatalogItem(id: "rosemary",            name: "Rosemary",             category: .spices),
        CatalogItem(id: "bay-leaves",          name: "Bay Leaves",           category: .spices),
        CatalogItem(id: "dill",                name: "Dill",                 category: .spices),
        CatalogItem(id: "cinnamon",            name: "Cinnamon",             category: .spices),
        CatalogItem(id: "nutmeg",              name: "Nutmeg",               category: .spices),
        CatalogItem(id: "cardamom",            name: "Cardamom",             category: .spices),
        CatalogItem(id: "vanilla",             name: "Vanilla Extract",      category: .spices),
        CatalogItem(id: "garlic-powder",       name: "Garlic Powder",        category: .spices),
        CatalogItem(id: "onion-powder",        name: "Onion Powder",         category: .spices),
        CatalogItem(id: "dried-ginger",        name: "Dried Ginger",         category: .spices),
    ]

    // MARK: Nuts & Seeds (14 items)
    static let nuts: [CatalogItem] = [
        CatalogItem(id: "almonds",             name: "Almonds",              category: .nuts),
        CatalogItem(id: "walnuts",             name: "Walnuts",              category: .nuts),
        CatalogItem(id: "cashews",             name: "Cashews",              category: .nuts),
        CatalogItem(id: "peanuts",             name: "Peanuts",              category: .nuts),
        CatalogItem(id: "hazelnuts",           name: "Hazelnuts",            category: .nuts),
        CatalogItem(id: "pecans",              name: "Pecans",               category: .nuts),
        CatalogItem(id: "pistachios",          name: "Pistachios",           category: .nuts),
        CatalogItem(id: "pine-nuts",           name: "Pine Nuts",            category: .nuts),
        CatalogItem(id: "sunflower-seeds",     name: "Sunflower Seeds",      category: .nuts),
        CatalogItem(id: "pumpkin-seeds",       name: "Pumpkin Seeds",        category: .nuts),
        CatalogItem(id: "sesame-seeds",        name: "Sesame Seeds",         category: .nuts),
        CatalogItem(id: "chia-seeds",          name: "Chia Seeds",           category: .nuts),
        CatalogItem(id: "flaxseeds",           name: "Flaxseeds",            category: .nuts),
        CatalogItem(id: "mixed-nuts",          name: "Mixed Nuts",           category: .nuts),
    ]

    // MARK: Snacks (12 items)
    static let snacks: [CatalogItem] = [
        CatalogItem(id: "potato-chips",        name: "Potato Chips",         category: .snacks),
        CatalogItem(id: "tortilla-chips",      name: "Tortilla Chips",       category: .snacks),
        CatalogItem(id: "rice-cakes",          name: "Rice Cakes",           category: .snacks),
        CatalogItem(id: "crackers",            name: "Crackers",             category: .snacks),
        CatalogItem(id: "pretzels",            name: "Pretzels",             category: .snacks),
        CatalogItem(id: "popcorn",             name: "Popcorn",              category: .snacks),
        CatalogItem(id: "dark-chocolate",      name: "Dark Chocolate",       category: .snacks),
        CatalogItem(id: "milk-chocolate",      name: "Milk Chocolate",       category: .snacks),
        CatalogItem(id: "granola-bars",        name: "Granola Bars",         category: .snacks),
        CatalogItem(id: "protein-bars",        name: "Protein Bars",         category: .snacks),
        CatalogItem(id: "dried-fruit",         name: "Dried Fruit",          category: .snacks),
        CatalogItem(id: "beef-jerky",          name: "Beef Jerky",           category: .snacks),
    ]

    // MARK: Beverages (20 items)
    static let beverages: [CatalogItem] = [
        CatalogItem(id: "still-water",         name: "Still Water",          category: .beverages),
        CatalogItem(id: "sparkling-water",     name: "Sparkling Water",      category: .beverages),
        CatalogItem(id: "orange-juice",        name: "Orange Juice",         category: .beverages),
        CatalogItem(id: "apple-juice",         name: "Apple Juice",          category: .beverages),
        CatalogItem(id: "grapefruit-juice",    name: "Grapefruit Juice",     category: .beverages),
        CatalogItem(id: "tomato-juice",        name: "Tomato Juice",         category: .beverages),
        CatalogItem(id: "green-tea",           name: "Green Tea",            category: .beverages),
        CatalogItem(id: "black-tea",           name: "Black Tea",            category: .beverages),
        CatalogItem(id: "herbal-tea",          name: "Herbal Tea",           category: .beverages),
        CatalogItem(id: "coffee-beans",        name: "Coffee Beans",         category: .beverages),
        CatalogItem(id: "ground-coffee",       name: "Ground Coffee",        category: .beverages),
        CatalogItem(id: "instant-coffee",      name: "Instant Coffee",       category: .beverages),
        CatalogItem(id: "beer",                name: "Beer",                 category: .beverages),
        CatalogItem(id: "red-wine",            name: "Red Wine",             category: .beverages),
        CatalogItem(id: "white-wine",          name: "White Wine",           category: .beverages),
        CatalogItem(id: "sparkling-wine",      name: "Sparkling Wine",       category: .beverages),
        CatalogItem(id: "kombucha",            name: "Kombucha",             category: .beverages),
        CatalogItem(id: "energy-drink",        name: "Energy Drink",         category: .beverages),
        CatalogItem(id: "coconut-water",       name: "Coconut Water",        category: .beverages),
        CatalogItem(id: "protein-shake",       name: "Protein Shake",        category: .beverages),
    ]

    // MARK: Baking (14 items)
    static let baking: [CatalogItem] = [
        CatalogItem(id: "all-purpose-flour",   name: "All-purpose Flour",    category: .baking),
        CatalogItem(id: "whole-wheat-flour",   name: "Whole Wheat Flour",    category: .baking),
        CatalogItem(id: "bread-flour",         name: "Bread Flour",          category: .baking),
        CatalogItem(id: "almond-flour",        name: "Almond Flour",         category: .baking),
        CatalogItem(id: "baking-powder",       name: "Baking Powder",        category: .baking),
        CatalogItem(id: "baking-soda",         name: "Baking Soda",          category: .baking),
        CatalogItem(id: "yeast",               name: "Yeast",                category: .baking),
        CatalogItem(id: "cocoa-powder",        name: "Cocoa Powder",         category: .baking),
        CatalogItem(id: "dark-chocolate-chips",name: "Dark Chocolate Chips", category: .baking),
        CatalogItem(id: "white-sugar",         name: "White Sugar",          category: .baking),
        CatalogItem(id: "brown-sugar",         name: "Brown Sugar",          category: .baking),
        CatalogItem(id: "powdered-sugar",      name: "Powdered Sugar",       category: .baking),
        CatalogItem(id: "cornstarch",          name: "Cornstarch",           category: .baking),
        CatalogItem(id: "vanilla-pod",         name: "Vanilla Pod",          category: .baking),
    ]
}
