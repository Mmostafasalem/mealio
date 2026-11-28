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

/// One stock batch a logged food takes from, and how much (in the batch's own unit).
struct StockUse: Hashable {
    let item: StockItem
    let amount: Double
    /// What stays in that batch after this.
    var left: Double { max(0, item.amount - amount) }
}

/// The line a review card shows for one food: which stock item it comes out of, and what's left.
struct StockSummary: Equatable {
    /// The stock item's name; nil when the food isn't in stock.
    let name: String?
    /// What stays in stock after this, in `unit`.
    let left: Double
    let unit: NutritionFood.Basis
    /// How much more than the stock holds is being logged (0 when it covers it).
    let short: Double
    let pieceAmount: Double?
    let pieceName: String?

    var inStock: Bool { name != nil }

    static func amount(_ value: Double, _ unit: NutritionFood.Basis) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
        return unit == .serving ? "\(number) serving\(value == 1 ? "" : "s")" : "\(number) \(unit.rawValue)"
    }

    /// "From your stock: Bread, whole-wheat (150 g left after this, about 5 slices)" or "Not in your stock".
    var text: String {
        guard let name else { return "Not in your stock" }
        if self.left < 0 { return "From your stock: \(name) (the recipe's ingredients)" }
        var left = Self.amount(self.left, unit) + " left after this"
        if let piece = pieceAmount, piece > 0, let word = pieceName, self.left > 0 {
            let count = (self.left / piece).rounded()
            if count >= 1 { left += ", about \(Int(count)) \(count == 1 ? word : PieceWords.plural(word))" }
        }
        if short > 0.05 { left += "; that's \(Self.amount(short, unit)) more than you had" }
        return "From your stock: \(name) (\(left))"
    }
}

/// Piece words for display.
enum PieceWords {
    static func plural(_ word: String) -> String {
        let w = word.lowercased()
        if w.hasSuffix("s") { return w }
        if w.hasSuffix("y"), let last = w.dropLast().last, !"aeiou".contains(last) { return String(w.dropLast()) + "ies" }
        if w.hasSuffix("ch") || w.hasSuffix("sh") || w.hasSuffix("x") { return w + "es" }
        if w == "loaf" { return "loaves" }
        return w + "s"
    }
    static func count(_ n: Double, _ word: String) -> String {
        let number = n.formatted(.number.precision(.fractionLength(0...1)))
        return "\(number) \(n == 1 ? word : plural(word))"
    }
}

