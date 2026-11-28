import Foundation

// MARK: - Typing a portion and its calories
//
// Wherever a food is reviewed before it's logged (the voice review card, Add Food's
// serving detail), the amount can be typed instead of stepped to, and the calorie
// estimate can be replaced by the person's own figure. Their figure is theirs: the
// protein, carbs and fat are scaled by the same factor, and the entry is marked
// (`FoodLogEntry.ownCalories`).

enum PortionInput {
    /// The calories a person can type for one food.
    static let kcalRange: ClosedRange<Int> = 0...10_000

    /// Typed amounts land on the same steps as the − and + buttons: whole grams or
    /// millilitres, quarters of a serving.
    static func step(for basis: NutritionFood.Basis) -> Double { basis == .serving ? 0.25 : 1 }

    /// A typed amount in the food's own unit ("150", "72,5", "1.5"), kept within the
    /// food's bounds; nil when there's no number in the text.
    static func amount(_ text: String, for food: NutritionFood) -> Double? {
        guard let value = TypedNumber.parse(text), value.isFinite else { return nil }
        return TypedNumber.fitted(value, range: food.minimumAmount...food.maximumAmount, step: step(for: food.basis))
    }

    /// A typed calorie figure, as a whole number within `kcalRange`; nil when there's no number.
    static func kcal(_ text: String) -> Int? {
        guard let value = TypedNumber.parse(text), value.isFinite else { return nil }
        return min(max(Int(value.rounded()), kcalRange.lowerBound), kcalRange.upperBound)
    }

    /// The portion, with the person's own calories when they typed them: protein,
    /// carbs and fat scale with the calories (a food with no calories keeps its macros).
    static func portion(of food: NutritionFood, amount: Double, kcal: Int?) -> NutritionFood.Portion {
        let estimate = food.portion(amount)
        guard let kcal else { return estimate }
        let factor = estimate.kcal > 0 ? Double(kcal) / estimate.kcal : 1
        return NutritionFood.Portion(kcal: Double(kcal), protein: estimate.protein * factor,
                                     carbs: estimate.carbs * factor, fat: estimate.fat * factor)
    }

    /// Keeps the person's calorie figure in step with a new amount: the same calories
    /// per gram (or serving) they gave, so doubling the portion doubles their figure.
    static func rescaled(_ kcal: Int?, from old: Double, to new: Double) -> Int? {
        guard let kcal, old > 0 else { return kcal }
        return min(max(Int((Double(kcal) * new / old).rounded()), kcalRange.lowerBound), kcalRange.upperBound)
    }
}
