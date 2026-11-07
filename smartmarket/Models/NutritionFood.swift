import Foundation
import CoreFoundation

/// A source record, not an AI estimate. Nutrients always describe 100 of `basis`.
struct NutritionFood: Codable, Hashable, Identifiable {
    enum Basis: String, Codable { case grams = "g", millilitres = "ml" }
    enum Source: String, Codable { case usda, openFoodFacts }
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

    var sourceName: String { source == .usda ? "USDA SR Legacy · April 2018" : "Open Food Facts · product data" }
    var sourceURL: URL {
        source == .usda
            ? URL(string: "https://fdc.nal.usda.gov/food-details/\(sourceID)/nutrients")!
            : URL(string: "https://world.openfoodfacts.org/product/\(sourceID)")!
    }
    var subtitle: String { [brand, "Per 100 \(basis.rawValue)"].compactMap { $0 }.joined(separator: " · ") }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !sourceID.isEmpty && sourceID.allSatisfy { $0.isASCII && $0.isNumber } &&
        [kcal, protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 } &&
        kcal <= 1000 && [protein, carbs, fat].allSatisfy { $0 <= 100 }
    }
    struct Portion {
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }
    func portion(_ amount: Double) -> Portion {
        let factor = amount / 100
        return Portion(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }

    static func openFoodFacts(_ product: [String: Any]) -> NutritionFood? {
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
        let name = ["product_name_en", "product_name", "generic_name"].compactMap { product[$0] as? String }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        func unit(_ raw: Any?) -> Basis? {
            guard let text = (raw as? String)?.lowercased() else { return nil }
            if ["g", "kg", "mg", "oz", "lb"].contains(text) { return .grams }
            if ["ml", "l", "cl", "dl", "fl oz", "fl. oz"].contains(text) { return .millilitres }
            return nil
        }
        let packageBasis = unit(product["product_quantity_unit"])
        let servingBasis = unit(product["serving_quantity_unit"])
        if let packageBasis, let servingBasis, packageBasis != servingBasis { return nil }
        let explicitVolume = (product["nutrition_data_per"] as? String)?.lowercased() == "100ml"
        let establishedBasis = packageBasis ?? servingBasis
        if explicitVolume, establishedBasis == .grams { return nil }
        // OFF's historical "100g" field also covers 100ml. Never infer density from that default.
        guard let basis = establishedBasis ?? (explicitVolume ? .millilitres : nil) else { return nil }
        let brand = (product["brands"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let food = NutritionFood(id: "off:\(code)", name: name, brand: brand,
                                 basis: basis,
                                 kcal: kcal, protein: protein, carbs: carbs, fat: fat,
                                 source: .openFoodFacts, sourceID: code, sourceDate: String(ISO8601DateFormatter().string(from: Date()).prefix(10)))
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
        let words = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        return foods.filter { food in
            let haystack = (food.name + " " + (food.brand ?? "")).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return words.allSatisfy(haystack.contains)
        }.sorted { a, b in
            // Put short, plain descriptions before composite foods without dropping preparation state.
            if a.name.count != b.name.count { return a.name.count < b.name.count }
            return a.id < b.id
        }.prefix(limit).map { $0 }
    }
}
