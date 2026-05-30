import Foundation

// MARK: - Food category
enum FoodCategory: String, Codable, CaseIterable, Identifiable {
    case all        = "all"
    case dairy      = "dairy"
    case meat       = "meat"
    case vegetables = "vegetables"
    case fruits     = "fruits"
    case grains     = "grains"
    case snacks     = "snacks"
    case beverages  = "beverages"
    case legumes    = "legumes"
    case seafood    = "seafood"

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var sfSymbol: String {
        switch self {
        case .all:        return "square.grid.2x2"
        case .dairy:      return "drop.fill"
        case .meat:       return "fork.knife"
        case .vegetables: return "leaf.fill"
        case .fruits:     return "apple.logo"
        case .grains:     return "square.3.layers.3d"
        case .snacks:     return "popcorn.fill"
        case .beverages:  return "cup.and.saucer.fill"
        case .legumes:    return "circle.grid.2x2.fill"
        case .seafood:    return "fish.fill"
        }
    }
}

// MARK: - Food model
struct Food: Codable, Identifiable, Hashable {
    let id: String
    let name: String              // Lithuanian name preferred, e.g. "Vištienos filė"
    let nameEn: String            // English fallback
    let category: FoodCategory
    let backendId: Int?           // matches Deal.id from /api/deals
    let caloriesPer100g: Int
    let proteinPer100g: Double    // grams
    let carbsPer100g: Double
    let fatPer100g: Double
    let servingSizeG: Int         // typical serving in grams
    let dietaryTags: [DietaryPreference]  // tags this food is safe for

    var displayName: String { nameEn }

    var macroSummary: String {
        "P: \(String(format: "%.0f", proteinPer100g))g  C: \(String(format: "%.0f", carbsPer100g))g  F: \(String(format: "%.0f", fatPer100g))g"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, category
        case nameEn          = "name_en"
        case caloriesPer100g = "calories_per_100g"
        case proteinPer100g  = "protein_per_100g"
        case carbsPer100g    = "carbs_per_100g"
        case fatPer100g      = "fat_per_100g"
        case servingSizeG    = "serving_size_g"
        case dietaryTags     = "dietary_tags"
        case backendId       = "backend_id"
    }
}

