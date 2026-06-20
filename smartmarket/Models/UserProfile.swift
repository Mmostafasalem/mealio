import Foundation

// MARK: - Gender
enum Gender: String, Codable, CaseIterable, Identifiable {
    case male   = "male"
    case female = "female"
    case other  = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .male:   return "Male"
        case .female: return "Female"
        case .other:  return "Other"
        }
    }
}

// MARK: - Activity level
enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary        = "sedentary"
    case lightlyActive    = "lightly_active"
    case moderatelyActive = "moderately_active"
    case veryActive       = "very_active"
    case superActive      = "super_active"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sedentary:        return "Sedentary"
        case .lightlyActive:    return "Lightly Active"
        case .moderatelyActive: return "Moderately Active"
        case .veryActive:       return "Very Active"
        case .superActive:      return "Super Active"
        }
    }

    var description: String {
        switch self {
        case .sedentary:        return "Little or no exercise"
        case .lightlyActive:    return "Light exercise 1–3 days/week"
        case .moderatelyActive: return "Moderate exercise 3–5 days/week"
        case .veryActive:       return "Hard exercise 6–7 days/week"
        case .superActive:      return "Very hard exercise + physical job"
        }
    }

    var sfSymbol: String {
        switch self {
        case .sedentary:        return "sofa.fill"
        case .lightlyActive:    return "figure.walk"
        case .moderatelyActive: return "figure.run"
        case .veryActive:       return "figure.strengthtraining.traditional"
        case .superActive:      return "flame.fill"
        }
    }

    /// Mifflin-St Jeor TDEE multiplier
    var multiplier: Double {
        switch self {
        case .sedentary:        return 1.2
        case .lightlyActive:    return 1.375
        case .moderatelyActive: return 1.55
        case .veryActive:       return 1.725
        case .superActive:      return 1.9
        }
    }
}

// MARK: - Weight goal
enum WeightGoal: String, Codable, CaseIterable, Identifiable {
    case lose     = "lose"
    case maintain = "maintain"
    case gain     = "gain"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lose:     return "Lose Weight"
        case .maintain: return "Maintain Weight"
        case .gain:     return "Gain Weight"
        }
    }

    var description: String {
        switch self {
        case .lose:     return "Burn fat, feel lighter"
        case .maintain: return "Stay at current weight"
        case .gain:     return "Build muscle, get stronger"
        }
    }

    var sfSymbol: String {
        switch self {
        case .lose:     return "arrow.down.circle.fill"
        case .maintain: return "equal.circle.fill"
        case .gain:     return "arrow.up.circle.fill"
        }
    }
}

// MARK: - Loss pace (only relevant when goal == .lose)
enum LossPace: Double, Codable, CaseIterable, Identifiable {
    case slow   = 0.25
    case medium = 0.5
    case fast   = 1.0

    var id: Double { rawValue }

    var displayName: String {
        switch self {
        case .slow:   return "0.25 kg / week"
        case .medium: return "0.5 kg / week"
        case .fast:   return "1 kg / week"
        }
    }

    /// Calorie deficit per day for this pace
    var dailyDeficit: Int {
        // 1 kg fat ≈ 7700 kcal → divide by 7 days
        Int(rawValue * 7700 / 7)
    }
}

// MARK: - UserProfile  (Codable so it can be saved to UserDefaults + sent to Python API)
struct UserProfile: Codable {
    var name: String         = ""
    var email: String        = ""
    var weight: Double       = 70       // kg
    var height: Double       = 170      // cm
    var age: Int             = 25
    var gender: Gender       = .male
    var activityLevel: ActivityLevel = .moderatelyActive
    var weightGoal: WeightGoal       = .maintain
    var lossPace: LossPace           = .medium   // used only when weightGoal == .lose

    // Computed after onboarding and cached here so the agent can read it directly
    var bmr: Double          = 0
    var tdee: Double         = 0
    var dailyCalorieGoal: Int = 0

    /// Keys must match what the Python backend expects exactly
    enum CodingKeys: String, CodingKey {
        case name, email, weight, height, age, gender
        case activityLevel    = "activity_level"
        case weightGoal       = "weight_goal"
        case lossPace         = "loss_pace"
        case bmr, tdee
        case dailyCalorieGoal = "daily_calorie_goal"
    }
}

// MARK: - Validation
extension UserProfile {
    var isValid: Bool {
        weight > 0 && height > 0 && age > 0 && age < 130
    }
}

// MARK: - Persistence helper (Keychain — health data is sensitive)
extension UserProfile {
    static func load() -> UserProfile {
        // Keychain is the source of truth
        if let profile = KeychainHelper.load(UserProfile.self, key: Constants.Storage.userProfile) {
            return profile
        }
        // Migrate from UserDefaults on first run after update
        if let data = UserDefaults.standard.data(forKey: Constants.Storage.userProfile),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            KeychainHelper.save(profile, key: Constants.Storage.userProfile)
            UserDefaults.standard.removeObject(forKey: Constants.Storage.userProfile)
            return profile
        }
        return UserProfile()
    }

    func save() {
        KeychainHelper.save(self, key: Constants.Storage.userProfile)
    }
}
