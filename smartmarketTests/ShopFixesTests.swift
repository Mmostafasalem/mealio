import XCTest
@testable import smartmarket

/// Shop, cart, groceries and stock fixes: bought ticks, price overrides,
/// amount input, use-by days, stock pruning and reload.
@MainActor
final class ShopFixesTests: XCTestCase {

    private func withCleanDefaults(_ body: () throws -> Void) rethrows {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        defer {
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            ShoppingCartService.shared.reloadFromStorage()
        }
        ShoppingCartService.shared.resetAll()
        GroceryStorage.save([])
        try body()
    }

    private func row(_ id: String, quantity: Int, bought: Bool) -> GroceryItem {
        GroceryItem(id: id, foodId: "x", foodName: "X", quantity: String(quantity), estimatedPrice: 1,
                    storeId: "catalog", storeName: "", isBought: bought)
    }

    // MARK: Bought ticks

    func testLegacyRetailerRowsKeepTheirBoughtTickAfterMigration() throws {
        try withCleanDefaults {
            let cart = ShoppingCartService.shared
            let item = try XCTUnwrap(CatalogItem.all.first)
            let other = try XCTUnwrap(CatalogItem.all.dropFirst().first)
            let legacy = [
                CartItem(id: UUID(), catalogId: item.id, name: item.name, store: "Rimi", price: 5,
                         category: item.category.rawValue, quantity: 2),
                CartItem(id: UUID(), catalogId: other.id, name: other.name, store: "Lidl", price: 3,
                         category: other.category.rawValue, quantity: 1),
            ]
            UserDefaults.standard.set(try JSONEncoder().encode(legacy), forKey: "shoppingCart_v1")
            GroceryStorage.save([row("cart_\(item.id)_Rimi", quantity: 2, bought: true),
                                 row("cart_\(other.id)_Lidl", quantity: 1, bought: false)])
            cart.reloadFromStorage()
            let rows = GroceryStorage.load()
            let migrated = try XCTUnwrap(rows.first { $0.id == "cart_\(item.id)_Catalogue" })
            XCTAssertTrue(migrated.isBought, "A bought legacy row stays bought under its new id")
            XCTAssertFalse(try XCTUnwrap(rows.first { $0.id == "cart_\(other.id)_Catalogue" }).isBought)
            XCTAssertFalse(rows.contains { $0.id.hasSuffix("_Rimi") || $0.id.hasSuffix("_Lidl") })
        }
    }

    func testMergedLegacyRowsAreBoughtOnlyWhenEveryRowWasBought() {
        let id = "cart_milk_Catalogue"
        let mixed = ShoppingCartService.previousCartRows([row("cart_milk_Rimi", quantity: 2, bought: true),
                                                          row("cart_milk_Lidl", quantity: 1, bought: false)])
        XCTAssertEqual(mixed[id]?.allBought, false)
        XCTAssertEqual(mixed[id]?.quantity, 3)
        let all = ShoppingCartService.previousCartRows([row("cart_milk_Rimi", quantity: 2, bought: true),
                                                        row("cart_milk_Lidl", quantity: 1, bought: true)])
        XCTAssertEqual(all[id]?.allBought, true)
        XCTAssertNil(ShoppingCartService.previousCartRows([row("manual", quantity: 1, bought: true)])[id])
    }

    func testBoughtTickResetsOnlyAboveTheTickedQuantity() throws {
        try withCleanDefaults {
            let cart = ShoppingCartService.shared
            let item = try XCTUnwrap(CatalogItem.all.first)
            cart.add(item, store: .catalog); cart.add(item, store: .catalog)
            let groceries = GroceryListViewModel()
            groceries.toggleBought(try XCTUnwrap(groceries.items.first))
            XCTAssertTrue(try XCTUnwrap(GroceryStorage.load().first).isBought)
            cart.remove(item.id, store: ShopStore.catalog.name)
            XCTAssertTrue(try XCTUnwrap(GroceryStorage.load().first).isBought, "Fewer units are still all bought")
            cart.add(item, store: .catalog)
            XCTAssertTrue(try XCTUnwrap(GroceryStorage.load().first).isBought,
                          "Back to the ticked amount (net zero): still bought")
            cart.add(item, store: .catalog)
            XCTAssertFalse(try XCTUnwrap(GroceryStorage.load().first).isBought, "An extra unit is not bought yet")
            cart.remove(item.id, store: ShopStore.catalog.name)
            XCTAssertFalse(try XCTUnwrap(GroceryStorage.load().first).isBought, "Once un-ticked it stays un-ticked")
        }
    }

