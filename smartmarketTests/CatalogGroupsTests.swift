import XCTest
@testable import smartmarket

final class CatalogGroupsTests: XCTestCase {

    private func groups(_ cat: CatalogCategory) -> [CatalogGroup] {
        cat.groups(of: CatalogItem.all.filter { $0.category == cat })
    }

    func testMeatIsGroupedByAnimal() {
        let g = Dictionary(uniqueKeysWithValues: groups(.meat).map { ($0.name, Set($0.items.map(\.name))) })
        XCTAssertEqual(g["Chicken"], ["Chicken Breast", "Chicken Thighs", "Chicken Wings", "Whole Chicken", "Ground Chicken", "Chicken Liver"])
        XCTAssertEqual(g["Pork"], ["Pork Tenderloin", "Pork Belly", "Pork Ribs", "Pork Chops", "Ground Pork", "Bacon", "Ham"])
        XCTAssertEqual(g["Beef"], ["Beef Steak", "Ground Beef", "Beef Ribs"])
    }

    func testEveryFoodIsInExactlyOneGroup() {
        for cat in CatalogCategory.allCases {
            let items = CatalogItem.all.filter { $0.category == cat }
            let grouped = groups(cat).flatMap(\.items)
            XCTAssertEqual(grouped.count, items.count, cat.rawValue)
            XCTAssertEqual(Set(grouped.map(\.id)), Set(items.map(\.id)), cat.rawValue)
        }
    }

    @MainActor func testSelectAllPicksASectionAndATapClearsIt() {
        let vm = OnboardingViewModel()
        let meat = CatalogItem.all.filter { $0.category == .meat }
        vm.toggleAll(meat)
        XCTAssertEqual(vm.favoritesCount, meat.count)
        vm.toggleAll(meat)
        XCTAssertEqual(vm.favoritesCount, 0)
    }
}

final class MealSplitAdjustTests: XCTestCase {
    func testRaisingAMealTakesFromTheBiggestOtherAndStaysAt100() {
        let s = MealSplit.balanced                       // 25 · 35 · 30 · 10
        let up = s.adjusting(.breakfast, by: 5)
        XCTAssertEqual(up, MealSplit(breakfast: 30, lunch: 30, dinner: 30, snack: 10))
        let down = s.adjusting(.dinner, by: -5)
        XCTAssertEqual(down, MealSplit(breakfast: 25, lunch: 40, dinner: 25, snack: 10))
        var x = s
        for _ in 0..<20 { if let n = x.adjusting(.snack, by: -5) { x = n } }
        XCTAssertEqual(x.snack, 0)
        XCTAssertEqual(x.total, 100)
        XCTAssertNil(MealSplit(breakfast: 5, lunch: 50, dinner: 45, snack: 0).adjusting(.breakfast, by: -5))
        XCTAssertTrue(x.isValid)
    }
}
