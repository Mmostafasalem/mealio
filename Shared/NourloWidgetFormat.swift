import Foundation

// MARK: - Text the widgets, controls and Live Activity show
//
// Kept here (compiled into the app too) so the wording is unit-tested and the
// same everywhere. Plain, short, sentence case.

nonisolated enum NourloWidgetFormat {

    /// Calories over the goal (0 while under it).
    static func caloriesOver(_ s: NourloSnapshot) -> Int { max(s.caloriesEaten - s.calorieGoal, 0) }

    /// The big number: kcal left, or kcal over once past the goal.
    static func headlineNumber(_ s: NourloSnapshot) -> Int {
        caloriesOver(s) > 0 ? caloriesOver(s) : s.caloriesLeft
    }

    /// The caption under the big number.
    static func headlineCaption(_ s: NourloSnapshot) -> String {
        caloriesOver(s) > 0 ? "kcal over" : "kcal left"
    }

    /// One line for the inline lock-screen widget: "620 kcal left", "No goal set".
    static func inline(_ s: NourloSnapshot) -> String {
        guard s.calorieGoal > 0 else { return "\(s.caloriesEaten) kcal eaten" }
        return "\(headlineNumber(s)) \(headlineCaption(s))"
    }

    /// What VoiceOver reads for the calories widget.
    static func caloriesAccessibility(_ s: NourloSnapshot) -> String {
        guard s.calorieGoal > 0 else { return "\(s.caloriesEaten) calories eaten today." }
        let over = caloriesOver(s)
        let status = over > 0 ? "\(over) calories over your goal" : "\(s.caloriesLeft) calories left"
        return "\(status). \(s.caloriesEaten) of \(s.calorieGoal) eaten today."
    }

    /// "82 / 140 g".
    static func macro(_ value: Int, of goal: Int) -> String {
        goal > 0 ? "\(value) / \(goal) g" : "\(value) g"
    }

    /// 0…1 for a macro bar (no goal → empty bar).
    static func fraction(_ value: Int, of goal: Int) -> Double {
        goal > 0 ? min(max(Double(value) / Double(goal), 0), 1) : 0
    }

    /// VoiceOver text for one macro: "Protein, 82 of 140 grams".
    static func macroAccessibility(_ name: String, _ value: Int, of goal: Int) -> String {
        goal > 0 ? "\(name), \(value) of \(goal) grams" : "\(name), \(value) grams"
    }

    /// Total of the planned meals.
    static func plannedTotal(_ meals: [NourloSnapshot.Meal]) -> Int { meals.reduce(0) { $0 + $1.kcal } }

    /// VoiceOver text for one planned meal: "Lunch: Chicken rice bowl, 640 calories".
    static func mealAccessibility(_ meal: NourloSnapshot.Meal) -> String {
        "\(meal.slot): \(meal.name), \(meal.kcal) calories"
    }

    /// SF Symbol for a meal slot title.
    static func symbol(forSlot slot: String) -> String {
        switch slot.lowercased() {
        case "breakfast": return "sunrise.fill"
        case "lunch": return "sun.max.fill"
        case "dinner": return "moon.fill"
        default: return "sparkles"
        }
    }

    /// "Exercise 2 of 6".
    static func stepPosition(index: Int, total: Int) -> String {
        "Exercise \(min(index + 1, max(total, 1))) of \(max(total, 1))"
    }

    /// "2/6" for the compact Dynamic Island.
    static func stepShort(index: Int, total: Int) -> String {
        "\(min(index + 1, max(total, 1)))/\(max(total, 1))"
    }

    /// "24 min" / "1 h 5 min" for a finished session.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(Int((seconds / 60).rounded()), seconds > 0 ? 1 : 0)
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}
