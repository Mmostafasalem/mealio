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

// MARK: - Legacy preference IDs with USDA-sourced nutrition (not the logger database)
extension Food {
    private static let referenceFoods = Dictionary(uniqueKeysWithValues: ((try? NutritionDatabase.load()) ?? []).map { ($0.sourceID, $0) })

    private static func reference(id: String, name: String, nameEn: String, category: FoodCategory,
                                  backendId: Int?, fdcID: String, servingSizeG: Int,
                                  dietaryTags: [DietaryPreference]) -> Food? {
        guard let record = referenceFoods[fdcID] else { return nil }
        return Food(id: id, name: name, nameEn: nameEn, category: category, backendId: backendId,
                    caloriesPer100g: Int(record.kcal.rounded()), proteinPer100g: record.protein,
                    carbsPer100g: record.carbs, fatPer100g: record.fat, servingSizeG: servingSizeG,
                    dietaryTags: dietaryTags)
    }

    static let catalog: [Food] = [
        reference(id: "visc-file", name: "Vištienos filė", nameEn: "Chicken breast", category: .meat,
             backendId: 101,
             fdcID: "171077", servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .halal]),
        reference(id: "kiausiniai", name: "Kiaušiniai", nameEn: "Eggs", category: .dairy,
             backendId: 102,
             fdcID: "171287", servingSizeG: 60,
             dietaryTags: [.glutenFree, .lactoseFree, .vegetarian]),
        reference(id: "lasisa", name: "Lašiša", nameEn: "Salmon", category: .seafood,
             backendId: 103,
             fdcID: "175167", servingSizeG: 120,
             dietaryTags: [.glutenFree, .lactoseFree, .halal]),
        reference(id: "kiauliena", name: "Kiaulienos kotletai", nameEn: "Pork cutlets", category: .meat,
             backendId: 104,
             fdcID: "168381", servingSizeG: 150,
             dietaryTags: [.glutenFree]),
        reference(id: "tunas", name: "Tuno konservai", nameEn: "Canned tuna", category: .seafood,
             backendId: 105,
             fdcID: "173709", servingSizeG: 100,
             dietaryTags: [.glutenFree, .lactoseFree]),
        reference(id: "varske", name: "Varškė", nameEn: "Quark / Cottage cheese", category: .dairy,
             backendId: 106,
             fdcID: "172179", servingSizeG: 200,
             dietaryTags: [.glutenFree, .vegetarian]),
        reference(id: "jogurtas", name: "Natūralus jogurtas", nameEn: "Natural yogurt", category: .dairy,
             backendId: 107,
             fdcID: "171284", servingSizeG: 150,
             dietaryTags: [.glutenFree, .vegetarian]),
        reference(id: "feta", name: "Feta sūris", nameEn: "Feta cheese", category: .dairy,
             backendId: 108,
             fdcID: "173420", servingSizeG: 50,
             dietaryTags: [.glutenFree, .vegetarian]),
        reference(id: "avizos", name: "Avižiniai dribsniai", nameEn: "Oats", category: .grains,
             backendId: 109,
             fdcID: "169705", servingSizeG: 80,
             dietaryTags: [.lactoseFree, .vegan, .vegetarian]),
        reference(id: "ryziai", name: "Ryžiai", nameEn: "Rice", category: .grains,
             backendId: 110,
             fdcID: "168877", servingSizeG: 80,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "bananai", name: "Bananai", nameEn: "Bananas", category: .fruits,
             backendId: 111,
             fdcID: "173944", servingSizeG: 120,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "duona", name: "Ruginė duona", nameEn: "Dark rye bread", category: .grains,
             backendId: 112,
             fdcID: "172684", servingSizeG: 50,
             dietaryTags: [.lactoseFree, .vegan]),
        reference(id: "bulves", name: "Bulvės", nameEn: "Sweet potato", category: .vegetables,
             backendId: 113,
             fdcID: "168482", servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "makaronai", name: "Makaronai", nameEn: "Pasta", category: .grains,
             backendId: 114,
             fdcID: "169736", servingSizeG: 80,
             dietaryTags: [.lactoseFree, .vegan]),
        reference(id: "brokoliai", name: "Brokoliai", nameEn: "Broccoli", category: .vegetables,
             backendId: 115,
             fdcID: "170379", servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "spinatai", name: "Špinatai", nameEn: "Spinach", category: .vegetables,
             backendId: 116,
             fdcID: "168462", servingSizeG: 80,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "pomidorai", name: "Pomidorai", nameEn: "Tomatoes", category: .vegetables,
             backendId: 117,
             fdcID: "170457", servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "agurkai", name: "Agurkai", nameEn: "Cucumbers", category: .vegetables,
             backendId: 118,
             fdcID: "168409", servingSizeG: 120,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "alyvuoges", name: "Alyvuogių aliejus", nameEn: "Olive oil", category: .snacks,
             backendId: 119,
             fdcID: "171413", servingSizeG: 15,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "avokadas", name: "Avokadas", nameEn: "Avocado", category: .fruits,
             backendId: 120,
             fdcID: "171705", servingSizeG: 100,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "migdolai", name: "Migdolai", nameEn: "Almonds", category: .snacks,
             backendId: 121,
             fdcID: "170567", servingSizeG: 30,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "sviestas", name: "Sviestas", nameEn: "Butter", category: .dairy,
             backendId: 122,
             fdcID: "173430", servingSizeG: 10,
             dietaryTags: [.glutenFree, .vegetarian]),
        reference(id: "bulves-paprastos", name: "Bulvės", nameEn: "Potato", category: .vegetables,
             backendId: 123,
             fdcID: "170026", servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "morkos", name: "Morkos", nameEn: "Carrots", category: .vegetables,
             backendId: 124,
             fdcID: "170393", servingSizeG: 100,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "kefyras", name: "Kefyras", nameEn: "Kefir (lowfat, plain reference)", category: .dairy,
             backendId: nil,
             fdcID: "170904", servingSizeG: 250,
             dietaryTags: [.glutenFree, .vegetarian]),
        reference(id: "suris-dziugas", name: "Sūris Džiugas", nameEn: "Hard cheese (Parmesan reference)", category: .dairy,
             backendId: nil,
             fdcID: "170848", servingSizeG: 30,
             dietaryTags: [.glutenFree, .vegetarian]),
        reference(id: "krevetes", name: "Krevetės", nameEn: "Shrimp", category: .seafood,
             backendId: nil,
             fdcID: "175179", servingSizeG: 100,
             dietaryTags: [.glutenFree, .lactoseFree]),
        reference(id: "grikiai", name: "Grikiai", nameEn: "Buckwheat", category: .grains,
             backendId: nil,
             fdcID: "170286", servingSizeG: 80,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "kopustai", name: "Kopūstai", nameEn: "Cabbage", category: .vegetables,
             backendId: nil,
             fdcID: "169975", servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "svogunu", name: "Svogūnai", nameEn: "Onions", category: .vegetables,
             backendId: nil,
             fdcID: "170000", servingSizeG: 80,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "obuoliai", name: "Obuoliai", nameEn: "Apples", category: .fruits,
             backendId: nil,
             fdcID: "171688", servingSizeG: 150,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "lesiai", name: "Lęšiai", nameEn: "Lentils", category: .legumes,
             backendId: nil,
             fdcID: "172420", servingSizeG: 80,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "pupeles", name: "Pupelės", nameEn: "Beans", category: .legumes,
             backendId: nil,
             fdcID: "173740", servingSizeG: 100,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "graikiniai", name: "Graikiniai riešutai", nameEn: "Walnuts", category: .snacks,
             backendId: nil,
             fdcID: "170187", servingSizeG: 30,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
        reference(id: "chia", name: "Čia sėklos", nameEn: "Chia seeds", category: .snacks,
             backendId: nil,
             fdcID: "170554", servingSizeG: 20,
             dietaryTags: [.glutenFree, .lactoseFree, .vegan]),
    ].compactMap { $0 }
}
