import Foundation
import Observation

/// Local-only "How was it?" ratings (1…5) keyed by recipe title. Never synced or
/// sent anywhere; lives in UserDefaults on this device.
@MainActor
@Observable
final class RecipeRatingStore {
    static let shared = RecipeRatingStore()

    private static let key = "recipeRatings_v1"
    private let defaults: UserDefaults
    private(set) var ratings: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ratings = defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
    }

    /// 0 when the recipe has not been rated.
    func rating(for title: String) -> Int { ratings[Self.normalize(title)] ?? 0 }

    /// 0 clears the rating.
    func setRating(_ value: Int, for title: String) {
        let key = Self.normalize(title)
        guard !key.isEmpty else { return }
        let value = min(max(value, 0), 5)
        if value == 0 { ratings[key] = nil } else { ratings[key] = value }
        defaults.set(ratings, forKey: Self.key)
    }

    private static func normalize(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
