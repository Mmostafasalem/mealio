import Foundation

// MARK: - Product (from GET /api/products — full market catalog, on sale or not)

// HONESTY CONSTRAINT: discount/discountedPrice/isOnSale are decoded for wire
// compatibility but are intentionally NOT rendered as price comparisons in the UI
// (no real price feed exists). The user only ever sees a single "est. price". Do
// not surface these as "was €X / −Y%" without re-checking the honesty constraint.
struct Product: Codable, Identifiable, Hashable {
    let id: String           // store-prefixed e.g. "rimi_12345", "maxima_67890"
    let name: String         // primary name (usually Lithuanian)
    let brand: String
    let store: String        // "Rimi" | "Maxima" | "Iki" | "Lidl" | "Norfa"
    let category: String     // "meat" | "dairy" | "vegetables" etc.
    let originalPrice: Double
    let discountedPrice: Double
    let discount: Int        // percent (0 if not on sale)
    let isOnSale: Bool
    let kcalPer100g: Int
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
    let weeklyQty: Int
    let unit: String
    let imageUrl: String?
    let latitude: Double?
    let longitude: Double?

    /// Current shelf price
    var price: Double { isOnSale ? discountedPrice : originalPrice }

    /// Slug used for favorite matching (lowercase, stable)
    var nameSlug: String { name.lowercased().trimmingCharacters(in: .whitespaces) }

    /// Whether a search term or favorite keyword matches this product
    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return name.lowercased().contains(q) || brand.lowercased().contains(q)
    }

    // Custom decoding: backend sends numeric or string ids
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id can be Int or String
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = "\(intId)"
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        name            = try c.decode(String.self,  forKey: .name)
        brand           = (try? c.decode(String.self, forKey: .brand)) ?? ""
        store           = (try? c.decode(String.self, forKey: .store)) ?? ""
        category        = (try? c.decode(String.self, forKey: .category)) ?? "other"
        originalPrice   = (try? c.decode(Double.self, forKey: .originalPrice)) ?? 0
        discountedPrice = (try? c.decode(Double.self, forKey: .discountedPrice)) ?? originalPrice
        discount        = (try? c.decode(Int.self,    forKey: .discount)) ?? 0
        isOnSale        = (try? c.decode(Bool.self,   forKey: .isOnSale)) ?? false
        kcalPer100g     = (try? c.decode(Int.self,    forKey: .kcalPer100g)) ?? 0
        proteinPer100g  = (try? c.decode(Double.self, forKey: .proteinPer100g)) ?? 0
        carbsPer100g    = (try? c.decode(Double.self, forKey: .carbsPer100g)) ?? 0
        fatPer100g      = (try? c.decode(Double.self, forKey: .fatPer100g)) ?? 0
        weeklyQty       = (try? c.decode(Int.self,    forKey: .weeklyQty)) ?? 1
        unit            = (try? c.decode(String.self, forKey: .unit)) ?? "vnt"
        imageUrl        = try? c.decode(String.self,  forKey: .imageUrl)
        latitude        = try? c.decode(Double.self,  forKey: .latitude)
        longitude       = try? c.decode(Double.self,  forKey: .longitude)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(brand, forKey: .brand)
        try c.encode(store, forKey: .store)
        try c.encode(category, forKey: .category)
        try c.encode(originalPrice, forKey: .originalPrice)
        try c.encode(discountedPrice, forKey: .discountedPrice)
        try c.encode(discount, forKey: .discount)
        try c.encode(isOnSale, forKey: .isOnSale)
        try c.encode(kcalPer100g, forKey: .kcalPer100g)
        try c.encode(proteinPer100g, forKey: .proteinPer100g)
        try c.encode(carbsPer100g, forKey: .carbsPer100g)
        try c.encode(fatPer100g, forKey: .fatPer100g)
        try c.encode(weeklyQty, forKey: .weeklyQty)
        try c.encode(unit, forKey: .unit)
        try c.encode(imageUrl, forKey: .imageUrl)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, brand, store, category
        case originalPrice   = "originalPrice"
        case discountedPrice = "discountedPrice"
        case discount, isOnSale
        case kcalPer100g     = "kcalPer100g"
        case proteinPer100g  = "proteinPer100g"
        case carbsPer100g    = "carbsPer100g"
        case fatPer100g      = "fatPer100g"
        case weeklyQty, unit, imageUrl, latitude, longitude
    }
}

// MARK: - Deal (from GET /api/deals)

struct Deal: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let brand: String
    let emoji: String
    let store: String
    let originalPrice: Double
    let discountedPrice: Double
    let discount: Int
    let category: String
    let kcalPer100g: Int
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
    let weeklyQty: Int
    let unit: String
    let expiresIn: String
    let allergens: [String]
    let latitude: Double?
    let longitude: Double?
}

// MARK: - BMR (POST /api/bmr request)

