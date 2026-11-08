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
