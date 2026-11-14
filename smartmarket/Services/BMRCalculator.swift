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

    /// Whether a weight-loss deficit may be applied at this age. Under-18s are
    /// never given a deficit; their goal is treated as maintain.
    static func allowsWeightLoss(age: Int) -> Bool { age >= Constants.Calories.adultAge }

    /// The goal the targets are actually computed for.
    static func effectiveGoal(_ goal: WeightGoal, age: Int) -> WeightGoal {
        goal == .lose && !allowsWeightLoss(age: age) ? .maintain : goal
    }

    /// The minimum daily target a weight-loss deficit may bring someone to.
    static func safetyFloor(for gender: Gender) -> Int {
        switch gender {
        case .male:   return Constants.Calories.minimumMale
        case .female: return Constants.Calories.minimumFemale
        case .other:  return Constants.Calories.minimumOther
        }
    }

    /// Returns the daily kcal target adjusted for goal and pace.
    /// Maintain is TDEE and gain is TDEE plus a surplus. Only weight loss is
    /// held at the safety floor (and never above maintenance). Under-18s are
    /// never given a deficit.
    static func dailyGoal(tdee: Double, goal: WeightGoal, pace: LossPace, gender: Gender,
                          age: Int = Constants.Calories.adultAge) -> Int {
        switch effectiveGoal(goal, age: age) {
        case .maintain:
            return Int(tdee.rounded())
        case .gain:
            return Int((tdee + Double(Constants.Calories.gainSurplus)).rounded())
        case .lose:
            let raw = tdee - Double(pace.dailyDeficit)
            let floor = min(Double(safetyFloor(for: gender)), tdee)
            return Int(max(raw, floor).rounded())
        }
    }

    /// The deficit that will actually be applied for this pace (after the
    /// safety floor), in kcal per day. 0 for under-18s.
    static func effectiveDeficit(tdee: Double, pace: LossPace, gender: Gender,
                                 age: Int = Constants.Calories.adultAge) -> Int {
        Int(tdee.rounded()) - dailyGoal(tdee: tdee, goal: .lose, pace: pace, gender: gender, age: age)
    }

    /// True when the safety floor (not the pace) sets the weight-loss target.
    static func isCappedBySafetyFloor(tdee: Double, pace: LossPace, gender: Gender,
                                      age: Int = Constants.Calories.adultAge) -> Bool {
        guard allowsWeightLoss(age: age) else { return false }
        return effectiveDeficit(tdee: tdee, pace: pace, gender: gender, age: age) < pace.dailyDeficit
    }

    // MARK: - All targets at once

    struct Targets: Equatable {
        let bmr: Double
        let tdee: Double
        let dailyGoal: Int
    }

    /// The one calculation behind both onboarding's live number and the saved
    /// profile, so what is shown is what is saved.
    static func targets(weight: Double, height: Double, age: Int, gender: Gender,
                        activityLevel: ActivityLevel, goal: WeightGoal, pace: LossPace) -> Targets {
        let b = bmr(weight: weight, height: height, age: age, gender: gender)
        let t = tdee(bmr: b, activityLevel: activityLevel)
        return Targets(bmr: b, tdee: t,
                       dailyGoal: dailyGoal(tdee: t, goal: goal, pace: pace, gender: gender, age: age))
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
    /// An under-18 profile that says "lose" (e.g. older saved data) is moved
    /// to maintain.
    static func populate(profile: inout UserProfile) {
        profile.weightGoal = effectiveGoal(profile.weightGoal, age: profile.age)
        let t = targets(weight: profile.weight, height: profile.height, age: profile.age,
                        gender: profile.gender, activityLevel: profile.activityLevel,
                        goal: profile.weightGoal, pace: profile.lossPace)
        profile.bmr              = t.bmr.rounded()
        profile.tdee             = t.tdee.rounded()
        profile.dailyCalorieGoal = t.dailyGoal
    }

    /// The calorie/macro targets the agent and meal planner read from
    /// `AppState.bmrData`. Call after `populate(profile:)`.
    static func response(for profile: UserProfile, isKeto: Bool) -> BMRResponse {
        let macros = macroTargets(calories: profile.dailyCalorieGoal, isKeto: isKeto)
        func goal(_ g: WeightGoal) -> Int {
            dailyGoal(tdee: profile.tdee, goal: g, pace: profile.lossPace, gender: profile.gender, age: profile.age)
        }
        return BMRResponse(
            bmr: Int(profile.bmr), tdee: Int(profile.tdee),
            loseCalories: goal(.lose), maintainCalories: goal(.maintain), gainCalories: goal(.gain),
            macros: BMRResponse.MacroTargets(protein: macros.proteinG, carbs: macros.carbsG, fat: macros.fatG)
        )
    }
}
