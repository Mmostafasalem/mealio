import XCTest
@testable import smartmarket

@MainActor
final class CartStockLinkTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CartStockLinkTests")
        defaults.removePersistentDomain(forName: "CartStockLinkTests")
        UserDefaults.standard.removeObject(forKey: "cartStockLinks_v1")
    }

    func testAddingToTheCartFillsStockAndTakingOutEmptiesIt() throws {
        let stock = StockStore(defaults: defaults)
        let chicken = try XCTUnwrap(CatalogItem.all.first { $0.id == "chicken-breast" })
        XCTAssertNotNil(CartStockLink.food(for: chicken))

        CartStockLink.added(chicken, stock: stock)
        XCTAssertEqual(stock.items.count, 1)
        let pack = stock.items[0].amount
        XCTAssertGreaterThan(pack, 0)

        // A second unit adds to the same stock item.
        CartStockLink.added(chicken, stock: stock)
        XCTAssertEqual(stock.items.count, 1)
        XCTAssertEqual(stock.items[0].amount, pack * 2, accuracy: 0.001)

        CartStockLink.removed(chicken.id, stock: stock)
        XCTAssertEqual(stock.items[0].amount, pack, accuracy: 0.001)
        CartStockLink.removed(chicken.id, stock: stock)
        XCTAssertTrue(stock.items.isEmpty)
    }

    func testTakingOutNeverTouchesStockTheCartDidNotAdd() throws {
        let stock = StockStore(defaults: defaults)
        let rice = try XCTUnwrap(CatalogItem.all.first { $0.category == .grains })
        let food = try XCTUnwrap(CartStockLink.food(for: rice))
        try stock.add(food: food, amount: 250)
        CartStockLink.removed(rice.id, stock: stock)
        XCTAssertEqual(stock.items.first?.amount, 250)
    }
}
