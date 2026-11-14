import Foundation
import Observation
import os

struct StockItem: Codable, Identifiable, Hashable {
    let id: UUID
    let food: NutritionFood
    var amount: Double
    /// The use-by day, saved as noon UTC of that calendar day (see `dayStamp`)
    /// so it stays the same day when the time zone changes.
    var expiresAt: Date?
    let addedAt: Date

    /// The use-by day as the start of that day in `calendar`.
    func expiryDay(calendar: Calendar = .current) -> Date? {
        expiresAt.flatMap { Self.localDay(fromStamp: $0, calendar: calendar) }
    }

    /// Food is expired only after its use-by day, never on the day itself.
    func isExpired(today: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let day = expiryDay(calendar: calendar) else { return false }
        return day < calendar.startOfDay(for: today)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// The calendar day `date` falls on in `calendar`, stored as noon UTC of
    /// that year, month and day: a time-zone-independent day.
    static func dayStamp(_ date: Date, calendar: Calendar = .current) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: date)
        parts.hour = 12
        return utc.date(from: parts) ?? date
    }

    /// The start, in `calendar`, of the day a `dayStamp` names.
    static func localDay(fromStamp stamp: Date, calendar: Calendar = .current) -> Date? {
        let parts = utc.dateComponents([.year, .month, .day], from: stamp)
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
            .map { calendar.startOfDay(for: $0) }
    }

    /// Soonest use-by day first (no date last), then the oldest batch.
    static func expiryOrder(_ a: StockItem, _ b: StockItem) -> Bool {
        let dayA = a.expiryDay() ?? .distantFuture, dayB = b.expiryDay() ?? .distantFuture
        return dayA != dayB ? dayA < dayB : a.addedAt < b.addedAt
    }
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
        /// When each meal operation was logged, so old ones can be pruned.
        var mealOperationDates: [String: Date]? = nil
        /// nil: use-by dates are local start-of-day instants (older saves).
        /// 1: they are `StockItem.dayStamp` values.
        var expiryFormat: Int? = StockStore.expiryFormat
    }
    /// Element-by-element fallback used only when the strict decode fails.
    private struct LossySnapshot: Decodable {
        var items: [ResilientStorage.Lossy<StockItem>]?
        var logs: [ResilientStorage.Lossy<FoodLogEntry>]?
        var mealOperations: [String]?
        var mealOperationDates: [String: Date]?
        var expiryFormat: Int?
        var snapshot: Snapshot {
            Snapshot(items: (items ?? []).compactMap(\.value), logs: (logs ?? []).compactMap(\.value),
                     mealOperations: mealOperations, mealOperationDates: mealOperationDates,
                     expiryFormat: expiryFormat)
        }
    }
    private let defaults: UserDefaults
    private let key = "nourloStock_v1"
    private var snapshot: Snapshot
    private let now: () -> Date
    var items: [StockItem] { snapshot.items }
    var logs: [FoodLogEntry] { snapshot.logs }

    /// Meal operation ids only stop a planned meal from being logged twice. Plans
    /// cover a week, so ids older than this can go. Logs are kept: they are the
    /// food history (Food History screen, calorie trend and streaks read them all).
    static let mealOperationRetention: TimeInterval = 90 * 86_400
    private static let logger = Logger(subsystem: "com.mostafa.mealio", category: "StockStore")

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
        snapshot = Self.loadSnapshot(defaults: defaults, key: key)
    }

    /// Re-reads the saved stock, e.g. after other code rewrote storage.
    func reload() {
        snapshot = Self.loadSnapshot(defaults: defaults, key: key)
    }

    /// Strict decode first; on failure back up the raw bytes and keep every
    /// readable item and log so the next save can't drop them all.
    private static func loadSnapshot(defaults: UserDefaults, key: String) -> Snapshot {
        guard let data = defaults.data(forKey: key) else { return Snapshot() }
        let snapshot: Snapshot
        if let strict = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = strict
        } else {
            ResilientStorage.backUp(data, key: key, defaults: defaults)
            snapshot = (try? JSONDecoder().decode(LossySnapshot.self, from: data))?.snapshot ?? Snapshot()
        }
        return migrateExpiryDays(snapshot, defaults: defaults, key: key)
    }

    /// Current format of saved use-by days (see `Snapshot.expiryFormat`).
    nonisolated static let expiryFormat = 1

    /// Older saves kept use-by days as start-of-day instants in the time zone
    /// of the moment; read them in the current time zone once and save them as
    /// day stamps. Runs once: the saved snapshot then carries the new format.
    private static func migrateExpiryDays(_ snapshot: Snapshot, defaults: UserDefaults, key: String) -> Snapshot {
        guard (snapshot.expiryFormat ?? 0) < expiryFormat else { return snapshot }
        var next = snapshot
        for index in next.items.indices {
            next.items[index].expiresAt = next.items[index].expiresAt.map { StockItem.dayStamp($0) }
        }
        next.expiryFormat = expiryFormat
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: key) }
        return next
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
        next.items.append(StockItem(id: UUID(), food: food, amount: amount, expiresAt: Self.day(expiresAt), addedAt: now()))
        try save(next)
    }

    func update(id: UUID, amount: Double, expiresAt: Date?) throws {
        guard amount.isFinite, amount > 0, amount <= 100000 else { throw StockError.invalidAmount }
        guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else { throw StockError.missingItem }
        var next = snapshot
        next.items[index].amount = amount
        next.items[index].expiresAt = Self.day(expiresAt)
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
                .sorted(by: StockItem.expiryOrder)
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
        next.mealOperationDates = (next.mealOperationDates ?? [:]).merging([operationID: now()]) { _, new in new }
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
        do { try save(next) } catch { Self.logger.error("Could not save stock after removing a log: \(error.localizedDescription)") }
    }
    func clearLogs(on date: Date) {
        var next = snapshot
        next.logs.removeAll { Calendar.current.isDate($0.loggedAt, inSameDayAs: date) }
        do { try save(next) } catch { Self.logger.error("Could not save stock after clearing logs: \(error.localizedDescription)") }
    }
    func clear() {
        snapshot = Snapshot()
        defaults.removeObject(forKey: key)
    }
    private static func day(_ date: Date?) -> Date? {
        date.map { StockItem.dayStamp($0) }
    }
    /// Drops meal operation ids past the retention window. Ids saved before
    /// dates were recorded are dated now, so they age out like the rest.
    private func pruned(_ snapshot: Snapshot) -> Snapshot {
        guard let operations = snapshot.mealOperations, !operations.isEmpty else { return snapshot }
        var next = snapshot
        let current = now()
        var dates = next.mealOperationDates ?? [:]
        for id in operations where dates[id] == nil { dates[id] = current }
        let cutoff = current.addingTimeInterval(-Self.mealOperationRetention)
        var seen = Set<String>()
        next.mealOperations = operations.filter { id in
            guard let date = dates[id], date >= cutoff else { return false }
            return seen.insert(id).inserted
        }
        let kept = Set(next.mealOperations ?? [])
        next.mealOperationDates = dates.filter { kept.contains($0.key) }
        return next
    }
    private func save(_ next: Snapshot) throws {
        let next = pruned(next)
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: key)
        snapshot = next
    }
}
