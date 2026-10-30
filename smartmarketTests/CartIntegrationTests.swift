import XCTest
@testable import smartmarket

@MainActor
final class CartIntegrationTests: XCTestCase {
    func testClearBoughtRemovesCartLineAndItDoesNotReturnOnNextEdit() throws {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        defer {
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            ShoppingCartService.shared.reloadFromStorage()
        }
        let cart = ShoppingCartService.shared
        cart.resetAll()
        GroceryStorage.save([])
        let item = try XCTUnwrap(CatalogItem.all.first)
        let store = try XCTUnwrap(ShopStore.all.first)
        cart.add(item, store: store)
        let groceries = GroceryListViewModel()
        let row = try XCTUnwrap(groceries.items.first)
        groceries.toggleBought(row)
        groceries.clearBought()
        XCTAssertTrue(cart.cartItems.isEmpty)
        XCTAssertTrue(GroceryStorage.load().isEmpty)
        let another = try XCTUnwrap(CatalogItem.all.dropFirst().first)
        cart.add(another, store: store)
        XCTAssertFalse(GroceryStorage.load().contains { $0.foodId == item.id })
    }

    func testFoodLogClearAllRemovesBothEntriesAndRecentIDs() {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        defer {
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            FoodLogStore.shared.reload()
        }
        let log = FoodLogStore.shared
        log.add(FoodLogEntry(foodId: "apple", name: "Apple", slot: .snack, servingG: 100,
                            calories: 52, proteinG: 0.3, carbsG: 14, fatG: 0.2))
        XCTAssertFalse(log.recentFoodIDs.isEmpty)
        log.clearAll()
        XCTAssertTrue(log.entries.isEmpty)
        XCTAssertTrue(log.recentFoodIDs.isEmpty)
        XCTAssertNil(UserDefaults.standard.object(forKey: "foodLogEntries"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "recentFoodIDs"))
    }
}
