import XCTest
@testable import smartmarket

/// Regression coverage for the cart <-> grocery two-way sync id round-trip.
///
/// The Groceries tab stores cart-sourced rows as `cart_<catalogId>_<store>` and,
/// when such a row is deleted or cleared, parses that id back into cart
/// coordinates to remove the matching cart line (see GroceryListViewModel
/// deleteItem/clearBought). If parsing were lossy, removals would silently fail to
/// round-trip and the cart would re-add the item on its next change.
///
/// Executed by the native smartmarketTests target in the shared scheme.
final class CartRowIdTests: XCTestCase {

    func testRoundTripsDashedCatalogId() {
        let id = ShoppingCartService.cartRowId(catalogId: "chicken-breast", store: "Rimi")
        XCTAssertEqual(id, "cart_chicken-breast_Rimi")

        let parsed = ShoppingCartService.parseCartRowId(id)
        XCTAssertEqual(parsed?.catalogId, "chicken-breast")
        XCTAssertEqual(parsed?.store, "Rimi")
    }

    func testRoundTripsMultiDashCatalogId() {
        // Catalog ids may contain several dashes; only the last underscore splits
        // off the store, so the whole dashed id must survive.
        let parsed = ShoppingCartService.parseCartRowId("cart_extra-virgin-olive-oil_Maxima")
        XCTAssertEqual(parsed?.catalogId, "extra-virgin-olive-oil")
        XCTAssertEqual(parsed?.store, "Maxima")
    }

    func testRejectsNonCartIds() {
        XCTAssertNil(ShoppingCartService.parseCartRowId("manual_123"))
        XCTAssertNil(ShoppingCartService.parseCartRowId("deal-42"))
        XCTAssertNil(ShoppingCartService.parseCartRowId("cart_"))          // no body
        XCTAssertNil(ShoppingCartService.parseCartRowId("cart_onlyid"))    // no store separator
    }
}
