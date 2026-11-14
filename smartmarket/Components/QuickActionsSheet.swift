import SwiftUI

enum MealioQuickAction: String, CaseIterable, Identifiable {
    case home, meals, shop, train, profile, logFood, cart, groceries
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .meals: return "Meal plan"
        case .shop: return "Browse groceries"
        case .train: return "Workouts and exercises"
        case .profile: return "Profile and settings"
        case .logFood: return "Log food"
        case .cart: return "View cart"
        case .groceries: return "Grocery checklist"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .meals: return "fork.knife"
        case .shop: return "storefront"
        case .train: return "figure.run"
        case .profile: return "person.crop.circle"
        case .logFood: return "plus.circle"
        case .cart: return "cart"
        case .groceries: return "checklist"
        }
    }
    var tab: Int? {
        switch self {
        case .home: return 0
        case .meals: return 1
        case .shop: return 2
        case .train: return 3
        default: return nil
        }
    }
    static func matching(_ query: String) -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allCases }
        return allCases.filter { ($0.title + " " + $0.rawValue).localizedStandardContains(query) }
    }
}
