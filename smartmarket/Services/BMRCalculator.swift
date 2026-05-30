import Foundation

/// Pure Swift BMR and calorie calculations — no network, no side effects.
/// Uses Mifflin-St Jeor equation (most accurate for general population).
enum BMRCalculator {

    // MARK: - BMR (Basal Metabolic Rate)

    /// Returns daily BMR in kcal for the given profile.
    static func bmr(weight: Double, height: Double, age: Int, gender: Gender) -> Double {
        // Mifflin-St Jeor: kcal/day
        let base = (10 * weight) + (6.25 * height) - (5 * Double(age))
        switch gender {
        case .male:   return base + 5
        case .female: return base - 161
        case .other:  return base - 78   // midpoint between male and female constants
        }
    }

    // MARK: - TDEE (Total Daily Energy Expenditure)

    /// Applies activity multiplier to BMR.
    static func tdee(bmr: Double, activityLevel: ActivityLevel) -> Double {
        bmr * activityLevel.multiplier
    }

    // MARK: - Daily calorie goal

    /// Returns the daily kcal target adjusted for goal and pace.
    /// Respects minimum safe calorie floors.
    static func dailyGoal(tdee: Double, goal: WeightGoal, pace: LossPace, gender: Gender) -> Int {
        let raw: Double
        switch goal {
        case .maintain:
            raw = tdee
        case .lose:
            raw = tdee - Double(pace.dailyDeficit)
        case .gain:
            raw = tdee + 300   // lean bulk default
        }

        let floor: Double
        switch gender {
        case .male:   floor = Double(Constants.Calories.minimumMale)
        case .female: floor = Double(Constants.Calories.minimumFemale)
        case .other:  floor = Double(Constants.Calories.minimumOther)
        }

        return Int(max(raw, floor).rounded())
    }

    // MARK: - Macro split (gram targets for given calorie goal)

    struct MacroTargets {
        let calories: Int
        let proteinG: Int   // 30% of calories
        let carbsG: Int     // 40% of calories
        let fatG: Int       // 30% of calories

        // Adjusts split for keto preference
        static func ketogenic(calories: Int) -> MacroTargets {
            MacroTargets(
                calories: calories,
                proteinG: Int((Double(calories) * 0.25 / 4).rounded()),
                carbsG:   Int((Double(calories) * 0.05 / 4).rounded()),
                fatG:     Int((Double(calories) * 0.70 / 9).rounded())
            )
        }
    }

    static func macroTargets(calories: Int, isKeto: Bool = false) -> MacroTargets {
        if isKeto { return .ketogenic(calories: calories) }
        return MacroTargets(
            calories: calories,
            proteinG: Int((Double(calories) * 0.30 / 4).rounded()),
            carbsG:   Int((Double(calories) * 0.40 / 4).rounded()),
            fatG:     Int((Double(calories) * 0.30 / 9).rounded())
        )
    }

    // MARK: - Convenience: compute all values at once from a profile
    /// Updates the profile's cached bmr, tdee, and dailyCalorieGoal in place.
    static func populate(profile: inout UserProfile) {
        let b = bmr(weight: profile.weight, height: profile.height,
                    age: profile.age, gender: profile.gender)
        let t = tdee(bmr: b, activityLevel: profile.activityLevel)
        let g = dailyGoal(tdee: t, goal: profile.weightGoal,
                          pace: profile.lossPace, gender: profile.gender)
        profile.bmr              = b.rounded()
        profile.tdee             = t.rounded()
        profile.dailyCalorieGoal = g
    }
}
