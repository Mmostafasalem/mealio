import XCTest
@testable import smartmarket

/// Typing an amount, and typing your own calories, wherever a food is reviewed before logging.
@MainActor
final class PortionInputTests: XCTestCase {
    private let nuts = NutritionFood(id: "usda:2", name: "Nuts, NFS", brand: nil, basis: .grams, kcal: 610, protein: 20, carbs: 21, fat: 54,
                                     source: .usda, sourceID: "2", sourceDate: nil)
    private let soup = NutritionFood(id: "usda:3", name: "Soup", brand: nil, basis: .serving, kcal: 200, protein: 10, carbs: 20, fat: 8,
                                     source: .usda, sourceID: "3", sourceDate: nil)

    func testTypedAmountsKeepTheUnitAndStayInBounds() {
        XCTAssertEqual(PortionInput.amount("150", for: nuts), 150)
        XCTAssertEqual(PortionInput.amount("72,5 g", for: nuts), 73, "grams land on whole grams")
        XCTAssertEqual(PortionInput.amount("0", for: nuts), nuts.minimumAmount)
        XCTAssertEqual(PortionInput.amount("99999", for: nuts), nuts.maximumAmount)
        XCTAssertEqual(PortionInput.amount("1.5", for: soup), 1.5)
        XCTAssertEqual(PortionInput.amount("1.3", for: soup), 1.25, "servings land on quarters")
        XCTAssertEqual(PortionInput.amount("٢", for: soup), 2, "any keyboard's digits")
        XCTAssertNil(PortionInput.amount("lots", for: nuts))
        XCTAssertNil(PortionInput.amount("", for: nuts))
    }

    func testTypedCaloriesAreWholeAndBounded() {
        XCTAssertEqual(PortionInput.kcal("450"), 450)
        XCTAssertEqual(PortionInput.kcal("449.6"), 450)
        XCTAssertEqual(PortionInput.kcal("123456"), PortionInput.kcalRange.upperBound)
        XCTAssertNil(PortionInput.kcal("about right"))
    }

    func testOwnCaloriesScaleTheMacros() {
        let estimate = nuts.portion(100)
        XCTAssertEqual(estimate.kcal, 610, accuracy: 0.001)
        let own = PortionInput.portion(of: nuts, amount: 100, kcal: 305)
        XCTAssertEqual(own.kcal, 305)
        XCTAssertEqual(own.protein, 10, accuracy: 0.001)
        XCTAssertEqual(own.carbs, 10.5, accuracy: 0.001)
        XCTAssertEqual(own.fat, 27, accuracy: 0.001)
        // No override: the estimate.
        XCTAssertEqual(PortionInput.portion(of: nuts, amount: 50, kcal: nil).kcal, 305, accuracy: 0.001)
        // A food with no calories keeps its macros.
        let water = NutritionFood(id: "usda:4", name: "Water", brand: nil, basis: .millilitres, kcal: 0, protein: 0, carbs: 0, fat: 0,
                                  source: .usda, sourceID: "4", sourceDate: nil)
        XCTAssertEqual(PortionInput.portion(of: water, amount: 250, kcal: 5).kcal, 5)
    }

    func testOwnCaloriesFollowANewAmount() {
        XCTAssertEqual(PortionInput.rescaled(300, from: 100, to: 200), 600)
        XCTAssertEqual(PortionInput.rescaled(300, from: 100, to: 50), 150)
        XCTAssertNil(PortionInput.rescaled(nil, from: 100, to: 200))
    }

    func testALoggedEntryKeepsTheOwnValueAndSaysSo() throws {
        let own = try LogFoodIntent.makeEntry(food: nuts, amount: 100, slot: .snack, kcal: 450)
        XCTAssertEqual(own.calories, 450)
        XCTAssertEqual(own.proteinG, 20 * 450 / 610, accuracy: 0.01)
        XCTAssertEqual(own.ownCalories, true)
        XCTAssertEqual(own.amount, 100)
        let estimated = try LogFoodIntent.makeEntry(food: nuts, amount: 100, slot: .snack)
        XCTAssertEqual(estimated.calories, 610)
        XCTAssertNil(estimated.ownCalories)

        // Saved and read back, the flag survives; old entries without it still decode.
        let data = try JSONEncoder().encode([own, estimated])
        let back = try JSONDecoder().decode([FoodLogEntry].self, from: data)
        XCTAssertEqual(back.map(\.ownCalories), [true, nil])
        XCTAssertEqual(back.first?.calories, 450)
    }

    func testTheVoiceCardLogsTheTypedValues() {
        var match = VoiceFoodMatch(phrase: VoiceFoodPhrase(name: "nuts", quantity: nil, unit: nil), food: nuts, amount: 100,
                                   alternatives: [nuts], estimated: true)
        XCTAssertEqual(match.kcal, 610)
        match.kcalOverride = 500
        XCTAssertEqual(match.kcal, 500)
        XCTAssertEqual(match.estimatedKcal, 610)
        XCTAssertNotEqual(match, VoiceFoodMatch(phrase: match.phrase, food: nuts, amount: 100, alternatives: [nuts], estimated: true),
                          "an override is a change the card shows")
    }

    func testTheVoiceModelTypesAmountsAndCalories() throws {
        let model = VoiceCommandModel(photoMode: true)
        model.start(photoFoods: [VoiceFoodPhrase(name: "banana", quantity: 120, unit: .gram)])
        guard case .food(let matches, _, _) = model.plan, let first = matches.first else {
            throw XCTSkip("the catalogue found no banana here")
        }
        model.typeAmount("200", for: first)
        guard case .food(let typed, _, _) = model.plan else { return XCTFail() }
        XCTAssertEqual(typed[0].amount, 200)
        XCTAssertFalse(typed[0].estimated)
        model.typeAmount("not a number", for: typed[0])
        guard case .food(let same, _, _) = model.plan else { return XCTFail() }
        XCTAssertEqual(same[0].amount, 200, "text without a number changes nothing")

        model.typeKcal("300", for: same[0])
        guard case .food(let own, _, _) = model.plan else { return XCTFail() }
        XCTAssertEqual(own[0].kcal, 300)
        model.nudge(own[0], up: true)
        guard case .food(let nudged, _, _) = model.plan else { return XCTFail() }
        XCTAssertEqual(nudged[0].amount, 225)
        XCTAssertEqual(nudged[0].kcal, 338, "their calories follow the amount")
        model.typeKcal(nil, for: nudged[0])
        guard case .food(let back, _, _) = model.plan else { return XCTFail() }
        XCTAssertNil(back[0].kcalOverride)
        XCTAssertEqual(back[0].kcal, back[0].estimatedKcal)
    }
}
