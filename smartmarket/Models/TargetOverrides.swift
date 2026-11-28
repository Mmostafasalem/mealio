import Foundation

/// Daily targets the person typed in Profile › Goals & targets. Each is
/// optional: an unset one follows the recommendation (body stats, goal and
/// pace for calories; the usual split of those calories for the macros).
/// "Use recommended" clears them all. Stored in UserDefaults on this iPhone.
struct TargetOverrides: Equatable {
    var calories: Int?
    var proteinG: Int?
    var carbsG: Int?
    var fatG: Int?

    static let caloriesKey = "targetCalories_v1"
    static let proteinKey = "targetProtein_v1"
    static let carbsKey = "targetCarbs_v1"
    static let fatKey = "targetFat_v1"

    /// What can be typed. Calories stay at or above a floor no plan should go under.
    static let calorieRange = 1000...6000
    static let macroRange = 1...600

    var isEmpty: Bool { calories == nil && proteinG == nil && carbsG == nil && fatG == nil }
    var hasMacros: Bool { proteinG != nil || carbsG != nil || fatG != nil }

    static func load(_ defaults: UserDefaults = .standard) -> TargetOverrides {
        func read(_ key: String, _ range: ClosedRange<Int>) -> Int? {
            let v = defaults.integer(forKey: key)
            return v > 0 ? min(max(v, range.lowerBound), range.upperBound) : nil
        }
        return TargetOverrides(calories: read(caloriesKey, calorieRange), proteinG: read(proteinKey, macroRange),
                               carbsG: read(carbsKey, macroRange), fatG: read(fatKey, macroRange))
    }

    func save(_ defaults: UserDefaults = .standard) {
        func write(_ value: Int?, _ key: String, _ range: ClosedRange<Int>) {
            if let value, value > 0 { defaults.set(min(max(value, range.lowerBound), range.upperBound), forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        write(calories, Self.caloriesKey, Self.calorieRange)
        write(proteinG, Self.proteinKey, Self.macroRange)
        write(carbsG, Self.carbsKey, Self.macroRange)
        write(fatG, Self.fatKey, Self.macroRange)
    }

    static func clear(_ defaults: UserDefaults = .standard) { TargetOverrides().save(defaults) }

    /// The recommended macros with any typed ones in their place.
    func applied(to recommended: BMRCalculator.MacroTargets) -> BMRCalculator.MacroTargets {
        BMRCalculator.MacroTargets(calories: recommended.calories,
                                   proteinG: proteinG ?? recommended.proteinG,
                                   carbsG: carbsG ?? recommended.carbsG,
                                   fatG: fatG ?? recommended.fatG)
    }

    /// Calories the macros add up to (4 per gram of protein and carbs, 9 of fat).
    static func kcal(protein: Int, carbs: Int, fat: Int) -> Int { protein * 4 + carbs * 4 + fat * 9 }
}
