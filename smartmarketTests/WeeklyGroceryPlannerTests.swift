import XCTest
@testable import smartmarket

@MainActor
final class WeeklyGroceryPlannerTests: XCTestCase {
    private func price(_ item: CatalogItem) -> Double { 3 }
    private func roles(_ plan: GroceryPlan) -> [WeeklyGroceryPlanner.Role] { plan.lines.compactMap { WeeklyGroceryPlanner.role(of: $0.item) } }

    func testWithNoFoodsPickedItSuggestsABalancedWeek() {
        let plan = WeeklyGroceryPlanner.plan(budget: 60, cart: [], favourites: [], preferences: [], price: price)
        let r = roles(GroceryPlan(lines: plan.lines.filter { $0.reason != .more }, available: plan.available))
        XCTAssertEqual(r.filter { $0 == .protein }.count, 1)
        XCTAssertEqual(r.filter { $0 == .carb }.count, 1)
        XCTAssertEqual(r.filter { $0 == .vegetable }.count, 2)
        XCTAssertEqual(r.filter { $0 == .fruit }.count, 1)
        XCTAssertEqual(r.filter { $0 == .dairy }.count, 1)
        XCTAssertTrue(plan.lines.allSatisfy { $0.reason != .favourite })
    }

    func testPickedFoodsLeadAndStaplesOnlyFillTheGaps() {
        let picked: Set<String> = ["salmon-fillet", "brown-rice", "spinach", "carrot", "apple", "kefir"]
        let plan = WeeklyGroceryPlanner.plan(budget: 60, cart: [], favourites: picked, preferences: [], price: price)
        XCTAssertEqual(Set(plan.lines.filter { $0.reason != .more }.map(\.item.id)), picked, "a balanced pick needs no staples")
        XCTAssertFalse(plan.lines.contains { $0.reason == .staple })
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
        let cart = [CartItem(id: UUID(), catalogId: "brown-rice", name: "Brown Rice", store: "Catalogue", price: 10, category: "grains", quantity: 2)]
        let plan = WeeklyGroceryPlanner.plan(budget: 40, cart: cart, favourites: [], preferences: [], price: price)
        XCTAssertEqual(plan.available, 20)
        XCTAssertFalse(plan.lines.contains { $0.reason == .staple && WeeklyGroceryPlanner.role(of: $0.item) == .carb },
                       "the rice in the cart already covers the carb")
        // Oats are breakfast; the plate still needs its own carb, as the meal plan does.
        let oats = [CartItem(id: UUID(), catalogId: "oats", name: "Oats", store: "Catalogue", price: 10, category: "grains", quantity: 2)]
        XCTAssertTrue(WeeklyGroceryPlanner.plan(budget: 40, cart: oats, favourites: [], preferences: [], price: price)
            .lines.contains { $0.reason == .staple && WeeklyGroceryPlanner.role(of: $0.item) == .carb })
        let full = [CartItem(id: UUID(), catalogId: "oats", name: "Oats", store: "Catalogue", price: 38, category: "grains", quantity: 1)]
        XCTAssertTrue(WeeklyGroceryPlanner.plan(budget: 40, cart: full, favourites: [], preferences: [], price: price).lines.isEmpty)
    }

    func testMoneyLeftAfterABalancedCartBuysMoreForTheWeek() {
        // Everything for a balanced week is already in the cart and €32 is left.
        let ids = ["chicken-breast", "brown-rice", "broccoli", "spinach", "banana", "greek-yogurt"]
        let cart = ids.map { CartItem(id: UUID(), catalogId: $0, name: $0, store: "Catalogue", price: 3, category: "x", quantity: 1) }
        let plan = WeeklyGroceryPlanner.plan(budget: 50, cart: cart, favourites: Set(ids), preferences: [], price: price)
        XCTAssertFalse(plan.lines.isEmpty, "money left means more to suggest")
        XCTAssertLessThanOrEqual(plan.total, plan.available)
        // The person's own foods (all in the cart) get one more pack each, first.
        XCTAssertEqual(Array(plan.lines.prefix(ids.count)).map(\.item.id).sorted(), ids.sorted())
        XCTAssertTrue(plan.lines.prefix(ids.count).allSatisfy { $0.reason == .another && $0.quantity == 1 })
        XCTAssertTrue(plan.lines.dropFirst(ids.count).allSatisfy { $0.reason == .more && !ids.contains($0.item.id) })
        XCTAssertEqual(Set(plan.lines.map(\.id)).count, plan.lines.count, "each food on one line")
        XCTAssertTrue(roles(plan).contains(.protein) && roles(plan).contains(.vegetable) && roles(plan).contains(.fruit))
        XCTAssertLessThan(plan.available - plan.total, WeeklyGroceryPlanner.fillUntil)
    }

    // MARK: Filling the budget

    private func realPrice(_ item: CatalogItem) -> Double { item.estimatedPrice(for: .catalog) }

    /// A cart of real catalogue foods worth `total`.
    private func cart(worth total: Double, of ids: [String]) -> [CartItem] {
        let each = total / Double(ids.count)
        return ids.map { CartItem(id: UUID(), catalogId: $0, name: $0, store: "Catalogue", price: each, category: "x", quantity: 1) }
    }

