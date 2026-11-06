import XCTest
@testable import smartmarket

@MainActor
final class CartIntegrationTests: XCTestCase {
    func testPriceCorrectionDoesNotChangeAnotherStore() throws {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        defer {
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            ShoppingCartService.shared.reloadFromStorage()
        }
        let cart = ShoppingCartService.shared
        cart.resetAll()
        let item = try XCTUnwrap(CatalogItem.all.first)
        let rimi = try XCTUnwrap(ShopStore.all.first { $0.id == "rimi" })
        let lidl = try XCTUnwrap(ShopStore.all.first { $0.id == "lidl" })
        cart.add(item, store: rimi)
        cart.add(item, store: lidl)
        let lidlEstimate = item.estimatedPrice(for: lidl)
        cart.setRealPrice(9.25, for: item.id, store: rimi.name)
        XCTAssertEqual(cart.cartItems.first { $0.store == rimi.name }?.price, 9.25)
        XCTAssertEqual(cart.cartItems.first { $0.store == lidl.name }?.price, lidlEstimate)
        XCTAssertEqual(cart.effectivePrice(for: item, store: lidl), lidlEstimate)
        XCTAssertFalse(cart.isEstimated(item.id, store: rimi.name))
        XCTAssertTrue(cart.isEstimated(item.id, store: lidl.name))
        cart.setRealPrice(3.75, for: item.id, store: lidl.name)
        cart.reloadFromStorage()
        XCTAssertEqual(cart.effectivePrice(for: item, store: rimi), 9.25)
        XCTAssertEqual(cart.effectivePrice(for: item, store: lidl), 3.75)
        XCTAssertFalse(cart.isEstimated(item.id, store: rimi.name))
        XCTAssertFalse(cart.isEstimated(item.id, store: lidl.name))
    }

    func testUndoUsesOnlyMatchingStoreCorrection() throws {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        defer {
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            ShoppingCartService.shared.reloadFromStorage()
        }
        let cart = ShoppingCartService.shared
        cart.resetAll()
        let item = try XCTUnwrap(CatalogItem.all.first)
        let rimi = try XCTUnwrap(ShopStore.all.first { $0.id == "rimi" })
        let lidl = try XCTUnwrap(ShopStore.all.first { $0.id == "lidl" })
        cart.add(item, store: rimi)
        cart.add(item, store: rimi)
        cart.add(item, store: lidl)
        let removed = cart.cartItems
        cart.clear()
        cart.setRealPrice(9.25, for: item.id, store: rimi.name)
        cart.restoreRemovedLines(removed)
        XCTAssertEqual(cart.cartItems.first { $0.store == rimi.name }?.price, 9.25)
        XCTAssertEqual(cart.quantity(of: item.id, store: rimi.name), 2)
        XCTAssertEqual(cart.cartItems.first { $0.store == lidl.name }?.price, item.estimatedPrice(for: lidl))
    }