/// What a logged food took from one batch: the batch as it was, and the amount.
struct StockDraw: Codable, Hashable {
    let item: StockItem
    let amount: Double
    let at: Date
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
        /// What each logged food (by its log entry id) took out of stock, so an undo can put it back.
        var draws: [String: [StockDraw]]? = nil
    }
    /// Element-by-element fallback used only when the strict decode fails.
    private struct LossySnapshot: Decodable {
        var items: [ResilientStorage.Lossy<StockItem>]?
        var logs: [ResilientStorage.Lossy<FoodLogEntry>]?
        var mealOperations: [String]?
        var mealOperationDates: [String: Date]?
        var expiryFormat: Int?
        var draws: [String: [StockDraw]]?
        var snapshot: Snapshot {
            Snapshot(items: (items ?? []).compactMap(\.value), logs: (logs ?? []).compactMap(\.value),
                     mealOperations: mealOperations, mealOperationDates: mealOperationDates,
                     expiryFormat: expiryFormat, draws: draws)
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
        NotificationCenter.default.post(name: .planInputsDidChange, object: nil)   // the plan is built from stock too
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
        NotificationCenter.default.post(name: .planInputsDidChange, object: nil)   // the plan is built from stock too
    }

    func consume(id: UUID, amount: Double, slot: MealSlot) throws {
        guard amount.isFinite, amount > 0 else { throw StockError.invalidAmount }
        guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else { throw StockError.missingItem }
        guard amount <= snapshot.items[index].amount else { throw StockError.insufficientStock }
        var next = snapshot
        next.logs.append(FoodLogEntry(nutritionFood: next.items[index].food, slot: slot, amount: amount))
        next.items[index].amount -= amount
        let usedUp = next.items[index].amount < 0.000001
        if usedUp { next.items.remove(at: index) }
        try save(next)
        // A food that ran out leaves the plan too.
        if usedUp { NotificationCenter.default.post(name: .planInputsDidChange, object: nil) }
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
        let before = next.items.count
        next.items.removeAll { $0.amount < 0.000001 }
        let ranOut = next.items.count < before
        next.mealOperations = (next.mealOperations ?? []) + [operationID]
        next.mealOperationDates = (next.mealOperationDates ?? [:]).merging([operationID: now()]) { _, new in new }
        try save(next)
        if ranOut { NotificationCenter.default.post(name: .planInputsDidChange, object: nil) }
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

    // MARK: Logged food comes out of stock
    //
    // Every way of logging food (search, quick add, voice, photo, plan rows, recipes)
    // goes through `FoodLogStore.add`, which calls `takeOut`: the amount comes out of
    // the matching stock, soonest use-by first, and what was taken is kept under the
    // log entry's id so an undo puts exactly that back. Food logged from My Stock's own
    // screens (`consume`, `consumeMeal`) is recorded here directly and never goes
    // through `FoodLogStore.add`, so nothing is taken twice.

    static let drawLimit = 400

    /// The stock batches `food` would come out of, best match first, and how much of each
    /// (in the batch's own unit). Empty when nothing in stock is that food.
    func preview(for food: NutritionFood, amount: Double) -> [StockUse] {
        Self.loggingUses(for: food, amount: amount, in: snapshot.items)
    }

    /// Takes the logged amount out of stock and remembers it under `entryID`. Returns what was taken.
    @discardableResult
    func takeOut(for entryID: String, food: NutritionFood, amount: Double) -> [StockUse] {
        let uses = Self.loggingUses(for: food, amount: amount, in: snapshot.items)
        apply(uses, for: entryID)
        return uses
    }

    /// What logging `amount` of `food` takes: the food itself, or for your own recipe
    /// weighed in grams, its ingredients in the share of the dish you ate.
    static func loggingUses(for food: NutritionFood, amount: Double, in items: [StockItem]) -> [StockUse] {
        if food.source == .recipe, let recipe = food.recipeDetails, recipe.cookedYieldG > 0, food.basis == .grams {
            let share = amount / recipe.cookedYieldG
            return uses(for: recipe.ingredients.map { NutritionIngredient(food: $0.food, amount: $0.amount * share) }, in: items)
        }
        return uses(for: food, amount: amount, in: items)
    }

    /// Takes each ingredient (in full) out of stock under `entryID` (a recipe that was cooked).
    @discardableResult
    func takeOut(for entryID: String, ingredients: [NutritionIngredient]) -> [StockUse] {
        let uses = Self.uses(for: ingredients, in: snapshot.items)
        apply(uses, for: entryID)
        return uses
    }

    /// Takes the given amounts out of stock under `entryID`.
    func takeOut(for entryID: String, uses: [StockUse]) {
        apply(uses, for: entryID)
    }

    /// What the log entry took out of stock (nothing when it wasn't in stock).
    func draws(for entryID: String) -> [StockDraw] { snapshot.draws?[entryID] ?? [] }

    /// Undo: whatever the log entry took goes back into stock (a batch that ran out comes back).
    @discardableResult
    func putBack(for entryID: String) -> Bool {
        guard let draws = snapshot.draws?[entryID], !draws.isEmpty else { return false }
        var next = snapshot
        for draw in draws {
            if let index = next.items.firstIndex(where: { $0.id == draw.item.id }) {
                next.items[index].amount += draw.amount
            } else {
                var item = draw.item
                item.amount = draw.amount
                next.items.append(item)
            }
        }
        next.draws?[entryID] = nil
        do { try save(next) } catch { Self.logger.error("Could not put food back into stock: \(error.localizedDescription)"); return false }
        NotificationCenter.default.post(name: .planInputsDidChange, object: nil)
        return true
    }

    /// The entry is gone for good without an undo: forget what it took (stock stays as it is).
    func forgetDraws(for entryID: String) {
        guard snapshot.draws?[entryID] != nil else { return }
        var next = snapshot
        next.draws?[entryID] = nil
        try? save(next)
    }

    private func apply(_ uses: [StockUse], for entryID: String) {
        guard !uses.isEmpty, !entryID.isEmpty else { return }
        var next = snapshot
        var draws = next.draws?[entryID] ?? []
        for use in uses where use.amount > 0.000001 {
            guard let index = next.items.firstIndex(where: { $0.id == use.item.id }) else { continue }
            let amount = min(use.amount, next.items[index].amount)
            draws.append(StockDraw(item: next.items[index], amount: amount, at: now()))
            next.items[index].amount -= amount
        }
        let before = next.items.count
        next.items.removeAll { $0.amount < 0.000001 }
        let ranOut = next.items.count < before
        var all = next.draws ?? [:]
        all[entryID] = draws
        next.draws = all
        do { try save(next) } catch { Self.logger.error("Could not take logged food out of stock: \(error.localizedDescription)") }
        if ranOut { NotificationCenter.default.post(name: .planInputsDidChange, object: nil) }
    }

    // MARK: Matching (pure)

    /// Whether `stockFood` (in My Stock) is the food that was logged: the same record, or
    /// the same food by name ("Egg, whole, cooked" is the "Egg, whole, raw" in stock;
    /// "Chicken broth" is not chicken). Dishes match only their own record.
    static func isSame(_ stockFood: NutritionFood, as food: NutritionFood) -> Bool {
        if stockFood.id == food.id { return true }
        let dishes: Set<NutritionFood.Source> = [.recipe, .menu, .cookbook]
        if dishes.contains(food.source) || dishes.contains(stockFood.source) { return false }
        func lead(_ name: String) -> String {
            let parts = name.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard let first = parts.first else { return name }
            let words = KitchenMatcher.words(first)
            if words.count == 1, !words.isDisjoint(with: KitchenMatcher.groups), parts.count > 1 { return first + " " + parts[1] }
            return first
        }
        func has(_ names: String, _ term: String) -> Bool {
            let line = CookbookRecipe.Line(text: term, food: nil, grams: nil, match: term, pantry: nil)
            return KitchenMatcher(names: [names]).has(line)
        }
        return has(stockFood.name, lead(food.name)) || has(food.name, lead(stockFood.name))
    }

    /// `amount` of `food` in `stockFood`'s unit; nil when the two can't be compared.
    static func convert(_ amount: Double, of food: NutritionFood, to stockFood: NutritionFood) -> Double? {
        switch (food.basis, stockFood.basis) {
        case (.serving, .serving): return amount
        case (.serving, _):
            guard let per = food.servingAmount ?? food.pieceAmount else { return nil }
            return amount * per
        case (_, .serving):
            guard let per = stockFood.servingAmount ?? stockFood.pieceAmount, per > 0 else { return nil }
            return amount / per
        default: return amount   // grams and millilitres are taken 1:1 (as on the label)
        }
    }

    static func uses(for food: NutritionFood, amount: Double, in items: [StockItem]) -> [StockUse] {
        guard amount.isFinite, amount > 0 else { return [] }
        let exact = items.filter { $0.food.id == food.id }.sorted(by: StockItem.expiryOrder)
        let named = items.filter { $0.food.id != food.id && isSame($0.food, as: food) }.sorted(by: StockItem.expiryOrder)
        var uses: [StockUse] = []
        var remaining = amount   // in the logged food's unit
        for item in exact + named where remaining > 0.000001 {
            guard let need = convert(remaining, of: food, to: item.food), need > 0 else { continue }
            let take = min(need, item.amount)
            uses.append(StockUse(item: item, amount: take))
            remaining -= remaining * (take / need)
        }
        return uses
    }

    /// What logging `amount` of `food` would do to My Stock, for the line on a review card.
    /// `exactOnly`: only the same food record counts (as "Log meal from stock" does).
    func summary(for food: NutritionFood, amount: Double, exactOnly: Bool = false) -> StockSummary {
        let items = exactOnly ? snapshot.items.filter { $0.food.id == food.id && $0.food.basis == food.basis } : snapshot.items
        return Self.summary(uses: Self.loggingUses(for: food, amount: amount, in: items), food: food, amount: amount, items: items)
    }

    /// The same, for food that has already been logged (its draws, against stock as it is now).
    func summary(afterLogging entryID: String, food: NutritionFood, amount: Double) -> StockSummary {
        let taken = draws(for: entryID).map { StockUse(item: $0.item, amount: $0.amount) }
        guard let first = taken.first else { return StockSummary(name: nil, left: 0, unit: food.basis, short: 0, pieceAmount: nil, pieceName: nil) }
        let same = snapshot.items.filter { $0.food.id == first.item.food.id || Self.isSame($0.food, as: first.item.food) }
            .filter { $0.food.basis == first.item.food.basis }
        let left = same.reduce(0) { $0 + $1.amount }
        return StockSummary(name: first.item.food.name, left: left, unit: first.item.food.basis, short: 0,
                            pieceAmount: first.item.food.pieceAmount, pieceName: first.item.food.pieceName)
    }

    static func summary(uses: [StockUse], food: NutritionFood, amount: Double, items: [StockItem]) -> StockSummary {
        guard let first = uses.first else { return StockSummary(name: nil, left: 0, unit: food.basis, short: 0, pieceAmount: nil, pieceName: nil) }
        if uses.contains(where: { $0.item.food.id != food.id && !isSame($0.item.food, as: food) }) {
            // A recipe: its ingredients come out of stock.
            var names: [String] = []
            for use in uses where !names.contains(use.item.food.name) { names.append(use.item.food.name) }
            return StockSummary(name: names.prefix(3).joined(separator: "; ") + (names.count > 3 ? " …" : ""), left: -1,
                                unit: food.basis, short: 0, pieceAmount: nil, pieceName: nil)
        }
        let unit = first.item.food.basis
        let matching = items.filter { $0.food.id == food.id || isSame($0.food, as: food) }.filter { $0.food.basis == unit }
        let taken = uses.filter { $0.item.food.basis == unit }.reduce(0) { $0 + $1.amount }
        let left = max(0, matching.reduce(0) { $0 + $1.amount } - taken)
        let wanted = convert(amount, of: food, to: first.item.food) ?? taken
        return StockSummary(name: first.item.food.name, left: left, unit: unit, short: max(0, wanted - taken),
                            pieceAmount: first.item.food.pieceAmount, pieceName: first.item.food.pieceName)
    }

    static func uses(for ingredients: [NutritionIngredient], in items: [StockItem]) -> [StockUse] {
        var left = items
        var all: [StockUse] = []
        for ingredient in ingredients {
            let uses = uses(for: ingredient.food, amount: ingredient.amount, in: left)
            for use in uses {
                if let index = left.firstIndex(where: { $0.id == use.item.id }) { left[index].amount -= use.amount }
            }
            left.removeAll { $0.amount < 0.000001 }
            all += uses
        }
        return all
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

    /// Empties the shelf for a new week; what was eaten (the food history) stays.
    func clearItems() {
        var next = snapshot
        next.items = []
        do { try save(next) } catch { Self.logger.error("Could not empty stock: \(error.localizedDescription)") }
        NotificationCenter.default.post(name: .planInputsDidChange, object: nil)   // the plan is built from stock too
    }
    private static func day(_ date: Date?) -> Date? {
        date.map { StockItem.dayStamp($0) }
    }
    /// Drops meal operation ids past the retention window. Ids saved before
    /// dates were recorded are dated now, so they age out like the rest.
    private func pruned(_ snapshot: Snapshot) -> Snapshot {
        var snapshot = snapshot
        // Only the latest few hundred logged foods can still be undone or deleted back into stock.
        if let draws = snapshot.draws, draws.count > Self.drawLimit {
            let kept = draws.sorted { ($0.value.first?.at ?? .distantPast) > ($1.value.first?.at ?? .distantPast) }.prefix(Self.drawLimit)
            snapshot.draws = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
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
        let logsChanged = snapshot.logs != next.logs
        snapshot = next
        // Food logged from (or removed back to) stock counts as logged food too.
        if logsChanged { NotificationCenter.default.post(name: .foodLogDidChange, object: nil) }
    }
}
