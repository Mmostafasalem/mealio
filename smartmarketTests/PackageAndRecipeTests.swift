import XCTest
import UIKit
@testable import smartmarket

/// G4 and G5: pieces per package and Open Food Facts package data (from two real
/// products saved as fixtures; no network), and G1: recipes read from text or a page.
@MainActor
final class PackageAndRecipeTests: XCTestCase {

    private func fixture(_ code: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "off-" + code, withExtension: "json"), "fixture off-\(code).json")
        return try Data(contentsOf: url)
    }

    private func product(_ code: String) throws -> [String: Any] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture(code)) as? [String: Any])
        return try XCTUnwrap(root["product"] as? [String: Any])
    }

    // MARK: Open Food Facts (fixtures fetched once with curl on 27 Nov 2026)

    /// Betty Crocker Whipped Cream Cheese Frosting: 340 g tub, "1 serving (24 g)", 110 kcal a serving.
    func testFrostingReadsPackageServingAndPer100() throws {
        let food = try XCTUnwrap(BarcodeLookupService.parse(fixture("0016000374201"), code: "0016000374201"))
        XCTAssertEqual(food.basis, .grams)
        XCTAssertEqual(food.packageAmount, 340)
        XCTAssertEqual(food.servingAmount, 24)
        XCTAssertEqual(food.servingLabel, "1 serving (24 g)")
        XCTAssertNil(food.pieceAmount, "a serving is not a piece")
        // Per 100 g as on the product (458.3 kcal), so a 24 g serving is the label's 110 kcal.
        XCTAssertEqual(food.kcal, 458.333, accuracy: 0.01)
        XCTAssertEqual(food.portion(24).kcal, 110, accuracy: 0.5)
        XCTAssertEqual(food.portion(24).carbs, 14, accuracy: 0.05)
        XCTAssertEqual(food.portion(24).fat, 6, accuracy: 0.05)
        // Shown to one decimal, never 58.3333333333333.
        XCTAssertEqual(ServingDetailView.oneDecimal(food.carbs), "58.3")
        XCTAssertEqual(ServingDetailView.oneDecimal(food.kcal), "458.3")
    }

    /// Président Emmental 250 g, serving "30g": 370 kcal per 100 g, 111 kcal a serving.
    func testCheeseReadsPackageAndServing() throws {
        let food = try XCTUnwrap(BarcodeLookupService.parse(fixture("3228021170022"), code: "3228021170022"))
        XCTAssertEqual(food.packageAmount, 250)
        XCTAssertEqual(food.servingAmount, 30)
        XCTAssertEqual(food.kcal, 370)
        XCTAssertEqual(food.protein, 27)
        XCTAssertEqual(food.portion(30).kcal, 111, accuracy: 0.01)
        // The search path reads the same product the same way.
        let searched = try XCTUnwrap(NutritionFood.openFoodFacts(product("3228021170022")))
        XCTAssertEqual(searched.packageAmount, 250)
        XCTAssertEqual(searched.servingAmount, 30)
        XCTAssertEqual(searched.kcal, food.kcal)
    }

    /// No package size on the product: nothing invented; "2 tbsp (34 g) (34 g)" is a 34 g serving.
    func testFrostingWithoutPackageSize() throws {
        let food = try XCTUnwrap(BarcodeLookupService.parse(fixture("0016000437760"), code: "0016000437760"))
        XCTAssertNil(food.packageAmount)
        XCTAssertEqual(food.servingAmount, 34)
        XCTAssertEqual(food.portion(34).kcal, 130, accuracy: 0.5)
    }

    func testPerServingOnlyLabelsAndKilojoules() {
        // Entered per serving only: the _100g values are worked out from the serving.
        let perServing = OFFPackage.per100(["energy-kcal_serving": 110, "proteins_serving": 0, "carbohydrates_serving": 14, "fat_serving": 6],
                                           servingAmount: 24)
        XCTAssertEqual(perServing?.kcal ?? 0, 458.33, accuracy: 0.01)
        XCTAssertEqual(perServing?.carbs ?? 0, 58.33, accuracy: 0.01)
        // OFF keeps `energy_100g` in kJ.
        let kj = OFFPackage.per100(["energy_100g": 1532, "proteins_100g": 27, "carbohydrates_100g": 0.5, "fat_100g": 29], servingAmount: nil)
        XCTAssertEqual(kj?.kcal ?? 0, 366.2, accuracy: 0.1)
        // A boolean is never a number.
        XCTAssertNil(OFFPackage.per100(["energy-kcal_100g": true, "proteins_100g": 1, "carbohydrates_100g": 1, "fat_100g": 1], servingAmount: nil))
    }

    func testServingSizeText() {
        let slice = OFFPackage.readServing("1 slice (21 g)", basis: .grams)
        XCTAssertEqual(slice.count, 1)
        XCTAssertEqual(slice.piece, "slice")
        XCTAssertEqual(slice.amount, 21)
        let cookies = OFFPackage.readServing("2 cookies (28g)", basis: .grams)
        XCTAssertEqual(cookies.piece, "cookie")
        XCTAssertEqual(cookies.amount, 28)
        let spoon = OFFPackage.readServing("2 tbsp (24 g)", basis: .grams)
        XCTAssertNil(spoon.piece)
        XCTAssertEqual(spoon.amount, 24)
        XCTAssertEqual(OFFPackage.readServing("330 ml", basis: .millilitres).amount, 330)
        XCTAssertEqual(OFFPackage.inBasis(1, unit: "kg", basis: .grams), 1000)
        XCTAssertNil(OFFPackage.inBasis(1, unit: "ml", basis: .grams), "no density is assumed")
    }

    func testSlicedBreadGetsPiecesFromItsLabel() {
        var food = LoggingStockTests.food("Sliced bread", id: 2001)
        OFFPackage.apply(["product_quantity": 500, "product_quantity_unit": "g", "serving_size": "2 slices (50 g)", "serving_quantity": 50], to: &food)
        XCTAssertEqual(food.pieceName, "slice")
        XCTAssertEqual(food.pieceAmount, 25)
        XCTAssertEqual(food.piecesPerPackage, 20)
        var cans = LoggingStockTests.food("Cola", id: 2002, basis: .millilitres)
        OFFPackage.apply(["product_quantity": 1980, "product_quantity_unit": "ml", "number_of_units": 6], to: &cans)
        XCTAssertEqual(cans.pieceAmount, 330)
    }

    // MARK: Pieces

    func testPiecesTypedWhenAddingToStock() {
        let samosas = LoggingStockTests.food("Samosa", id: 2003, kcal: 260).withPieces(6, name: "samosa", package: 300)
        XCTAssertEqual(samosas.pieceAmount, 50)
        XCTAssertEqual(samosas.pieceName, "samosa")
        XCTAssertEqual(samosas.piecesPerPackage, 6)
        // Logging two of them: 100 g and 260 kcal.
        XCTAssertEqual(samosas.portion(2 * (samosas.pieceAmount ?? 0)).kcal, 260)
        // No pieces typed: the food stays as it was, with the package size.
        let plain = LoggingStockTests.food("Rice", id: 2004).withPieces(nil, name: nil, package: 1000)
        XCTAssertNil(plain.pieceAmount)
        XCTAssertEqual(plain.packageAmount, 1000)
    }

    func testVoiceCardCountsPiecesAndTheCountChangesTheGrams() throws {
        let burger = LoggingStockTests.food("Veggie burger, on bun", id: 2005, kcal: 224)
        let plan = VoiceCommandRunner.plan(for: .logFood(items: [VoiceFoodPhrase(name: "veggie burgers", quantity: 2, unit: nil)], slot: .lunch),
                                           search: { _ in [burger] })
        guard case .food(let matches, _, _) = plan, var match = matches.first else { return XCTFail() }
        XCTAssertEqual(match.count, 2)
        XCTAssertEqual(match.pieceName, "veggie burger")
        XCTAssertEqual(match.summary, "2 × veggie burger · 220 g · 493 kcal")
        match.amount = 3 * (match.pieceAmount ?? 0)
        XCTAssertEqual(match.summary, "3 × veggie burger · 330 g · 739 kcal")
        // Slices said out loud are counted as slices.
        let bread = LoggingStockTests.food("Bread, white", id: 2006, kcal: 266)
        let pieces = VoiceAmounts.pieces(for: VoiceFoodPhrase(name: "bread", quantity: 3, unit: .slice), food: bread, amount: 90)
        XCTAssertEqual(pieces.0, 30)
        XCTAssertEqual(pieces.1, "slice")
        // Weighed with no pieces known: just grams.
        XCTAssertNil(VoiceAmounts.pieces(for: VoiceFoodPhrase(name: "rice", quantity: 150, unit: .gram), food: bread, amount: 150).0)
    }

    func testPieceWords() {
        XCTAssertEqual(PieceWords.plural("slice"), "slices")
        XCTAssertEqual(PieceWords.plural("patty"), "patties")
        XCTAssertEqual(PieceWords.plural("sandwich"), "sandwiches")
        XCTAssertEqual(PieceWords.count(1, "can"), "1 can")
        XCTAssertEqual(PieceWords.count(2.5, "can"), "2.5 cans")
    }

    // MARK: Recipes

    func testIngredientLines() throws {
        let milk = try XCTUnwrap(RecipeTextParser.line("1 ½ cups whole milk"))
        XCTAssertEqual(milk.quantity, 1.5)
        XCTAssertEqual(milk.unit, "cup")
        XCTAssertEqual(milk.name, "whole milk")
        let pasta = try XCTUnwrap(RecipeTextParser.line("- 200g spaghetti"))
        XCTAssertEqual(pasta.quantity, 200)
        XCTAssertEqual(pasta.unit, "g")
        XCTAssertEqual(pasta.name, "spaghetti")
        let onions = try XCTUnwrap(RecipeTextParser.line("2 large onions, finely chopped"))
        XCTAssertEqual(onions.quantity, 2)
        XCTAssertNil(onions.unit)
        XCTAssertEqual(onions.name, "onions")
        let range = try XCTUnwrap(RecipeTextParser.line("2-3 tbsp olive oil"))
        XCTAssertEqual(range.quantity, 2.5)
        XCTAssertEqual(range.unit, "tbsp")
        let salt = try XCTUnwrap(RecipeTextParser.line("Salt to taste"))
        XCTAssertNil(salt.quantity)
        XCTAssertEqual(salt.name, "Salt")
        XCTAssertEqual(try XCTUnwrap(RecipeTextParser.line("3/4 tsp baking soda")).quantity, 0.75)
        XCTAssertEqual(try XCTUnwrap(RecipeTextParser.line("a pinch of salt")).unit, "pinch")
    }

    func testWholeRecipeTextWithHeadings() {
        let text = """
        Banana pancakes
        Makes 8 servings
        Ingredients
        2 ripe bananas
        2 eggs
        1 cup flour
        250 ml milk
        Method
        1. Mash the bananas.
        2. Mix and fry.
        """
        let recipe = RecipeTextParser.parse(text)
        XCTAssertEqual(recipe.title, "Banana pancakes")
        XCTAssertEqual(recipe.servings, 8)
        XCTAssertEqual(recipe.lines.map(\.name), ["ripe bananas", "eggs", "flour", "milk"])
    }

    func testGramsFromCupsSpoonsAndCounts() {
        let flour = RecipeLine(text: "1 cup flour", quantity: 1, unit: "cup", name: "flour")
        XCTAssertEqual(RecipeAmounts.grams(for: flour, pieceWeight: nil)?.grams, 125)
        let oil = RecipeLine(text: "2 tbsp olive oil", quantity: 2, unit: "tbsp", name: "olive oil")
        XCTAssertEqual(RecipeAmounts.grams(for: oil, pieceWeight: nil)?.grams ?? 0, 27.25, accuracy: 0.01)
        let eggs = RecipeLine(text: "2 eggs", quantity: 2, unit: nil, name: "eggs")
        XCTAssertEqual(RecipeAmounts.grams(for: eggs, pieceWeight: 50)?.grams, 100)
        XCTAssertEqual(RecipeAmounts.grams(for: eggs, pieceWeight: 50)?.estimated, true)
        let weighed = RecipeLine(text: "1 kg potatoes", quantity: 1, unit: "kg", name: "potatoes")
        XCTAssertEqual(RecipeAmounts.grams(for: weighed, pieceWeight: nil)?.estimated, false)
        XCTAssertNil(RecipeAmounts.grams(for: RecipeLine(text: "salt", quantity: nil, unit: nil, name: "salt"), pieceWeight: nil))
    }

    func testRecipeFromAPagesJSONLD() throws {
        let html = """
        <html><head><title>x</title>
        <script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"WebPage","name":"x"},
        {"@type":["Recipe"],"name":"Tomato &amp; basil soup","recipeYield":["4","4 bowls"],
        "recipeIngredient":["800 g tomatoes","1 onion","2 tbsp olive oil","&#189; tsp salt"]}]}</script>
        </head><body><p>Not this</p></body></html>
        """
        let recipe = try XCTUnwrap(RecipeWebReader.recipe(fromHTML: html))
        XCTAssertEqual(recipe.title, "Tomato & basil soup")
        XCTAssertEqual(recipe.servings, 4)
        XCTAssertEqual(recipe.lines.count, 4)
        XCTAssertEqual(recipe.lines[3].quantity, 0.5)
        XCTAssertNil(RecipeWebReader.recipe(fromHTML: "<html><body>1 cup rice</body></html>"))
        XCTAssertTrue(RecipeWebReader.text(fromHTML: "<ul><li>1 cup rice</li><li>2 eggs</li></ul>").contains("1 cup rice\n2 eggs"))
    }

    func testScalingTheWholeRecipe() {
        let flour = LoggingStockTests.food("Wheat flour, white, all-purpose", id: 2007, kcal: 364)
        let draft = RecipeDraft(ParsedRecipe(title: "Bread", servings: 8, lines: [RecipeLine(text: "500 g flour", quantity: 500, unit: "g", name: "flour")]),
                                search: { _ in [flour] })
        XCTAssertEqual(draft.total.kcal, 1820, accuracy: 0.01)
        XCTAssertEqual(draft.perServing.kcal, 227.5, accuracy: 0.01)
        draft.scale = 2
        XCTAssertEqual(draft.ingredients.first?.amount, 1000)
        XCTAssertEqual(draft.servingsMade, 16)
        XCTAssertEqual(draft.perServing.kcal, 227.5, accuracy: 0.01, "doubling makes twice the servings, not bigger ones")
        draft.scale = 0.5
        draft.eaten = 2
        XCTAssertEqual(draft.servingsMade, 4)
        XCTAssertEqual(draft.perServing.kcal * draft.eaten, 455, accuracy: 0.01)
        // Fewer servings than written: each is bigger.
        draft.scale = 1
        draft.servings = 4
        XCTAssertEqual(draft.perServing.kcal, 455, accuracy: 0.01)
        let food = draft.food()
        XCTAssertEqual(food?.basis, .serving)
        XCTAssertEqual(food?.source, .recipe)
        XCTAssertEqual(food?.isValid, true)
    }

    // MARK: Meal photos to clarify

    func testPhotoIsKeptToClarifyAndRemovedOnceLogged() throws {
        let suite = "PendingMeals." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let store = PendingMealStore(defaults: defaults, directory: folder)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1500)).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1500))
        }
        let taken = Date().addingTimeInterval(-600)
        let meal = try XCTUnwrap(store.add(image, slot: .lunch, at: taken))
        let data = try XCTUnwrap(store.imageData(for: meal))
        XCTAssertEqual(Array(data.prefix(3)), [0xFF, 0xD8, 0xFF], "a JPEG")
        let saved = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(saved.size.width, saved.size.height) * saved.scale, 768)
        // Still there after a relaunch, with its time.
        let reopened = PendingMealStore(defaults: defaults, directory: folder)
        XCTAssertEqual(reopened.meals.first?.id, meal.id)
        XCTAssertEqual(reopened.meals.first?.takenAt.timeIntervalSince1970 ?? 0, taken.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(reopened.meals.first?.slot, .lunch)
        reopened.remove(meal.id)
        XCTAssertTrue(reopened.meals.isEmpty)
        XCTAssertNil(reopened.imageData(for: meal))
    }

    func testAPhotoWithoutOnlineAIIsSavedForLater() throws {
        guard !MealPhotoAccess.isUsable else { throw XCTSkip("online AI is offered on this build") }
        let model = VoiceCommandModel(photoMode: true)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PendingAI." + UUID().uuidString)
        let suite = "PendingAI." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        model.pendingStore = PendingMealStore(defaults: defaults, directory: folder)
        model.start()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        }
        model.readPhoto(image)
        guard case .savedForLater = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertEqual(model.pendingStore.meals.count, 1)
    }
}
