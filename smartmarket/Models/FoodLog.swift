import SwiftUI

// MARK: - Meal slot

enum MealSlot: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var sfSymbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.fill"
        case .snack:     return "sparkles"
        }
    }

    var accent: Color {
        switch self {
        case .breakfast: return .carbsAccent
        case .lunch:     return .calorieAccent
        case .dinner:    return .fatAccent
        case .snack:     return .proteinAccent
        }
    }

    /// Intelligent defaulting — the slot most likely being logged at `date`.
    static func suggested(at date: Date = Date()) -> MealSlot {
        switch Calendar.current.component(.hour, from: date) {
        case ..<11:   return .breakfast
        case 11..<15: return .lunch
        case 15..<18: return .snack
        default:      return .dinner
        }
    }
}

// MARK: - Logged food entry

struct FoodLogEntry: Codable, Identifiable, Hashable {
    let id: String
    let foodId: String?      // links back to Food.catalog when logged from it
    let name: String
    let slot: MealSlot
    let servingG: Int
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let loggedAt: Date

    init(id: String = UUID().uuidString, foodId: String? = nil, name: String,
         slot: MealSlot, servingG: Int, calories: Int,
         proteinG: Double, carbsG: Double, fatG: Double, loggedAt: Date = Date()) {
        self.id = id
        self.foodId = foodId
        self.name = name
        self.slot = slot
        self.servingG = servingG
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.loggedAt = loggedAt
    }
}

// MARK: - Food log store (local, daily-resetting)

/// Single source of truth for today's logged foods. Persists to UserDefaults and
/// auto-resets each day by keeping only entries logged today — fixing the old
/// "calories never reset at midnight" bug.
@MainActor
@Observable
final class FoodLogStore {

    static let shared = FoodLogStore()

    private let key = "foodLogEntries"
    private let recentsKey = "recentFoodIDs"

    private(set) var entries: [FoodLogEntry] = []
    private(set) var recentFoodIDs: [String] = []

    private init() {
        recentFoodIDs = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        reload()
    }

    /// Reloads today's entries from disk, pruning any from previous days.
    func reload() {
        recentFoodIDs = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        let stored = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([FoodLogEntry].self, from: $0) } ?? []
        let today = stored.filter { Calendar.current.isDateInToday($0.loggedAt) }
        entries = today.sorted { $0.loggedAt < $1.loggedAt }
        if today.count != stored.count { persist() }   // drop stale days from disk
    }

    // MARK: Totals

    var totalCalories: Int { entries.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { entries.reduce(0) { $0 + $1.proteinG } }
    var totalCarbs: Double { entries.reduce(0) { $0 + $1.carbsG } }
    var totalFat: Double { entries.reduce(0) { $0 + $1.fatG } }

    func entries(for slot: MealSlot) -> [FoodLogEntry] { entries.filter { $0.slot == slot } }
    func calories(for slot: MealSlot) -> Int { entries(for: slot).reduce(0) { $0 + $1.calories } }

    // MARK: Mutations (optimistic — UI updates instantly)

    func add(_ entry: FoodLogEntry) {
        entries.append(entry)
        entries.sort { $0.loggedAt < $1.loggedAt }
        persist()
        if let fid = entry.foodId { noteRecent(foodId: fid) }
    }

    func remove(_ entry: FoodLogEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clearToday() {
        entries.removeAll()
        persist()
    }

    func clearAll() {
        entries.removeAll()
        recentFoodIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: recentsKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: Recents

    private func noteRecent(foodId: String) {
        var list = recentFoodIDs.filter { $0 != foodId }
        list.insert(foodId, at: 0)
        recentFoodIDs = Array(list.prefix(12))
        UserDefaults.standard.set(recentFoodIDs, forKey: recentsKey)
    }
}