    func testLegacyCorrectionsStayStoredWithoutVerifyingAnyStore() throws {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        defer {
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            ShoppingCartService.shared.reloadFromStorage()
        }
        let cart = ShoppingCartService.shared
        cart.resetAll()
        let item = try XCTUnwrap(CatalogItem.all.first)
        let rimi = try XCTUnwrap(ShopStore.all.first { $0.id == "rimi" })
        let lidl = try XCTUnwrap(ShopStore.all.first { $0.id == "lidl" })
        cart.add(item, store: rimi)
        cart.setRealPrice(8.50, for: item.id, store: rimi.name)
        // Model the old release: an existing cart price and a catalog-only correction.
        UserDefaults.standard.set(try JSONEncoder().encode([item.id: 8.50]), forKey: "priceOverrides_v1")
        cart.reloadFromStorage()
        XCTAssertEqual(cart.cartItems.count, 1)
        XCTAssertEqual(cart.cartItems.first?.price, 8.50)
        for store in [rimi, lidl] {
            XCTAssertTrue(cart.isEstimated(item.id, store: store.name))
            XCTAssertEqual(cart.effectivePrice(for: item, store: store), item.estimatedPrice(for: store))
        }
        let removed = cart.cartItems
        cart.clear()
        cart.setRealPrice(9.25, for: item.id, store: lidl.name)
        cart.restoreRemovedLines(removed)
        XCTAssertEqual(cart.cartItems.first?.price, 8.50)
        cart.add(item, store: lidl)
        XCTAssertEqual(cart.cartItems.first { $0.store == lidl.name }?.price, 9.25)
        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: "priceOverrides_v1"))
        let stored = try JSONDecoder().decode([String: Double].self, from: data)
        XCTAssertEqual(stored[item.id], 8.50)
        XCTAssertEqual(stored["cart_\(item.id)_Lidl"], 9.25)
        // Exercise the existing private Sync snapshot/apply validation unchanged.
        let snapshot = try SyncStorageAdapter.snapshot()
        try SyncStorageAdapter.apply(snapshot)
        XCTAssertEqual(cart.priceOverrides, stored)
        XCTAssertTrue(cart.isEstimated(item.id, store: rimi.name))
        XCTAssertFalse(cart.isEstimated(item.id, store: lidl.name))
    }

    func testInvalidCorrectionsDoNotChangePricesOrPersistence() throws {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        defer {
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            ShoppingCartService.shared.reloadFromStorage()
        }
        let cart = ShoppingCartService.shared
        cart.resetAll()
        let item = try XCTUnwrap(CatalogItem.all.first)
        let store = try XCTUnwrap(ShopStore.all.first)
        cart.add(item, store: store)
        for invalid in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            cart.setRealPrice(invalid, for: item.id, store: store.name)
            XCTAssertTrue(cart.isEstimated(item.id, store: store.name))
            XCTAssertEqual(cart.cartItems.first?.price, item.estimatedPrice(for: store))
        }
        cart.setRealPrice(9.25, for: item.id, store: store.name)
        let stored = UserDefaults.standard.data(forKey: "priceOverrides_v1")
        for invalid in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            cart.setRealPrice(invalid, for: item.id, store: store.name)
            XCTAssertEqual(cart.cartItems.first?.price, 9.25)
            XCTAssertFalse(cart.isEstimated(item.id, store: store.name))
            XCTAssertEqual(UserDefaults.standard.data(forKey: "priceOverrides_v1"), stored)
        }
        // Invalid scoped values imported from storage must not verify a store either.
        UserDefaults.standard.set(try JSONEncoder().encode(["cart_\(item.id)_\(store.name)": -1.0]), forKey: "priceOverrides_v1")
        cart.reloadFromStorage()
        XCTAssertTrue(cart.isEstimated(item.id, store: store.name))
        XCTAssertEqual(cart.effectivePrice(for: item, store: store), item.estimatedPrice(for: store))
    }

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

    func testCartBackedGroceryDeletionCanBeUndoneWithQuantityAndBoughtState() throws {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        defer {
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            ShoppingCartService.shared.reloadFromStorage()
        }
        let cart = ShoppingCartService.shared
        cart.resetAll(); GroceryStorage.save([])
        let item = try XCTUnwrap(CatalogItem.all.first)
        let store = try XCTUnwrap(ShopStore.all.first)
        cart.add(item, store: store); cart.add(item, store: store)
        let groceries = GroceryListViewModel()
        groceries.toggleBought(try XCTUnwrap(groceries.items.first))
        groceries.deleteItem(try XCTUnwrap(groceries.items.first))
        XCTAssertTrue(cart.cartItems.isEmpty)
        groceries.undoDelete()
        XCTAssertEqual(cart.quantity(of: item.id, store: store.name), 2)
        XCTAssertTrue(try XCTUnwrap(GroceryStorage.load().first).isBought)
    }

    func testUndoMergesWithNewCartEditsAndUsesCorrectedPrice() throws {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        defer {
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            ShoppingCartService.shared.reloadFromStorage()
        }
        let cart = ShoppingCartService.shared
        cart.resetAll(); GroceryStorage.save([])
        let item = try XCTUnwrap(CatalogItem.all.first)
        let store = try XCTUnwrap(ShopStore.all.first)
        cart.add(item, store: store); cart.add(item, store: store)
        let groceries = GroceryListViewModel()
        groceries.deleteItem(try XCTUnwrap(groceries.items.first))
        cart.add(item, store: store)
        cart.setRealPrice(9.25, for: item.id, store: store.name)
        groceries.undoDelete()
        XCTAssertEqual(cart.quantity(of: item.id, store: store.name), 3)
        XCTAssertEqual(cart.cartItems.first?.price, 9.25)
    }

    func testClearBoughtUndoRestoresBothManualAndCartRows() throws {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        defer {
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            ShoppingCartService.shared.reloadFromStorage()
        }
        let cart = ShoppingCartService.shared
        cart.resetAll(); GroceryStorage.save([])
        let item = try XCTUnwrap(CatalogItem.all.first)
        let store = try XCTUnwrap(ShopStore.all.first)
        cart.add(item, store: store)
        let groceries = GroceryListViewModel()
        groceries.toggleBought(try XCTUnwrap(groceries.items.first))
        groceries.addItem(GroceryItem(id: "manual-undo", foodId: "apple", foodName: "Apples",
            quantity: "2", estimatedPrice: 2, storeId: "shop", storeName: "Shop", isBought: true))
        groceries.clearBought()
        XCTAssertTrue(GroceryStorage.load().isEmpty)
        groceries.undoDelete()
        XCTAssertEqual(GroceryStorage.load().count, 2)
        XCTAssertTrue(GroceryStorage.load().allSatisfy(\.isBought))
        XCTAssertEqual(cart.quantity(of: item.id, store: store.name), 1)
    }

    func testCancelledExpiryCannotHideNewUndoAndResetInvalidatesUndo() async throws {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        let generation = AppState.shared.dataGeneration
        defer {
            AppState.shared.dataGeneration = generation
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            ShoppingCartService.shared.reloadFromStorage()
        }
        ShoppingCartService.shared.resetAll()
        let a = GroceryItem(id: "a", foodId: "apple", foodName: "Apples", quantity: "1",
            estimatedPrice: 1, storeId: "shop", storeName: "Shop", isBought: false)
        let b = GroceryItem(id: "b", foodId: "banana", foodName: "Bananas", quantity: "1",
            estimatedPrice: 1, storeId: "shop", storeName: "Shop", isBought: false)
        GroceryStorage.save([a,b])
        let groceries = GroceryListViewModel()
        groceries.deleteItem(a)
        await Task.yield()
        groceries.deleteItem(b)
        await Task.yield(); await Task.yield()
        XCTAssertEqual(groceries.undoMessage, "Bananas removed")
        AppState.shared.dataGeneration = UUID()
        groceries.undoDelete()
        XCTAssertTrue(GroceryStorage.load().isEmpty)
        XCTAssertNil(groceries.undoMessage)
    }

    func testQuickActionsSearchIsLocalAndFindsDestinations() {
        XCTAssertEqual(MealioQuickAction.matching(" CART "), [.cart])
        XCTAssertEqual(MealioQuickAction.matching("checklist"), [.groceries])
        XCTAssertEqual(MealioQuickAction.matching("nothing-matches"), [])
        XCTAssertEqual(MealioQuickAction.matching("").count, 8)
    }

    func testQuickLoggerStartsWithSavedMealPlanWithoutNetwork() {
        let previous = AppState.shared.weeklyMealPlan
        defer { AppState.shared.weeklyMealPlan = previous }
        AppState.shared.weeklyMealPlan = FallbackData.mealPlan(targetKcal: 2000, pantry: [])
        let logger = HomeViewModel()
        XCTAssertFalse(logger.plannedEntries(for: .breakfast).isEmpty)
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
