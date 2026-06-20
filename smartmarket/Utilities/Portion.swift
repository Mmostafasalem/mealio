import Foundation

/// Human-friendly household portion descriptions ("≈ ½ plate", "≈ 2 tbsp",
/// "≈ 2 eggs") so users don't have to think in grams.
enum Portion {

    /// A short household equivalent for `grams` of a food in `category`.
    static func household(grams: Int, category: String) -> String {
        let g = Double(max(grams, 0))
        switch category.lowercased() {
        case "oils", "condiments", "oil", "sauce", "spices":
            return spoons(g, gramsPerSpoon: 15)            // tablespoons
        case "nuts", "seeds":
            return handfuls(g, gramsPerHandful: 30)
        case "snacks":
            return handfuls(g, gramsPerHandful: 30)
        case "eggs":
            return pieces(g, gramsPerPiece: 60, unit: "egg")
        case "fruits", "fruit":
            return pieces(g, gramsPerPiece: 120, unit: "piece")
        case "dairy":
            return g <= 60 ? spoons(g, gramsPerSpoon: 15) : cups(g, gramsPerCup: 245)
        case "beverages":
            return cups(g, gramsPerCup: 245)
        case "meat", "poultry", "fish", "seafood":
            return plate(g, fullPlate: 250)                // a protein portion
        case "grains", "pasta", "rice", "legumes":
            return plate(g, fullPlate: 200)                // a carb portion
        case "vegetables":
            return plate(g, fullPlate: 150)                // a veg portion
        default:
            return plate(g, fullPlate: 300)
        }
    }

    // MARK: - Units

    private static func plate(_ g: Double, fullPlate: Double) -> String {
        let f = g / max(fullPlate, 1)
        switch f {
        case ..<0.35: return "≈ ¼ plate"
        case ..<0.6:  return "≈ ½ plate"
        case ..<0.85: return "≈ ¾ plate"
        case ..<1.25: return "≈ 1 plate"
        case ..<1.75: return "≈ 1½ plates"
        default:      return String(format: "≈ %.0f plates", f.rounded())
        }
    }

    private static func spoons(_ g: Double, gramsPerSpoon: Double) -> String {
        let n = max(Int((g / gramsPerSpoon).rounded()), 1)
        return "≈ \(n) tbsp"
    }

    private static func handfuls(_ g: Double, gramsPerHandful: Double) -> String {
        let n = max(Int((g / gramsPerHandful).rounded()), 1)
        return "≈ \(n) handful" + (n > 1 ? "s" : "")
    }

    private static func pieces(_ g: Double, gramsPerPiece: Double, unit: String) -> String {
        let n = max(Int((g / gramsPerPiece).rounded()), 1)
        return "≈ \(n) \(unit)" + (n > 1 ? "s" : "")
    }

    private static func cups(_ g: Double, gramsPerCup: Double) -> String {
        let cups = g / gramsPerCup
        if cups < 0.6 { return "≈ ½ cup" }
        if cups < 1.25 { return "≈ 1 cup" }
        return String(format: "≈ %.1f cups", cups)
    }
}
