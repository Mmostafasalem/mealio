import XCTest
@testable import smartmarket

@MainActor
final class WeeklyGroceryPlannerTests: XCTestCase {
    private func price(_ item: CatalogItem) -> Double { 3 }
    private func roles(_ plan: GroceryPlan) -> [WeeklyGroceryPlanner.Role] { plan.lines.compactMap { WeeklyGroceryPlanner.role(of: $0.item) } }

    func testWithNoFoodsPickedItSuggestsABalancedWeek() {
        let plan = WeeklyGroceryPlanner.plan(budget: 60, cart: [], favourites: [], preferences: [], price: price)
        let r = roles(plan)
        XCTAssertEqual(r.filter { $0 == .protein }.count, 1)
        XCTAssertEqual(r.filter { $0 == .carb }.count, 1)
        XCTAssertEqual(r.filter { $0 == .vegetable }.count, 2)
        XCTAssertEqual(r.filter { $0 == .fruit }.count, 1)
        XCTAssertEqual(r.filter { $0 == .dairy }.count, 1)
        XCTAssertTrue(plan.lines.allSatisfy { $0.reason == .staple })
    }

    func testPickedFoodsLeadAndStaplesOnlyFillTheGaps() {
        let picked: Set<String> = ["salmon-fillet", "brown-rice", "spinach", "carrot", "apple", "kefir"]
        let plan = WeeklyGroceryPlanner.plan(budget: 60, cart: [], favourites: picked, preferences: [], price: price)
        XCTAssertEqual(Set(plan.lines.map(\.item.id)), picked, "a balanced pick needs no staples")
        XCTAssertTrue(plan.lines.allSatisfy { $0.reason == .favourite })
    }

    func testWhenTheBudgetAllowsEveryPickedFoodIsKept() {
        let chicken: Set<String> = ["chicken-breast", "chicken-thighs", "chicken-wings", "whole-chicken", "ground-chicken"]
        let plan = WeeklyGroceryPlanner.plan(budget: 100, cart: [], favourites: chicken, preferences: [], price: price)
        XCTAssertFalse(plan.tight)
        XCTAssertEqual(plan.lines.filter { $0.reason == .favourite }.count, 5, "no two-of-a-kind limit when it all fits")
    }

    func testATightBudgetPutsTheBasicsFirstAndLimitsEachGroupToTwo() {
        let chicken: Set<String> = ["chicken-breast", "chicken-thighs", "chicken-wings", "whole-chicken", "ground-chicken"]
        let plan = WeeklyGroceryPlanner.plan(budget: 24, cart: [], favourites: chicken, preferences: [], price: price)
        XCTAssertTrue(plan.tight)
        XCTAssertLessThanOrEqual(plan.total, 24)
        XCTAssertLessThanOrEqual(plan.lines.filter { $0.item.category == .meat }.count, 2)
        XCTAssertTrue(roles(plan).contains(.vegetable) && roles(plan).contains(.fruit) && roles(plan).contains(.dairy))
    }

    func testTheCartCountsAndSmallChangeSuggestsNothing() {
        let cart = [CartItem(id: UUID(), catalogId: "oats", name: "Oats", store: "Catalogue", price: 10, category: "grains", quantity: 2)]
        let plan = WeeklyGroceryPlanner.plan(budget: 40, cart: cart, favourites: [], preferences: [], price: price)
        XCTAssertEqual(plan.available, 20)
        XCTAssertFalse(roles(plan).contains(.carb), "the oats in the cart already cover the carb")
        let full = [CartItem(id: UUID(), catalogId: "oats", name: "Oats", store: "Catalogue", price: 38, category: "grains", quantity: 1)]
        XCTAssertTrue(WeeklyGroceryPlanner.plan(budget: 40, cart: full, favourites: [], preferences: [], price: price).lines.isEmpty)
    }

    func testDietsAreRespected() {
        let plan = WeeklyGroceryPlanner.plan(budget: 100, cart: [], favourites: ["bacon", "chicken-breast"], preferences: [.vegetarian], price: price)
        XCTAssertFalse(plan.lines.contains { [.meat, .seafood].contains($0.item.category) })
        XCTAssertFalse(WeeklyGroceryPlanner.allowed(CatalogItem.all.first { $0.id == "bacon" }!, [.halal]))
    }
}