    func testABalancedCartWithElevenEurosLeftStillGetsGroceries() {
        // The owner's case: budget €50, a balanced cart of €38.97, €11.03 left.
        let ids = ["chicken-breast", "brown-rice", "broccoli", "spinach", "banana", "greek-yogurt", "free-range-eggs", "apple"]
        let basket = cart(worth: 38.97, of: ids)
        for favourites: Set<String> in [[], Set(ids), ["salmon-fillet", "kefir"]] {
            for price in [realPrice, { _ in 3.0 }] as [(CatalogItem) -> Double] {
                let plan = WeeklyGroceryPlanner.plan(budget: 50, cart: basket, favourites: favourites, preferences: [], price: price)
                XCTAssertEqual(plan.available, 11.03, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(plan.total, 6.03 - 0.001, "less than €5 is left unplanned (\(favourites))")
                XCTAssertLessThanOrEqual(plan.total, 11.03 + 0.001, "never more than what's left")
            }
        }
    }

    func testAnEmptyCartUsesTheBudget() {
        for budget in [60.0, 35.0, 120.0] {
            let plan = WeeklyGroceryPlanner.plan(budget: budget, cart: [], favourites: [], preferences: [], price: realPrice)
            XCTAssertGreaterThanOrEqual(plan.total, budget - 5, "budget \(budget)")
            XCTAssertLessThanOrEqual(plan.total, budget + 0.001, "budget \(budget)")
        }
        let picked: Set<String> = ["salmon-fillet", "brown-rice", "spinach", "carrot", "apple", "kefir"]
        let mine = WeeklyGroceryPlanner.plan(budget: 60, cart: [], favourites: picked, preferences: [], price: realPrice)
        XCTAssertGreaterThanOrEqual(mine.total, 55)
        XCTAssertLessThanOrEqual(mine.total, 60.001)
    }

    func testOwnFoodsGetMorePacksFirstButNeverMoreThanTwo() {
        let picked: Set<String> = ["salmon-fillet", "brown-rice", "spinach", "carrot", "apple", "kefir"]
        let plan = WeeklyGroceryPlanner.plan(budget: 60, cart: [], favourites: picked, preferences: [], price: price)
        for id in picked { XCTAssertEqual(plan.lines.first { $0.id == id }?.quantity, 2, id) }
        XCTAssertTrue(plan.lines.allSatisfy { $0.quantity <= WeeklyGroceryPlanner.maxPacks })
        // A pack already in the cart counts towards the two.
        let inCart = [CartItem(id: UUID(), catalogId: "salmon-fillet", name: "Salmon", store: "Catalogue", price: 3, category: "seafood", quantity: 2)]
        let again = WeeklyGroceryPlanner.plan(budget: 60, cart: inCart, favourites: ["salmon-fillet"], preferences: [], price: price)
        XCTAssertNil(again.lines.first { $0.id == "salmon-fillet" })
    }

    func testFillersAreRealFoodThatFitsTheDiet() {
        for prefs: Set<DietaryPreference> in [[], [.vegan], [.vegetarian, .glutenFree], [.halal], [.lactoseFree, .nutAllergy], [.keto]] {
            let plan = WeeklyGroceryPlanner.plan(budget: 80, cart: [], favourites: [], preferences: prefs, price: realPrice)
            XCTAssertLessThanOrEqual(plan.total, 80.001)
            for line in plan.lines {
                XCTAssertNotNil(WeeklyGroceryPlanner.role(of: line.item), "\(line.item.name) isn't a meal food")
                XCTAssertTrue(WeeklyGroceryPlanner.allowed(line.item, prefs), "\(line.item.name) breaks \(prefs)")
                XCTAssertFalse([.snacks, .condiments, .beverages, .spices, .baking, .oils].contains(line.item.category), line.item.name)
            }
        }
    }

    func testACartLeavingUnderFiveEurosGetsNoSuggestionsAndSaysSo() {
        let full = [CartItem(id: UUID(), catalogId: "oats", name: "Oats", store: "Catalogue", price: 46, category: "grains", quantity: 1)]
        let plan = WeeklyGroceryPlanner.plan(budget: 50, cart: full, favourites: [], preferences: [], price: price)
        XCTAssertTrue(plan.lines.isEmpty)
        XCTAssertEqual(plan.available, 4, accuracy: 0.001)
        XCTAssertTrue(WeeklyGroceryCard.emptyMessage(plan, removedAny: false).contains("€4.00"))
    }

    func testTheListComesCloseToTheBudgetEvenWhenEveryStapleIsInTheCart() {
        // Every staple is already bought, and half the budget is left.
        let ids = WeeklyGroceryPlanner.staples.values.flatMap { $0 }
        let cart = ids.map { CartItem(id: UUID(), catalogId: $0, name: $0, store: "Catalogue", price: 1, category: "x", quantity: 1) }
        let budget = Double(ids.count) + 31.4
        let plan = WeeklyGroceryPlanner.plan(budget: budget, cart: cart, favourites: [], preferences: [], price: price)
        XCTAssertLessThanOrEqual(plan.total, plan.available + 0.001)
        XCTAssertLessThan(plan.available - plan.total, 5, "no more than a few euros of the budget is left unplanned")
        XCTAssertTrue(plan.lines.allSatisfy { !ids.contains($0.item.id) && WeeklyGroceryPlanner.role(of: $0.item) != nil })
        // With no favourites and an empty cart the same holds.
        let fresh = WeeklyGroceryPlanner.plan(budget: 65, cart: [], favourites: [], preferences: [], price: price)
        XCTAssertLessThan(fresh.available - fresh.total, 5)
    }

    func testDietsAreRespected() {
        let plan = WeeklyGroceryPlanner.plan(budget: 100, cart: [], favourites: ["bacon", "chicken-breast"], preferences: [.vegetarian], price: price)
        XCTAssertFalse(plan.lines.contains { [.meat, .seafood].contains($0.item.category) })
        XCTAssertFalse(WeeklyGroceryPlanner.allowed(CatalogItem.all.first { $0.id == "bacon" }!, [.halal]))
    }
}
