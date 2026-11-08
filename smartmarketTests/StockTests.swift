import XCTest
@testable import smartmarket

@MainActor
final class StockTests: XCTestCase {
    func testConsumePersistsStockAndIntakeTogetherAndRejectsOverdraw() throws {
        let name = "StockTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let food = try XCTUnwrap(NutritionDatabase.load().first)
        let store = StockStore(defaults: defaults)
        try store.add(food: food, amount: 500)
        let id = try XCTUnwrap(store.items.first?.id)
        XCTAssertThrowsError(try store.consume(id: id, amount: 501, slot: .lunch))
        XCTAssertThrowsError(try store.consume(id: id, amount: .nan, slot: .lunch))
        XCTAssertEqual(store.items.first?.amount, 500)
        XCTAssertTrue(store.logs.isEmpty)
        try store.consume(id: id, amount: 125, slot: .lunch)
        let restored = StockStore(defaults: defaults)
        XCTAssertEqual(restored.items.first?.amount, 375)
        XCTAssertEqual(restored.logs.first?.amount, 125)
        let log = FoodLogStore(defaults: defaults, stock: restored)
        XCTAssertEqual(log.totalCalories, Int(food.portion(125).kcal.rounded()))
        log.reload()
        XCTAssertEqual(log.entries.count, 1, "Reload must not duplicate stock consumption")
        log.remove(try XCTUnwrap(log.entries.first))
        XCTAssertTrue(log.entries.isEmpty)
        XCTAssertEqual(restored.items.first?.amount, 375, "Deleting intake does not replenish eaten food")
        try restored.consume(id: id, amount: 375, slot: .dinner)
        XCTAssertTrue(restored.items.isEmpty)
        XCTAssertEqual(restored.logs.count, 1)
        log.clearAll()
        XCTAssertTrue(StockStore(defaults: defaults).logs.isEmpty)
        XCTAssertNil(defaults.object(forKey: "nourloStock_v1"))
    }

    func testHistoryMigrationPreservesPastDaysAndDailyClearOnlyClearsToday() throws {
        let name = "HistoryTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let old = FoodLogEntry(name: "Yesterday", slot: .lunch, servingG: 100, calories: 100,
                               proteinG: 4, carbsG: 12, fatG: 4, loggedAt: yesterday)
        defaults.set(try JSONEncoder().encode([old]), forKey: "foodLogEntries")
        let stock = StockStore(defaults: defaults)
        let log = FoodLogStore(defaults: defaults, stock: stock)
        XCTAssertEqual(log.allEntries.count, 1)
        XCTAssertEqual(log.totalCalories, 0)
        log.add(FoodLogEntry(name: "Today", slot: .breakfast, servingG: 150, calories: 200,
                             proteinG: 8, carbsG: 20, fatG: 6))
        XCTAssertEqual(log.totalCalories, 200)
        log.clearToday()
        let restored = FoodLogStore(defaults: defaults, stock: stock)
        XCTAssertEqual(restored.allEntries.map(\.id), [old.id])
        XCTAssertEqual(restored.totalCalories, 0)
        XCTAssertThrowsError(try stock.add(food: NutritionDatabase.load()[0], amount: -.infinity))
    }
}
