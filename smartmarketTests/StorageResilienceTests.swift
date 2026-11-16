import XCTest
@testable import smartmarket

@MainActor
final class StorageResilienceTests: XCTestCase {
    func testOneBadElementKeepsTheRestAndBacksUpRawData() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "StorageResilienceTests"))
        defer { defaults.removePersistentDomain(forName: "StorageResilienceTests") }
        let raw = Data(#"[{"id":"a","food_id":"x","food_name":"Apples","quantity":"1","estimated_price":1,"store_id":"s","store_name":"S","is_bought":false},{"id":"b"}]"#.utf8)
        defaults.set(raw, forKey: "list")
        let items = ResilientStorage.loadArray(GroceryItem.self, key: "list", defaults: defaults)
        XCTAssertEqual(items.map(\.id), ["a"])
        XCTAssertEqual(defaults.data(forKey: "list.corrupt"), raw)
    }

    func testUnreadableBlobIsBackedUp() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "StorageResilienceTests2"))
        defer { defaults.removePersistentDomain(forName: "StorageResilienceTests2") }
        let raw = Data("not json".utf8)
        defaults.set(raw, forKey: "log")
        XCTAssertTrue(ResilientStorage.loadArray(FoodLogEntry.self, key: "log", defaults: defaults).isEmpty)
        XCTAssertEqual(defaults.data(forKey: "log.corrupt"), raw)
    }

    func testPlannedGroceryRowsStayLocalThroughSync() throws {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        defer {
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            ShoppingCartService.shared.reloadFromStorage()
        }
        ShoppingCartService.shared.resetAll()
        let shared = GroceryItem(id: "manual_1", foodId: "apple", foodName: "Apples", quantity: "1",
                                 estimatedPrice: 1, storeId: "shop", storeName: "Shop", isBought: false)
        let planned = GroceryItem(id: "planned_op_rice", foodId: "rice", foodName: "Rice", quantity: "100 g",
                                  estimatedPrice: 0, storeId: "unassigned", storeName: "Choose a store",
                                  isBought: false, priceKnown: false)
        GroceryStorage.save([shared, planned])
        let snapshot = try SyncStorageAdapter.snapshot()
        XCTAssertTrue(snapshot.keys.contains("groceryList/manual_1"))
        XCTAssertFalse(snapshot.keys.contains { $0.contains("planned_") })
        // An inbound document without the planned row must not delete it.
        try SyncStorageAdapter.apply(snapshot)
        XCTAssertEqual(Set(GroceryStorage.load().map(\.id)), ["manual_1", "planned_op_rice"])
    }
}
