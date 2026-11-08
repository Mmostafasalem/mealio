import Foundation
import Observation

struct StockItem: Codable, Identifiable, Hashable {
    let id: UUID
    let food: NutritionFood
    var amount: Double
    var expiresAt: Date?
    let addedAt: Date
}

/// Quantities and their consumption records are saved together in one snapshot.
/// Deleting an intake record does not put eaten food back into the cupboard.
@MainActor @Observable
final class StockStore {
    static let shared = StockStore()
    private struct Snapshot: Codable {
        var items: [StockItem] = []
        var logs: [FoodLogEntry] = []
        var mealOperations: [String]? = nil
    }
    private let defaults: UserDefaults
    private let key = "nourloStock_v1"
    private var snapshot: Snapshot
    var items: [StockItem] { snapshot.items }
    var logs: [FoodLogEntry] { snapshot.logs }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
    }

    enum StockError: LocalizedError {
        case invalidAmount, missingItem, insufficientStock
        var errorDescription: String? {
            switch self {
            case .invalidAmount: return "Enter a valid amount greater than zero."
            case .missingItem: return "This food is no longer in your stock."
            case .insufficientStock: return "The portion is larger than the amount in stock."
            }
        }
    }

    func add(food: NutritionFood, amount: Double, expiresAt: Date? = nil) throws {
        guard food.isValid, amount.isFinite, amount > 0, amount <= 100000 else { throw StockError.invalidAmount }
        var next = snapshot
        next.items.append(StockItem(id: UUID(), food: food, amount: amount, expiresAt: expiresAt, addedAt: Date()))
        try save(next)
    }

    func update(id: UUID, amount: Double, expiresAt: Date?) throws {
        guard amount.isFinite, amount > 0, amount <= 100000 else { throw StockError.invalidAmount }
        guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else { throw StockError.missingItem }
        var next = snapshot
        next.items[index].amount = amount
        next.items[index].expiresAt = expiresAt
        try save(next)
    }

    func remove(id: UUID) throws {
        var next = snapshot
        next.items.removeAll { $0.id == id }
        try save(next)
    }

    func consume(id: UUID, amount: Double, slot: MealSlot) throws {
        guard amount.isFinite, amount > 0 else { throw StockError.invalidAmount }
        guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else { throw StockError.missingItem }
        guard amount <= snapshot.items[index].amount else { throw StockError.insufficientStock }
        var next = snapshot
        next.logs.append(FoodLogEntry(nutritionFood: next.items[index].food, slot: slot, amount: amount))
        next.items[index].amount -= amount
        if next.items[index].amount < 0.000001 { next.items.remove(at: index) }
        try save(next)
    }

    func hasLoggedMeal(_ operationID: String) -> Bool {
        snapshot.mealOperations?.contains(operationID) == true
    }

    func missingIngredients(for ingredients: [NutritionIngredient]) throws -> [NutritionIngredient] {
        let required = try requirements(ingredients)
        return required.compactMap { ingredient in
            let available = snapshot.items.filter { $0.food.id == ingredient.food.id && $0.food.basis == ingredient.food.basis }
                .reduce(0) { $0 + $1.amount }
            let missing = ingredient.amount - available
            return missing > 0.000001 ? NutritionIngredient(food: ingredient.food, amount: missing) : nil
        }
    }

    /// All ingredients are checked before a single snapshot records the full meal.
    /// A stable operation ID also prevents a repeated tap/relaunch from logging twice.
    func consumeMeal(_ ingredients: [NutritionIngredient], slot: MealSlot, operationID: String) throws {
        guard !operationID.isEmpty, operationID.count <= 300 else { throw StockError.invalidAmount }
        if hasLoggedMeal(operationID) { return }
        let required = try requirements(ingredients)
        guard try missingIngredients(for: ingredients).isEmpty else { throw StockError.insufficientStock }
        var next = snapshot
        for ingredient in required {
            var remaining = ingredient.amount
            let batches = next.items.filter { $0.food.id == ingredient.food.id && $0.food.basis == ingredient.food.basis }
                .sorted { ($0.expiresAt ?? .distantFuture, $0.addedAt) < ($1.expiresAt ?? .distantFuture, $1.addedAt) }
            for batch in batches where remaining > 0.000001 {
                guard let index = next.items.firstIndex(where: { $0.id == batch.id }) else { continue }
                let amount = min(remaining, next.items[index].amount)
                next.logs.append(FoodLogEntry(nutritionFood: next.items[index].food, slot: slot, amount: amount))
                next.items[index].amount -= amount
                remaining -= amount
            }
        }
        next.items.removeAll { $0.amount < 0.000001 }
        next.mealOperations = (next.mealOperations ?? []) + [operationID]
        try save(next)
    }

    private func requirements(_ ingredients: [NutritionIngredient]) throws -> [NutritionIngredient] {
        guard !ingredients.isEmpty, ingredients.count <= 50,
              ingredients.allSatisfy({ $0.food.isValid && $0.amount.isFinite && $0.amount > 0 && $0.amount <= 100000 })
        else { throw StockError.invalidAmount }
        var grouped: [String: NutritionIngredient] = [:]
        for ingredient in ingredients {
            if var existing = grouped[ingredient.food.id] {
                guard existing.food.basis == ingredient.food.basis else { throw StockError.invalidAmount }
                existing.amount += ingredient.amount
                grouped[ingredient.food.id] = existing
            } else { grouped[ingredient.food.id] = ingredient }
        }
        return grouped.values.sorted { $0.food.id < $1.food.id }
    }

    func removeLog(id: String) {
        var next = snapshot
        next.logs.removeAll { $0.id == id }
        try? save(next)
    }
    func clearLogs(on date: Date) {
        var next = snapshot
        next.logs.removeAll { Calendar.current.isDate($0.loggedAt, inSameDayAs: date) }
        try? save(next)
    }
    func clear() {
        snapshot = Snapshot()
        defaults.removeObject(forKey: key)
    }
    private func save(_ next: Snapshot) throws {
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: key)
        snapshot = next
    }
}
