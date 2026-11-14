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
    let foodId: String?      // source-qualified nutrition ID; old catalog IDs remain readable
    let name: String
    let slot: MealSlot
    let servingG: Int
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let loggedAt: Date
    let portionAmount: Double?
    let nutritionFood: NutritionFood? // immutable source snapshot; absent in legacy/estimated entries

    var amount: Double { portionAmount ?? Double(servingG) }
    var amountUnit: String { nutritionFood?.basis.rawValue ?? "g" }

    init(id: String = UUID().uuidString, foodId: String? = nil, name: String,
         slot: MealSlot, servingG: Int, calories: Int,
         proteinG: Double, carbsG: Double, fatG: Double, loggedAt: Date = Date(), nutritionFood: NutritionFood? = nil, portionAmount: Double? = nil) {
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
        self.portionAmount = portionAmount
        self.nutritionFood = nutritionFood
    }
    init(nutritionFood food: NutritionFood, slot: MealSlot, amount: Double) {
        let p = food.portion(amount)
        self.init(foodId: food.id, name: food.name, slot: slot, servingG: Int(amount.rounded()),
                  calories: Int(p.kcal.rounded()), proteinG: p.protein, carbsG: p.carbs, fatG: p.fat,
                  nutritionFood: food, portionAmount: amount)
    }
}

// MARK: - Food log store (local history, daily totals)

/// Preserves recorded history while deriving today’s totals from the current date.
@MainActor
@Observable
final class FoodLogStore {

    static let shared = FoodLogStore()

    private let key = "foodLogEntries"
    private let recentsKey = "recentFoodIDs"

    private var history: [FoodLogEntry] = []
    private let defaults: UserDefaults
    private let stock: StockStore
    var allEntries: [FoodLogEntry] { (history + stock.logs).sorted { $0.loggedAt < $1.loggedAt } }
    var entries: [FoodLogEntry] { allEntries.filter { Calendar.current.isDateInToday($0.loggedAt) } }
    private(set) var recentFoodIDs: [String] = []

    init(defaults: UserDefaults = .standard, stock: StockStore? = nil) {
        self.defaults = defaults
        self.stock = stock ?? .shared
        recentFoodIDs = defaults.stringArray(forKey: recentsKey) ?? []
        reload()
    }

    /// Reads legacy logs without discarding previous days.
    func reload() {
        recentFoodIDs = defaults.stringArray(forKey: recentsKey) ?? []
        // One bad entry must not wipe the log; unreadable bytes are backed up.
        history = ResilientStorage.loadArray(FoodLogEntry.self, key: key, defaults: defaults)
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
        history.append(entry)
        history.sort { $0.loggedAt < $1.loggedAt }
        persist()
        if let fid = entry.foodId { noteRecent(foodId: fid) }
    }

    func remove(_ entry: FoodLogEntry) {
        history.removeAll { $0.id == entry.id }
        stock.removeLog(id: entry.id)
        persist()
    }

    func clearToday() {
        history.removeAll { Calendar.current.isDateInToday($0.loggedAt) }
        stock.clearLogs(on: Date())
        persist()
    }

    func clearAll() {
        history.removeAll()
        stock.clear()
        recentFoodIDs.removeAll()
        NutritionCatalogService.shared.clear()
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: recentsKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: Recents

    private func noteRecent(foodId: String) {
        var list = recentFoodIDs.filter { $0 != foodId }
        list.insert(foodId, at: 0)
        recentFoodIDs = Array(list.prefix(12))
        defaults.set(recentFoodIDs, forKey: recentsKey)
    }
}