struct BMRRequest: Codable {
    let weight: Double
    let height: Double
    let age: Int
    let gender: String       // "male" | "female"
    let activityLevel: String
}

// MARK: - BMR Response

struct BMRResponse: Codable {
    let bmr: Int
    let tdee: Int
    let loseCalories: Int
    let maintainCalories: Int
    let gainCalories: Int
    let macros: MacroTargets

    struct MacroTargets: Codable {
        let protein: Int
        let carbs: Int
        let fat: Int
    }
}

// MARK: - Meal Plan (POST /api/meal-plan)

struct MealPlanRequest: Codable {
    let user: MealPlanUser
    let bmrData: BMRResponse
    let groceryList: [Deal]
    let goal: String   // "lose" | "maintain" | "gain"
    let lang: String   // "en" | "lt"
}

struct MealPlanUser: Codable {
    let name: String
    let age: Int
    let gender: String
    let weight: Double
    let height: Double
    let goal: String
    let activityLevel: String
    let dietaryOptions: [String]
    let allergies: [String]
    let favoriteFoods: [String]   // food name slugs matched by the backend
}

/// Full 7-day plan. Keys are always Lithuanian day names.
struct WeeklyMealPlan: Codable, Equatable {
    let agentMessage: String?
    let pirmadienis: DayPlan?
    let antradienis: DayPlan?
    let treciadienis: DayPlan?
    let ketvirtadienis: DayPlan?
    let pentadienis: DayPlan?
    let sestadienis: DayPlan?
    let sekmadienis: DayPlan?

    var allDays: [(label: String, plan: DayPlan)] {
        let pairs: [(String, DayPlan?)] = [
            ("Monday",    pirmadienis),
            ("Tuesday",   antradienis),
            ("Wednesday", treciadienis),
            ("Thursday",  ketvirtadienis),
            ("Friday",    pentadienis),
            ("Saturday",  sestadienis),
            ("Sunday",    sekmadienis)
        ]
        return pairs.compactMap { label, plan in plan.map { (label, $0) } }
    }
}

struct DayPlan: Codable, Equatable {
    let pusryciai: MealItem?   // breakfast
    let pietus: MealItem?      // lunch
    let vakariene: MealItem?   // dinner
    let uzkandziai: MealItem?  // snacks
    let visoKcal: Int?

    enum CodingKeys: String, CodingKey {
        case pusryciai
        case pietus = "pietūs"
        case vakariene
        case uzkandziai
        case visoKcal
    }
}

struct MealItem: Codable, Equatable {
    let pavadinimas: String    // name
    let ingredientai: [String] // ingredients
    let kcal: Int
}

// MARK: - Gap Fillers (POST /api/gap-fillers)

struct GapFillerRequest: Codable {
    let targetCalories: Int
    let macros: BMRResponse.MacroTargets
    let lang: String
}

struct GapFiller: Codable, Identifiable {
    var id: String { pavadinimas }
    let pavadinimas: String     // name
    let aprasymas: String       // description
    let kcal: Int
    let baltymai: Int           // protein
    let angliavandeniai: Int    // carbs
    let riebalai: Int           // fat
}

// MARK: - Nutritional gaps (computed locally, passed to shopping advice)

struct NutritionalGaps {
    let caloriesNeeded: Int
    let proteinNeeded: Double
    let carbsNeeded: Double
    let fatNeeded: Double
}

// MARK: - Shopping Advice (POST /api/shopping-advice)

struct ShoppingAdviceRequest: Codable {
    let groceryList: [Deal]
    let goal: String
    let macros: BMRResponse.MacroTargets
    let lang: String
}

struct ShoppingAdvice: Codable, Identifiable {
    var id: String { produktas }
    let produktas: String       // product name
    let priezastis: String      // reason
    let apytiksleCena: String   // estimated price
    let kurPirkti: String       // where to buy
    let makroNauda: String      // macro benefit
}

// MARK: - Agent Chat (POST /api/agent-chat)

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: String   // "user" or "assistant"
    let content: String

    init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
    }
}

struct AgentChatRequest: Codable {
    let message: String
    let history: [AgentChatHistoryItem]
    let userContext: AgentUserContext
}

struct AgentChatHistoryItem: Codable {
    let role: String
    let content: String
}

struct AgentUserContext: Codable {
    let goal: String
    let targetCalories: Int
    let caloriesConsumed: Int
    let favoriteFoods: [String]
}

struct AgentChatResponse: Codable {
    let reply: String
}

// MARK: - Recipe
struct RecipeRequest: Codable {
    let mealName: String
}

struct RecipeIngredient: Codable, Identifiable {
    var id: String { name }
    let name: String
    let amount: String
}

struct Recipe: Codable, Identifiable {
    var id: String { mealName }
    let mealName: String
    let prepTime: Int
    let cookTime: Int
    let servings: Int
    let ingredients: [RecipeIngredient]
    let steps: [String]
    let tip: String?
}
