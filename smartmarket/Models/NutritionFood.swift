import Foundation
import CoreFoundation

/// A source record, not an AI estimate. Nutrients always describe 100 of `basis`.
struct NutritionFood: Codable, Hashable, Identifiable {
    enum Basis: String, Codable { case grams = "g", millilitres = "ml", serving = "serving" }
    enum Source: String, Codable { case usda, openFoodFacts, recipe, menu }
    let id: String
    let name: String
    let brand: String?
    let basis: Basis
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let source: Source
    let sourceID: String
    let sourceDate: String?
    var dataset: String? = nil
    var searchNames: [String]? = nil
    var recipeDetails: NutritionRecipe? = nil
    var menuURL: String? = nil
    var reportedRetailers: [String]? = nil

    var referenceAmount: Double { basis == .serving ? 1 : 100 }
    var defaultAmount: Double { referenceAmount }
    var minimumAmount: Double { basis == .serving ? 0.25 : 1 }
    var maximumAmount: Double { basis == .serving ? 20 : 5000 }
    var referenceLabel: String { basis == .serving ? "Per serving" : "Per 100 \(basis.rawValue)" }

    var sourceName: String {
        switch source {
        case .usda:
            switch dataset {
            case "foundation": return "USDA Foundation · October 2026 download"
            case "survey": return "USDA FNDDS · 2021–2023 reference"
            default: return "USDA SR Legacy · April 2018"
            }
        case .openFoodFacts: return "Open Food Facts · product data"
        case .recipe: return "Your recipe · calculated estimate"
        case .menu: return "Menu nutrition · entered by you"
        }
    }
    var sourceExplanation: String {
        switch source {
        case .usda: return "Choose the preparation that matches what you ate. These are dated reference averages, including restaurant-style foods, not verified nutrition for every current restaurant menu."
        case .openFoodFacts: return "Community-contributed product data, as sold. Check the brand and current package label; preparation can change the values."
        case .recipe: return "Calculated from the ingredient records and final cooked weight you entered. This is a recipe estimate; include oils, sauces and all edible ingredients."
        case .menu: return "Nutrition entered by you per restaurant serving. Nourlo has not verified the menu or portion; check current published figures and adjust for what you ate."
        }
    }
    var sourceURL: URL? {
        switch source {
        case .usda: return URL(string: "https://fdc.nal.usda.gov/food-details/\(sourceID)/nutrients")
        case .openFoodFacts: return URL(string: "https://world.openfoodfacts.org/product/\(sourceID)")
        case .recipe: return nil
        case .menu: return menuURL.flatMap(URL.init(string:))
        }
    }
    var subtitle: String { [brand, referenceLabel].compactMap { $0 }.joined(separator: " · ") }
    var isValid: Bool {
        let identifierValid: Bool
        if source == .recipe || source == .menu { identifierValid = UUID(uuidString: sourceID) != nil }
        else { identifierValid = !sourceID.isEmpty && sourceID.allSatisfy { $0.isASCII && $0.isNumber } }
        let energyLimit: Double = basis == .serving ? 10000 : 1000
        let macroLimit: Double = basis == .serving ? 1000 : 100
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && identifierValid &&
            [kcal, protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 } &&
            kcal <= energyLimit && [protein, carbs, fat].allSatisfy { $0 <= macroLimit }
    }
    struct Portion {
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }
    func portion(_ amount: Double) -> Portion {
        let factor = amount / referenceAmount
        return Portion(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }

    static func openFoodFacts(_ product: [String: Any], language: String = "en") -> NutritionFood? {
        guard let code = product["code"] as? String,
              [8, 12, 13, 14].contains(code.count),
              code.allSatisfy({ $0.isASCII && $0.isNumber }),
              let n = product["nutriments"] as? [String: Any] else { return nil }
        func number(_ key: String) -> Double? {
            if let v = n[key] as? NSNumber {
                guard CFGetTypeID(v) != CFBooleanGetTypeID() else { return nil }
                return v.doubleValue
            }
            if let v = n[key] as? String { return Double(v) }
            return nil
        }
        let energy = number("energy-kcal_100g") ?? number("energy-kj_100g").map { $0 / 4.184 }
            ?? ((n["energy_unit"] as? String)?.lowercased() == "kj" ? number("energy_100g").map { $0 / 4.184 } : nil)
        guard let kcal = energy, let protein = number("proteins_100g"),
              let carbs = number("carbohydrates_100g"), let fat = number("fat_100g") else { return nil }
        let name = ["product_name_" + language, "product_name", "product_name_en", "generic_name"].compactMap { product[$0] as? String }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        func unit(_ raw: Any?) -> Basis? {
            guard let text = (raw as? String)?.lowercased() else { return nil }
            if ["g", "kg", "mg", "oz", "lb"].contains(text) { return .grams }
            if ["ml", "l", "cl", "dl", "fl oz", "fl. oz"].contains(text) { return .millilitres }
            return nil
        }
        let quantity = (product["quantity"] as? String) ?? ""
        let quantityUnit = quantity.range(of: #"(?i)(?<=\d)\s*(kg|mg|ml|cl|dl|g|l|oz|lb)\s*$"#, options: .regularExpression)
            .map { String(quantity[$0]).trimmingCharacters(in: .whitespaces) }
        let packageBasis = unit(product["product_quantity_unit"]) ?? unit(quantityUnit)
        let servingBasis = unit(product["serving_quantity_unit"])
        if let packageBasis, let servingBasis, packageBasis != servingBasis { return nil }
        let explicitVolume = (product["nutrition_data_per"] as? String)?.lowercased() == "100ml"
        let establishedBasis = packageBasis ?? servingBasis
        if explicitVolume, establishedBasis == .grams { return nil }
        // OFF's historical "100g" field also covers 100ml. Never infer density from that default.
        guard let basis = establishedBasis ?? (explicitVolume ? .millilitres : nil) else { return nil }
        let brand = (product["brands"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var food = NutritionFood(id: "off:\(code)", name: name, brand: brand,
                                 basis: basis,
                                 kcal: kcal, protein: protein, carbs: carbs, fat: fat,
                                 source: .openFoodFacts, sourceID: code, sourceDate: String(ISO8601DateFormatter().string(from: Date()).prefix(10)))
        food.searchNames = ["product_name", "product_name_en", "product_name_ar", "product_name_lt", "generic_name"]
            .compactMap { product[$0] as? String }.filter { !$0.isEmpty }
        food.reportedRetailers = product["stores_tags"] as? [String]
        return food.isValid ? food : nil
    }
}

enum NutritionDatabase {
    private struct Catalog: Decodable { let foods: [NutritionFood] }
    static func load(bundle: Bundle = .main) throws -> [NutritionFood] {
        guard let url = bundle.url(forResource: "NutritionCatalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        return catalog.foods.filter(\.isValid)
    }
    static func search(_ query: String, in foods: [NutritionFood], limit: Int = 60) -> [NutritionFood] {
        NutritionSearchIndex(foods: foods).search(query, limit: limit)
    }
}