    func testUntickingForgetsTheTickedQuantity() throws {
        try withCleanDefaults {
            let cart = ShoppingCartService.shared
            let item = try XCTUnwrap(CatalogItem.all.first)
            cart.add(item, store: .catalog); cart.add(item, store: .catalog)
            let groceries = GroceryListViewModel()
            groceries.toggleBought(try XCTUnwrap(groceries.items.first))
            groceries.toggleBought(try XCTUnwrap(groceries.items.first))
            XCTAssertNil(UserDefaults.standard.dictionary(forKey: ShoppingCartService.tickedQuantitiesKey))
            cart.remove(item.id, store: ShopStore.catalog.name)
            groceries.loadItems()
            groceries.toggleBought(try XCTUnwrap(groceries.items.first))   // ticked at 1 unit
            cart.add(item, store: .catalog)
            XCTAssertFalse(try XCTUnwrap(GroceryStorage.load().first).isBought, "Above the 1 unit ticked")
        }
    }

    func testToggleBoughtDoesNotOverwriteRowsSyncedSinceLoad() throws {
        try withCleanDefaults {
            let cart = ShoppingCartService.shared
            let item = try XCTUnwrap(CatalogItem.all.first)
            cart.add(item, store: .catalog)
            let groceries = GroceryListViewModel()
            let stale = try XCTUnwrap(groceries.items.first)
            // Storage changes behind the view model's back (e.g. a sync pull).
            var stored = GroceryStorage.load()
            stored.append(row("synced", quantity: 1, bought: false))
            GroceryStorage.save(stored)
            groceries.toggleBought(stale)
            let after = GroceryStorage.load()
            XCTAssertTrue(after.contains { $0.id == "synced" })
            XCTAssertTrue(try XCTUnwrap(after.first { $0.id == stale.id }).isBought)
        }
    }

    func testBoughtCartCountForClearBoughtConfirmation() throws {
        try withCleanDefaults {
            let cart = ShoppingCartService.shared
            let item = try XCTUnwrap(CatalogItem.all.first)
            cart.add(item, store: .catalog)
            let groceries = GroceryListViewModel()
            groceries.toggleBought(try XCTUnwrap(groceries.items.first))
            groceries.addItem(row("manual", quantity: 1, bought: true))
            XCTAssertEqual(groceries.boughtItems.count, 2)
            XCTAssertEqual(groceries.boughtCartCount, 1)
        }
    }

    // MARK: Price overrides

    func testLoadReappliesPriceOverridesToExistingCartLines() throws {
        try withCleanDefaults {
            let cart = ShoppingCartService.shared
            let item = try XCTUnwrap(CatalogItem.all.first)
            cart.add(item, store: .catalog)
            // A correction pulled from sync lands without touching the cart.
            let key = ShoppingCartService.cartRowId(catalogId: item.id, store: ShopStore.catalog.name)
            UserDefaults.standard.set(try JSONEncoder().encode([key: 4.2]), forKey: "priceOverrides_v1")
            cart.reloadFromStorage()
            XCTAssertEqual(cart.cartItems.first?.price, 4.2)
            XCTAssertEqual(ResilientStorage.loadArray(CartItem.self, key: "shoppingCart_v1").first?.price, 4.2)
        }
    }

    func testOutOfRangeRealPriceIsIgnored() throws {
        try withCleanDefaults {
            let cart = ShoppingCartService.shared
            let item = try XCTUnwrap(CatalogItem.all.first)
            cart.add(item, store: .catalog)
            cart.setRealPrice(1e9, for: item.id, store: ShopStore.catalog.name)
            XCTAssertTrue(cart.isEstimated(item.id, store: ShopStore.catalog.name))
            XCTAssertEqual(cart.cartItems.first?.price, item.estimatedPrice(for: .catalog))
        }
    }

