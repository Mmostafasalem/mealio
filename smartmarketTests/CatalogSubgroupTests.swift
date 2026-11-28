import XCTest
@testable import smartmarket

/// Favourite foods are grouped by what they are inside each category.
@MainActor
final class CatalogSubgroupTests: XCTestCase {
    private func item(_ name: String) throws -> CatalogItem { try XCTUnwrap(CatalogItem.all.first { $0.name == name }, name) }

    func testRelatedFoodsSitTogether() throws {
        XCTAssertEqual(try item("Chicken Liver").subgroup, "Chicken")
        XCTAssertEqual(try item("Ground Beef").subgroup, "Beef")
        XCTAssertEqual(try item("Hot Dogs").subgroup, "Cured meat and sausages")
        XCTAssertEqual(try item("Pineapple").subgroup, "Tropical and other", "pineapple isn't an apple")
        XCTAssertEqual(try item("Grapefruit").subgroup, "Citrus", "grapefruit isn't a grape")
        XCTAssertEqual(try item("Cream Cheese").subgroup, "Cheese")
        XCTAssertEqual(try item("Oat Milk").subgroup, "Milk")
        XCTAssertEqual(try item("Rice Noodles").subgroup, "Pasta and noodles")
        XCTAssertEqual(try item("Peanut Butter").subgroup, "Spreads and sweeteners")
        XCTAssertEqual(try item("Soy Sauce").subgroup, "Sauces")
        XCTAssertEqual(try item("Canned Tuna").subgroup, "Tinned and smoked")
        XCTAssertEqual(try item("Black Pepper").subgroup, "Salt and pepper")
        XCTAssertEqual(try item("Cayenne Pepper").subgroup, "Spices")
    }

    func testEveryItemIsInExactlyOneGroupOfItsCategory() {
        for category in CatalogCategory.allCases {
            let items = CatalogItem.all.filter { $0.category == category }
            let groups = CatalogSubgroups.groups(of: items, in: category)
            XCTAssertEqual(groups.reduce(0) { $0 + $1.items.count }, items.count, category.rawValue)
            XCTAssertEqual(Set(groups.map(\.title)).count, groups.count, "no repeated group in \(category.rawValue)")
        }
    }

    func testMeatGroupsAreTheExpectedOnes() {
        let meat = CatalogItem.all.filter { $0.category == .meat }
        XCTAssertEqual(CatalogSubgroups.groups(of: meat, in: .meat).map(\.title),
                       ["Chicken", "Pork", "Beef", "Lamb", "Turkey and duck", "Cured meat and sausages"])
    }
}
