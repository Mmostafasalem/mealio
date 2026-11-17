import XCTest
@testable import smartmarket

@MainActor
final class WeeklyGroceryPlannerTests: XCTestCase {
    private func price(_ item: CatalogItem) -> Double { 3 }

    func testItFitsTheBudgetAndCoversABalancedWeek() {
        let plan = WeeklyGroceryPlanner.plan(budget: 30, cart: [], favourites: [], mealPlan: nil, preferences: [], price: price)
        XCTAssertLessThanOrEqual(plan.total, 30)
        XCTAssertFalse(plan.lines.isEmpty)
        let categories = Set(plan.lines.map(\.item.category))
        XCTAssertTrue(categories.contains(.vegetables))
        XCTAssertTrue(categories.contains(.fruits))
        XCTAssertTrue(categories.contains(.dairy))
    }

    func testFavouritesComeFirstAndTheCartIsCounted() {
        let cart = [CartItem(id: UUID(), catalogId: "oats", name: "Oats", store: "Catalogue", price: 10, category: "grains", quantity: 2)]
        let plan = WeeklyGroceryPlanner.plan(budget: 30, cart: cart, favourites: ["salmon-fillet"], mealPlan: nil, preferences: [], price: price)
        XCTAssertEqual(plan.available, 10)
        XCTAssertEqual(plan.lines.first?.item.id, "salmon-fillet")
        XCTAssertEqual(plan.lines.first?.reason, .favourite)
        XCTAssertFalse(plan.lines.contains { $0.item.id == "oats" }, "what's in the cart isn't suggested again")
        XCTAssertLessThanOrEqual(plan.total, 10)
    }

    func testDietsAreRespected() {
        let plan = WeeklyGroceryPlanner.plan(budget: 100, cart: [], favourites: ["bacon", "chicken-breast"], mealPlan: nil,
                                             preferences: [.vegetarian], price: price)
        XCTAssertFalse(plan.lines.contains { [.meat, .seafood].contains($0.item.category) })
        XCTAssertFalse(WeeklyGroceryPlanner.allowed(CatalogItem.all.first { $0.id == "bacon" }!, [.halal]))
        XCTAssertFalse(WeeklyGroceryPlanner.allowed(CatalogItem.all.first { $0.id == "almonds" }!, [.nutAllergy]))
    }

    func testRemovedSuggestionsStayOut() {
        let first = WeeklyGroceryPlanner.plan(budget: 30, cart: [], favourites: [], mealPlan: nil, preferences: [], price: price)
        let gone = first.lines[0].item.id
        let second = WeeklyGroceryPlanner.plan(budget: 30, cart: [], favourites: [], mealPlan: nil, preferences: [], excluded: [gone], price: price)
        XCTAssertFalse(second.lines.contains { $0.item.id == gone })
    }

    func testNoSuggestionsForSmallChangeAndAtMostTwoFavouritesPerGroup() {
        let full = [CartItem(id: UUID(), catalogId: "oats", name: "Oats", store: "Catalogue", price: 38, category: "grains", quantity: 1)]
        XCTAssertTrue(WeeklyGroceryPlanner.plan(budget: 40, cart: full, favourites: [], mealPlan: nil, preferences: [], price: price).lines.isEmpty)
        let chicken: Set<String> = ["chicken-breast", "chicken-thighs", "chicken-wings", "whole-chicken", "ground-chicken"]
        let plan = WeeklyGroceryPlanner.plan(budget: 100, cart: [], favourites: chicken, mealPlan: nil, preferences: [], price: price)
        XCTAssertEqual(plan.lines.filter { $0.reason == .favourite }.count, 2)
    }
}
