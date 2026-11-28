import Foundation
import CoreFoundation

// MARK: - What the package says (Open Food Facts)

/// The package size, the label's serving and its pieces, read from an Open Food Facts
/// product: `product_quantity` (+ `product_quantity_unit`), `serving_quantity`
/// (+ `serving_quantity_unit`), `serving_size` ("1 slice (21 g)") and `number_of_units`.
nonisolated enum OFFPackage {
    /// Words that measure an amount rather than name a piece ("2 tbsp" is not two pieces).
    static let measures: Set<String> = ["g", "gr", "gram", "grams", "kg", "mg", "ml", "l", "cl", "dl", "oz", "lb", "fl",
                                        "tbsp", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons", "cup", "cups",
                                        "serving", "servings", "portion", "portions", "scoop", "scoops", "pinch", "dash",
                                        "unit", "units", "twelfth", "eighth", "sixth", "quarter", "half", "third", "of"]

    static func number(_ raw: Any?) -> Double? {
        if let v = raw as? NSNumber {
            guard CFGetTypeID(v) != CFBooleanGetTypeID() else { return nil }
            return v.doubleValue
        }
        if let v = raw as? String { return Double(v.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    /// `amount` in `unit`, in the food's own unit (grams or millilitres); nil when the unit is another kind.
    static func inBasis(_ amount: Double, unit: String?, basis: NutritionFood.Basis) -> Double? {
        guard amount.isFinite, amount > 0 else { return nil }
        let u = (unit ?? (basis == .millilitres ? "ml" : "g")).lowercased().trimmingCharacters(in: .whitespaces)
        let grams: [String: Double] = ["g": 1, "gr": 1, "kg": 1000, "mg": 0.001, "oz": 28.3495, "lb": 453.592]
        let millilitres: [String: Double] = ["ml": 1, "l": 1000, "cl": 10, "dl": 100, "fl oz": 29.5735, "fl. oz": 29.5735]
        switch basis {
        case .grams: return grams[u].map { amount * $0 }
        case .millilitres: return millilitres[u].map { amount * $0 }
        case .serving: return nil
        }
    }

    /// "1 slice (21 g)" → (1, "slice", 21 g); "2 tbsp (24 g)" → (nil, nil, 24 g); "30g" → (nil, nil, 30 g).
    static func readServing(_ text: String, basis: NutritionFood.Basis) -> (count: Double?, piece: String?, amount: Double?) {
        let lower = text.lowercased()
        var amount: Double?
        // The weight in brackets, else a bare "30 g".
        let weight = #"(\d+(?:[.,]\d+)?)\s*(kg|mg|ml|cl|dl|gr|g|l|oz)\b"#
        if let regex = try? NSRegularExpression(pattern: weight),
           let match = regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)).last,
           let n = Range(match.range(at: 1), in: lower), let u = Range(match.range(at: 2), in: lower),
           let value = Double(lower[n].replacingOccurrences(of: ",", with: ".")) {
            amount = inBasis(value, unit: String(lower[u]), basis: basis)
        }
        // A leading count and word: "1 slice", "2 cookies", "1 can".
        let lead = #"^\s*(\d+(?:[.,]\d+)?)\s+([a-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: lead),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let n = Range(match.range(at: 1), in: lower), let w = Range(match.range(at: 2), in: lower),
              let count = Double(lower[n].replacingOccurrences(of: ",", with: ".")), count > 0 else { return (nil, nil, amount) }
        let word = String(lower[w])
        guard !measures.contains(word), word.count >= 3 else { return (nil, nil, amount) }
        return (count, singular(word), amount)
    }

    /// "slices" → "slice", "cookies" → "cookie", "patties" → "patty".
    static func singular(_ word: String) -> String {
        let ie: Set<String> = ["cookies", "brownies", "pies", "smoothies", "rotis", "samosas", "ties", "movies"]
        if ie.contains(word), word.hasSuffix("s") { return String(word.dropLast()) }
        return KitchenMatcher.singular(word)
    }

    /// Fills the package, serving and piece fields from the product.
    static func apply(_ product: [String: Any], to food: inout NutritionFood) {
        guard food.basis != .serving else { return }
        if let quantity = number(product["product_quantity"]) {
            food.packageAmount = inBasis(quantity, unit: product["product_quantity_unit"] as? String, basis: food.basis)
        }
        if food.packageAmount == nil, let text = product["quantity"] as? String {
            food.packageAmount = readServing(text, basis: food.basis).amount
        }
        let servingText = (product["serving_size"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let servingText, !servingText.isEmpty { food.servingLabel = servingText }
        let read = servingText.flatMap { $0.isEmpty ? nil : readServing($0, basis: food.basis) }
        if let quantity = number(product["serving_quantity"]) {
            food.servingAmount = inBasis(quantity, unit: product["serving_quantity_unit"] as? String, basis: food.basis)
        }
        if food.servingAmount == nil { food.servingAmount = read?.amount }
        if let count = read?.count, let piece = read?.piece, let serving = food.servingAmount {
            food.pieceAmount = serving / count
            food.pieceName = piece
        } else if let units = number(product["number_of_units"]), units >= 1, let package = food.packageAmount {
            food.pieceAmount = package / units
            food.pieceName = "piece"
        }
        if let package = food.packageAmount, package > 100_000 { food.packageAmount = nil }
    }

    /// Per-100 values from `nutriments`: the `_100g` fields first; kJ (`energy-kj_100g`, or
    /// `energy_100g`, which Open Food Facts always keeps in kJ) when kcal is missing; and,
    /// for labels entered per serving with no `_100g` field, the `_serving` value scaled by
    /// the serving size.
    static func per100(_ n: [String: Any], servingAmount: Double?) -> (kcal: Double, protein: Double, carbs: Double, fat: Double)? {
        func value(_ name: String) -> Double? {
            if let v = number(n[name + "_100g"]) { return v }
            if n[name + "_100g"] is NSNumber { return nil }   // a boolean: not a number
            if let serving = servingAmount, serving > 0, let v = number(n[name + "_serving"]) { return v * 100 / serving }
            return nil
        }
        let kcal = value("energy-kcal") ?? value("energy-kj").map { $0 / 4.184 } ?? value("energy").map { $0 / 4.184 }
        guard let kcal, let protein = value("proteins"), let carbs = value("carbohydrates"), let fat = value("fat") else { return nil }
        return (kcal, protein, carbs, fat)
    }

    /// The label's serving size in the food's unit, read before the food exists (for `per100`).
    static func servingAmount(_ product: [String: Any], basis: NutritionFood.Basis) -> Double? {
        if let quantity = number(product["serving_quantity"]),
           let amount = inBasis(quantity, unit: product["serving_quantity_unit"] as? String, basis: basis) { return amount }
        return (product["serving_size"] as? String).flatMap { readServing($0, basis: basis).amount }
    }
}