    // MARK: Amount input

    func testEuroInputParsesCommonFormats() {
        XCTAssertEqual(EuroInput.parse("€2"), 2)
        XCTAssertEqual(EuroInput.parse("2,50"), 2.5)
        XCTAssertEqual(EuroInput.parse("2.50"), 2.5)
        XCTAssertEqual(EuroInput.parse(" € 75.5 "), 75.5)
        XCTAssertEqual(EuroInput.parse("3 €"), 3)
        XCTAssertEqual(EuroInput.parse("2.5"), 2.5)
        XCTAssertEqual(EuroInput.parse(",5"), 0.5)
        for bad in ["", "€", "abc", "1e9", "-2", "1.2.3", "1,234.50", "inf", "nan", "٣", "5.", ",", "2,5000"] {
            XCTAssertNil(EuroInput.parse(bad), bad)
        }
    }

    func testEuroInputThousandsSeparators() {
        // A single separator followed by exactly three digits groups thousands.
        XCTAssertEqual(EuroInput.parse("1,000"), 1000)
        XCTAssertEqual(EuroInput.parse("2,000"), 2000)
        XCTAssertEqual(EuroInput.parse("€2,000"), 2000)
        XCTAssertEqual(EuroInput.parse("2.000"), 2000)
        XCTAssertEqual(EuroInput.parse("1.000"), 1000)
        XCTAssertEqual(EuroInput.parse("2.499"), 2499)
        // One or two digits after it are decimals.
        XCTAssertEqual(EuroInput.parse("2,50"), 2.5)
        XCTAssertEqual(EuroInput.parse("2,5"), 2.5)
        XCTAssertEqual(EuroInput.parse("€2"), 2)
        // Ambiguous or malformed: rejected.
        for bad in ["1,234.50", "1.234,50", "1,234,567", "1234,567", "0,500", ",500", "12,3456", "2,"] {
            XCTAssertNil(EuroInput.parse(bad), bad)
        }
        let budget = ShoppingCartService.budgetRange
        XCTAssertEqual(EuroInput.validate("2,000", in: budget), .success(2000), "The stated maximum is accepted")
        XCTAssertEqual(EuroInput.validate("2,001", in: budget), .failure(.outOfRange(budget)))
        XCTAssertEqual(EuroInput.validate("1,000", in: ShoppingCartService.priceRange),
                       .failure(.outOfRange(ShoppingCartService.priceRange)), "Not silently stored as €1.00")
        // The range text reads back through the parser.
        XCTAssertEqual(EuroInput.parse(String(EuroInput.format(budget.upperBound).dropFirst())), budget.upperBound)
    }

    func testBudgetAndPriceRanges() {
        let budget = ShoppingCartService.budgetRange
        XCTAssertEqual(EuroInput.validate("75,50", in: budget), .success(75.5))
        XCTAssertEqual(EuroInput.validate("0.01", in: budget), .failure(.outOfRange(budget)))
        XCTAssertEqual(EuroInput.validate("1000000000", in: budget), .failure(.outOfRange(budget)))
        XCTAssertEqual(EuroInput.validate("lots", in: budget), .failure(.unreadable))
        let price = ShoppingCartService.priceRange
        XCTAssertEqual(EuroInput.validate("€2", in: price), .success(2))
        XCTAssertEqual(EuroInput.validate("0", in: price), .failure(.outOfRange(price)))
        XCTAssertEqual(EuroInput.validate("501", in: price), .failure(.outOfRange(price)))
        XCTAssertEqual(EuroInput.message(for: .outOfRange(budget), example: "60"), "Enter an amount from €5 to €2000.")
        XCTAssertEqual(EuroInput.message(for: .outOfRange(price), example: "2.50"), "Enter an amount from €0.01 to €500.")
        XCTAssertEqual(EuroInput.message(for: .unreadable, example: "2.50"), "Enter an amount like 2.50.")
    }