// MARK: - Mocked Lithuanian food catalog (used until API is ready)
extension Food {
    static let catalog: [Food] = [
        Food(id: "visc-file", name: "Vištienos filė", nameEn: "Chicken breast", category: .meat,
             backendId: 101,
             caloriesPer100g: 110, proteinPer100g: 23, carbsPer100g: 0, fatPer100g: 1.5, servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .halal]),
        Food(id: "kiausiniai", name: "Kiaušiniai", nameEn: "Eggs", category: .dairy,
             backendId: 102,
             caloriesPer100g: 155, proteinPer100g: 13, carbsPer100g: 1.1, fatPer100g: 11, servingSizeG: 60,
             dietaryTags: [.glutenFree, .lactoseFree, .vegetarian]),
        Food(id: "lasisa", name: "Lašiša", nameEn: "Salmon", category: .seafood,
             backendId: 103,
             caloriesPer100g: 208, proteinPer100g: 20, carbsPer100g: 0, fatPer100g: 13, servingSizeG: 120,
             dietaryTags: [.glutenFree, .lactoseFree, .halal]),
        Food(id: "kiauliena", name: "Kiaulienos kotletai", nameEn: "Pork cutlets", category: .meat,
             backendId: 104,
             caloriesPer100g: 220, proteinPer100g: 17, carbsPer100g: 0, fatPer100g: 17, servingSizeG: 150,
             dietaryTags: [.glutenFree]),
        Food(id: "tunas", name: "Tuno konservai", nameEn: "Canned tuna", category: .seafood,
             backendId: 105,
             caloriesPer100g: 116, proteinPer100g: 26, carbsPer100g: 0, fatPer100g: 0.8, servingSizeG: 100,
             dietaryTags: [.glutenFree, .lactoseFree]),
        Food(id: "varske", name: "Varškė", nameEn: "Quark / Cottage cheese", category: .dairy,
             backendId: 106,
             caloriesPer100g: 155, proteinPer100g: 15.3, carbsPer100g: 3.6, fatPer100g: 9, servingSizeG: 200,
             dietaryTags: [.glutenFree, .vegetarian]),
        Food(id: "jogurtas", name: "Natūralus jogurtas", nameEn: "Natural yogurt", category: .dairy,
             backendId: 107,
             caloriesPer100g: 61, proteinPer100g: 3.5, carbsPer100g: 4.7, fatPer100g: 3.3, servingSizeG: 150,
             dietaryTags: [.glutenFree, .vegetarian]),
        Food(id: "feta", name: "Feta sūris", nameEn: "Feta cheese", category: .dairy,
             backendId: 108,
             caloriesPer100g: 264, proteinPer100g: 14, carbsPer100g: 4.1, fatPer100g: 21, servingSizeG: 50,
             dietaryTags: [.glutenFree, .vegetarian]),
        Food(id: "avizos", name: "Avižiniai dribsniai", nameEn: "Oats", category: .grains,
             backendId: 109,
             caloriesPer100g: 389, proteinPer100g: 17, carbsPer100g: 66, fatPer100g: 7, servingSizeG: 80,
             dietaryTags: [.lactoseFree, .vegan, .vegetarian]),
        Food(id: "ryziai", name: "Ryžiai", nameEn: "Rice", category: .grains,
             backendId: 110,
             caloriesPer100g: 365, proteinPer100g: 7, carbsPer100g: 80, fatPer100g: 0.7, servingSizeG: 80,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "bananai", name: "Bananai", nameEn: "Bananas", category: .fruits,
             backendId: 111,
             caloriesPer100g: 89, proteinPer100g: 1.1, carbsPer100g: 23, fatPer100g: 0.3, servingSizeG: 120,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "duona", name: "Ruginė duona", nameEn: "Dark rye bread", category: .grains,
             backendId: 112,
             caloriesPer100g: 259, proteinPer100g: 8.5, carbsPer100g: 48, fatPer100g: 1.8, servingSizeG: 50,
             dietaryTags: [.lactoseFree, .vegan]),
        Food(id: "bulves", name: "Bulvės", nameEn: "Sweet potato", category: .vegetables,
             backendId: 113,
             caloriesPer100g: 86, proteinPer100g: 1.6, carbsPer100g: 20, fatPer100g: 0.1, servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "makaronai", name: "Makaronai", nameEn: "Pasta", category: .grains,
             backendId: 114,
             caloriesPer100g: 370, proteinPer100g: 13, carbsPer100g: 75, fatPer100g: 1.5, servingSizeG: 80,
             dietaryTags: [.lactoseFree, .vegan]),
        Food(id: "brokoliai", name: "Brokoliai", nameEn: "Broccoli", category: .vegetables,
             backendId: 115,
             caloriesPer100g: 34, proteinPer100g: 2.8, carbsPer100g: 7, fatPer100g: 0.4, servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "spinatai", name: "Špinatai", nameEn: "Spinach", category: .vegetables,
             backendId: 116,
             caloriesPer100g: 23, proteinPer100g: 2.9, carbsPer100g: 3.6, fatPer100g: 0.4, servingSizeG: 80,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "pomidorai", name: "Pomidorai", nameEn: "Tomatoes", category: .vegetables,
             backendId: 117,
             caloriesPer100g: 18, proteinPer100g: 0.9, carbsPer100g: 3.9, fatPer100g: 0.2, servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "agurkai", name: "Agurkai", nameEn: "Cucumbers", category: .vegetables,
             backendId: 118,
             caloriesPer100g: 15, proteinPer100g: 0.7, carbsPer100g: 3.6, fatPer100g: 0.1, servingSizeG: 120,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "alyvuoges", name: "Alyvuogių aliejus", nameEn: "Olive oil", category: .snacks,
             backendId: 119,
             caloriesPer100g: 884, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 100, servingSizeG: 15,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "avokadas", name: "Avokadas", nameEn: "Avocado", category: .fruits,
             backendId: 120,
             caloriesPer100g: 160, proteinPer100g: 2, carbsPer100g: 9, fatPer100g: 15, servingSizeG: 100,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "migdolai", name: "Migdolai", nameEn: "Almonds", category: .snacks,
             backendId: 121,
             caloriesPer100g: 579, proteinPer100g: 21, carbsPer100g: 22, fatPer100g: 50, servingSizeG: 30,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "sviestas", name: "Sviestas", nameEn: "Butter", category: .dairy,
             backendId: 122,
             caloriesPer100g: 717, proteinPer100g: 0.9, carbsPer100g: 0.1, fatPer100g: 81, servingSizeG: 10,
             dietaryTags: [.glutenFree, .vegetarian]),
        Food(id: "bulves-paprastos", name: "Bulvės", nameEn: "Potato", category: .vegetables,
             backendId: 123,
             caloriesPer100g: 77, proteinPer100g: 2, carbsPer100g: 17, fatPer100g: 0.1, servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "morkos", name: "Morkos", nameEn: "Carrots", category: .vegetables,
             backendId: 124,
             caloriesPer100g: 41, proteinPer100g: 0.9, carbsPer100g: 10, fatPer100g: 0.2, servingSizeG: 100,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "kefyras", name: "Kefyras", nameEn: "Kefir", category: .dairy,
             backendId: nil,
             caloriesPer100g: 52, proteinPer100g: 3.3, carbsPer100g: 4.8, fatPer100g: 2.5, servingSizeG: 250,
             dietaryTags: [.glutenFree, .vegetarian]),
        Food(id: "suris-dziugas", name: "Sūris Džiugas", nameEn: "Džiugas cheese", category: .dairy,
             backendId: nil,
             caloriesPer100g: 392, proteinPer100g: 32, carbsPer100g: 0, fatPer100g: 29, servingSizeG: 30,
             dietaryTags: [.glutenFree, .vegetarian]),
        Food(id: "krevetes", name: "Krevetės", nameEn: "Shrimp", category: .seafood,
             backendId: nil,
             caloriesPer100g: 85, proteinPer100g: 18, carbsPer100g: 0.9, fatPer100g: 0.8, servingSizeG: 100,
             dietaryTags: [.glutenFree, .lactoseFree]),
        Food(id: "grikiai", name: "Grikiai", nameEn: "Buckwheat", category: .grains,
             backendId: nil,
             caloriesPer100g: 343, proteinPer100g: 13, carbsPer100g: 71, fatPer100g: 3.4, servingSizeG: 80,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "kopustai", name: "Kopūstai", nameEn: "Cabbage", category: .vegetables,
             backendId: nil,
             caloriesPer100g: 25, proteinPer100g: 1.3, carbsPer100g: 5.8, fatPer100g: 0.1, servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "svogunu", name: "Svogūnai", nameEn: "Onions", category: .vegetables,
             backendId: nil,
             caloriesPer100g: 40, proteinPer100g: 1.1, carbsPer100g: 9.3, fatPer100g: 0.1, servingSizeG: 80,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "obuoliai", name: "Obuoliai", nameEn: "Apples", category: .fruits,
             backendId: nil,
             caloriesPer100g: 52, proteinPer100g: 0.3, carbsPer100g: 14, fatPer100g: 0.2, servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "lesiai", name: "Lęšiai", nameEn: "Lentils", category: .legumes,
             backendId: nil,
             caloriesPer100g: 352, proteinPer100g: 25, carbsPer100g: 60, fatPer100g: 1.1, servingSizeG: 80,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "pupeles", name: "Pupelės", nameEn: "Beans", category: .legumes,
             backendId: nil,
             caloriesPer100g: 127, proteinPer100g: 8.7, carbsPer100g: 22, fatPer100g: 0.5, servingSizeG: 100,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "graikiniai", name: "Graikiniai riešutai", nameEn: "Walnuts", category: .snacks,
             backendId: nil,
             caloriesPer100g: 654, proteinPer100g: 15, carbsPer100g: 14, fatPer100g: 65, servingSizeG: 30,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        Food(id: "chia", name: "Čia sėklos", nameEn: "Chia seeds", category: .snacks,
             backendId: nil,
             caloriesPer100g: 486, proteinPer100g: 17, carbsPer100g: 42, fatPer100g: 31, servingSizeG: 20,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
    ]
}