    func testStoredBudgetOutsideRangeIsClamped() throws {
        try withCleanDefaults {
            UserDefaults.standard.set(1e9, forKey: "weeklyBudget")
            ShoppingCartService.shared.reloadFromStorage()
            XCTAssertEqual(ShoppingCartService.shared.weeklyBudget, ShoppingCartService.budgetRange.upperBound)
        }
    }

    // MARK: Stock

    private func stockDefaults() throws -> (UserDefaults, String) {
        let name = "ShopFixesTests." + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    func testUseByDayIsNotExpiredUntilTheDayAfter() throws {
        let (defaults, name) = try stockDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let calendar = Calendar.current
        let food = try XCTUnwrap(NutritionDatabase.load().first)
        let store = StockStore(defaults: defaults)
        let todayEvening = try XCTUnwrap(calendar.date(bySettingHour: 20, minute: 0, second: 0, of: Date()))
        try store.add(food: food, amount: 100, expiresAt: todayEvening)
        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(item.expiryDay(), calendar.startOfDay(for: Date()), "Saved as that calendar day")
        XCTAssertFalse(item.isExpired(today: Date()))
        let lateTonight = try XCTUnwrap(calendar.date(bySettingHour: 23, minute: 59, second: 0, of: Date()))
        XCTAssertFalse(item.isExpired(today: lateTonight))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: Date()))
        XCTAssertTrue(item.isExpired(today: tomorrow))
        try store.update(id: item.id, amount: 100, expiresAt: tomorrow)
        XCTAssertEqual(store.items.first?.expiryDay(), calendar.startOfDay(for: tomorrow))
    }

    private func gregorian(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

    func testUseByDayStaysTheSameDayAcrossTimeZones() throws {
        let auckland = try gregorian("Pacific/Auckland"), losAngeles = try gregorian("America/Los_Angeles")
        let utc = try gregorian("UTC")
        // Late evening of 10 March in Auckland is still 9 March in Los Angeles.
        let picked = try XCTUnwrap(auckland.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 23)))
        let stamp = StockItem.dayStamp(picked, calendar: auckland)
        let food = try XCTUnwrap(NutritionDatabase.load().first)
        let item = StockItem(id: UUID(), food: food, amount: 1, expiresAt: stamp, addedAt: Date())
        for cal in [auckland, losAngeles, utc] {
            let day = try XCTUnwrap(item.expiryDay(calendar: cal))
            XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: day),
                           DateComponents(year: 2026, month: 3, day: 10), cal.timeZone.identifier)
            XCTAssertEqual(day, cal.startOfDay(for: day))
            let evening = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 22)))
            XCTAssertFalse(item.isExpired(today: evening, calendar: cal))
            let nextMorning = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 1)))
            XCTAssertTrue(item.isExpired(today: nextMorning, calendar: cal))
        }
    }

    func testOldStartOfDayUseByDatesMigrateOnce() throws {
        let (defaults, name) = try stockDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let food = try XCTUnwrap(NutritionDatabase.load().first)
        let calendar = Calendar.current
        try StockStore(defaults: defaults).add(food: food, amount: 100, expiresAt: Date())
        // Rewrite the save the way older versions stored it: a local start of
        // day and no format marker.
        let raw = try XCTUnwrap(defaults.data(forKey: "nourloStock_v1"))
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        var items = try XCTUnwrap(json["items"] as? [[String: Any]])
        let oldDay = calendar.startOfDay(for: Date())
        items[0]["expiresAt"] = oldDay.timeIntervalSinceReferenceDate
        json["items"] = items
        json["expiryFormat"] = nil
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "nourloStock_v1")

        let migrated = StockStore(defaults: defaults)
        XCTAssertEqual(migrated.items.first?.expiryDay(), oldDay)
        let saved = try XCTUnwrap(defaults.data(forKey: "nourloStock_v1"))
        let savedJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(savedJSON["expiryFormat"] as? Int, StockStore.expiryFormat, "Saved in the new format")
        // Loading again changes nothing.
        XCTAssertEqual(StockStore(defaults: defaults).items.first?.expiresAt, migrated.items.first?.expiresAt)
        XCTAssertEqual(StockStore(defaults: defaults).items.first?.expiryDay(), oldDay)
    }

    func testExpiryOrderComparesDaysThenAge() throws {
        let food = try XCTUnwrap(NutritionDatabase.load().first)
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let stamp = StockItem.dayStamp(day)
        let older = StockItem(id: UUID(), food: food, amount: 1, expiresAt: stamp,
                              addedAt: Date(timeIntervalSince1970: 0))
        let newer = StockItem(id: UUID(), food: food, amount: 1, expiresAt: stamp,
                              addedAt: Date(timeIntervalSince1970: 100))
        let sooner = StockItem(id: UUID(), food: food, amount: 1,
                               expiresAt: StockItem.dayStamp(try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: day))),
                               addedAt: Date(timeIntervalSince1970: 200))
        let noDate = StockItem(id: UUID(), food: food, amount: 1, expiresAt: nil, addedAt: Date(timeIntervalSince1970: 0))
        // Soonest day first; on the same use-by day the older batch goes first.
        XCTAssertEqual([noDate, newer, older, sooner].sorted(by: StockItem.expiryOrder).map(\.id),
                       [sooner.id, older.id, newer.id, noDate.id])
    }

    func testOldMealOperationsArePrunedButLogsAreKept() throws {
        let (defaults, name) = try stockDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let food = try XCTUnwrap(NutritionDatabase.load().first)
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let store = StockStore(defaults: defaults, now: { clock })
        try store.add(food: food, amount: 1000)
        try store.consumeMeal([NutritionIngredient(food: food, amount: 10)], slot: .lunch, operationID: "old")
        clock = clock.addingTimeInterval(StockStore.mealOperationRetention - 86_400)
        try store.consumeMeal([NutritionIngredient(food: food, amount: 10)], slot: .dinner, operationID: "recent")
        XCTAssertTrue(store.hasLoggedMeal("old"))
        clock = clock.addingTimeInterval(2 * 86_400)
        try store.consumeMeal([NutritionIngredient(food: food, amount: 10)], slot: .snack, operationID: "new")
        XCTAssertFalse(store.hasLoggedMeal("old"), "Past the retention window")
        XCTAssertTrue(store.hasLoggedMeal("recent"))
        XCTAssertTrue(store.hasLoggedMeal("new"))
        XCTAssertEqual(store.logs.count, 3, "Food history is never pruned")
        let restored = StockStore(defaults: defaults, now: { clock })
        XCTAssertFalse(restored.hasLoggedMeal("old"))
        XCTAssertTrue(restored.hasLoggedMeal("new"))
    }

    func testLegacyMealOperationsWithoutDatesAgeOut() throws {
        let (defaults, name) = try stockDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"{"items":[],"logs":[],"mealOperations":["legacy"]}"#.utf8), forKey: "nourloStock_v1")
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let store = StockStore(defaults: defaults, now: { clock })
        XCTAssertTrue(store.hasLoggedMeal("legacy"))
        let food = try XCTUnwrap(NutritionDatabase.load().first)
        try store.add(food: food, amount: 10)
        XCTAssertTrue(store.hasLoggedMeal("legacy"), "Dated now on first save, not dropped")
        clock = clock.addingTimeInterval(StockStore.mealOperationRetention + 86_400)
        try store.add(food: food, amount: 10)
        XCTAssertFalse(store.hasLoggedMeal("legacy"))
    }

    func testReloadPicksUpStockWrittenToStorage() throws {
        let (defaults, name) = try stockDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let food = try XCTUnwrap(NutritionDatabase.load().first)
        let store = StockStore(defaults: defaults)
        XCTAssertTrue(store.items.isEmpty)
        let writer = StockStore(defaults: defaults)
        try writer.add(food: food, amount: 250)
        store.reload()
        XCTAssertEqual(store.items.first?.amount, 250)
        // The next save builds on the reloaded stock instead of overwriting it.
        try store.add(food: food, amount: 5)
        XCTAssertEqual(StockStore(defaults: defaults).items.map(\.amount), [250, 5])
    }
}
