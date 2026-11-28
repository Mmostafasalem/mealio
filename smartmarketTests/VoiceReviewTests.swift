import XCTest
@testable import smartmarket

/// Voice fixes from review: stray words, piece weights, shopping before
/// workouts, meal words inside food names, and calorie questions.
@MainActor
final class VoiceReviewTests: XCTestCase {

    private func food(_ name: String, _ quantity: Double? = nil, _ unit: VoiceUnit? = nil) -> VoiceFoodPhrase {
        VoiceFoodPhrase(name: name, quantity: quantity, unit: unit)
    }

    private func usda(_ name: String, basis: NutritionFood.Basis = .grams) -> NutritionFood {
        NutritionFood(id: "usda:1", name: name, brand: nil, basis: basis, kcal: 100, protein: 5, carbs: 10, fat: 3,
                      source: .usda, sourceID: "1", sourceDate: nil)
    }

    private func isNotUnderstood(_ plan: VoicePlan) -> Bool {
        if case .notUnderstood = plan { return true }
        return false
    }

    // MARK: Stray words

    func testStrayWordsLogNothing() {
        for word in ["stop", "no", "yes", "help", "hi", "run", "test"] {
            // Against the real food list.
            XCTAssertTrue(isNotUnderstood(VoiceCommandRunner.plan(for: VoiceRuleBook.parse(word))), word)
            // And even when a search hands a food back for it.
            let pushed = VoiceCommandRunner.plan(for: VoiceRuleBook.parse(word), search: { _ in [self.usda("Noodles, egg, cooked")] })
            XCTAssertTrue(isNotUnderstood(pushed), word)
        }
    }

    func testABareNameMustBeAWholeWordOfTheFood() {
        // The start of a word isn't the word.
        let ham = VoiceCommandRunner.plan(for: .unknown("ham"), search: { _ in [self.usda("Hamburger, plain")] })
        XCTAssertTrue(isNotUnderstood(ham))
        let pea = VoiceCommandRunner.plan(for: .unknown("pea"), search: { _ in [self.usda("Peanut butter, smooth")] })
        XCTAssertTrue(isNotUnderstood(pea))
        // A word from far down the name isn't the food either.
        let raw = VoiceCommandRunner.plan(for: .unknown("raw"), search: { _ in [self.usda("Banana, raw")] })
        XCTAssertTrue(isNotUnderstood(raw))
        // The food under a catalogue group counts.
        let salmon = VoiceCommandRunner.plan(for: .unknown("salmon"), search: { _ in [self.usda("Fish, salmon, raw")] })
        XCTAssertFalse(isNotUnderstood(salmon))
    }

    func testABareNameIsAGuessThatWaitsForATap() {
        let search: VoiceCommandRunner.FoodSearch = { _ in [self.usda("Banana, raw")] }
        let bare = VoiceCommandRunner.plan(for: VoiceRuleBook.parse("banana"), search: search)
        guard case .food(let matches, let missing, _) = bare else { return XCTFail("expected a food plan") }
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(missing.isEmpty)
        XCTAssertTrue(bare.isComplete)
        XCTAssertTrue(bare.isGuessed)
        // Said as a command, it is not a guess.
        let said = VoiceCommandRunner.plan(for: VoiceRuleBook.parse("log a banana"), search: search)
        XCTAssertTrue(said.isComplete)
        XCTAssertFalse(said.isGuessed)
    }

    // MARK: Amounts

    func testGramsOfAServingFoodAreOneServingAndAGuess() {
        let dish = NutritionFood(id: "recipe:x", name: "My stew", brand: nil, basis: .serving, kcal: 400, protein: 20, carbs: 30, fat: 10,
                                 source: .recipe, sourceID: UUID().uuidString, sourceDate: nil)
        let grams = VoiceAmounts.amount(for: food("my stew", 200, .gram), food: dish)
        XCTAssertEqual(grams.amount, 1)
        XCTAssertTrue(grams.estimated)
        XCTAssertEqual(VoiceAmounts.amount(for: food("my stew", 250, .millilitre), food: dish).amount, 1)
        // Counted servings stay as said.
        XCTAssertEqual(VoiceAmounts.amount(for: food("my stew", 2, .serving), food: dish).amount, 2)
        XCTAssertFalse(VoiceAmounts.isUnsure(food("my stew", 2), food: dish))

        let plan = VoiceCommandRunner.plan(for: .logFood(items: [food("my stew", 200, .gram)], slot: .dinner), search: { _ in [dish] })
        XCTAssertTrue(plan.isGuessed)
    }

    func testPieceWeightsNeedThePieceWordAsTheFood() {
        func grams(_ phrase: VoiceFoodPhrase, _ name: String) -> Double { VoiceAmounts.amount(for: phrase, food: usda(name)).amount }
        // A piece word that only describes the food: the usual 100.
        XCTAssertEqual(grams(food("almond milk"), "Almond milk, unsweetened"), 100)
        XCTAssertEqual(grams(food("strawberry yogurt"), "Yogurt, Greek, strawberry, lowfat"), 100)
        XCTAssertEqual(grams(food("potato chips"), "Potato chips, NFS"), 100)
        XCTAssertEqual(grams(food("black pepper"), "Spices, pepper, black"), 100)
        XCTAssertEqual(grams(food("apple pie"), "Pie, apple"), 100)
        XCTAssertEqual(grams(food("almond milk", 2), "Almond milk, unsweetened"), 200)
        XCTAssertEqual(grams(food("apple pie", 1, .piece), "Pie, apple"), 100)
        // The piece word as the food itself still counts in pieces.
        XCTAssertEqual(grams(food("eggs", 2), "Egg, whole, raw"), 100)
        XCTAssertEqual(grams(food("boiled eggs", 2), "Egg, whole, boiled or poached"), 100)
        XCTAssertEqual(grams(food("apple"), "Apple, raw"), 180)
        XCTAssertEqual(grams(food("chicken breast", 1), "Chicken breast, baked"), 170)
    }

    // MARK: Shopping before workouts

    func testShoppingPhrasesAreNotWorkouts() {
        XCTAssertEqual(VoiceRuleBook.parse("buy exercise bands"), .addToChecklist(["exercise bands"]))
        XCTAssertEqual(VoiceRuleBook.parse("add a workout mat to my cart"), .addToCart(["workout mat"]))
        XCTAssertEqual(VoiceRuleBook.parse("add training shoes to my list"), .addToChecklist(["training shoes"]))
        // A food verb in front of a short phrase isn't a request for a workout.
        if case .startWorkout = VoiceRuleBook.parse("log my workout") { XCTFail("\"log my workout\" started a workout") }
        // Workouts still work, short ones included.
        XCTAssertEqual(VoiceRuleBook.parse("gym session"), .startWorkout(kind: .gym, minutes: nil))
        XCTAssertEqual(VoiceRuleBook.parse("Start a 30 minute cardio workout"), .startWorkout(kind: .cardio, minutes: 30))
    }

    // MARK: Meal words inside food names

    func testAMealWordInsideAFoodNameStaysThere() {
        XCTAssertEqual(VoiceRuleBook.parse("log a snack bar"), .logFood(items: [food("snack bar")], slot: nil))
        XCTAssertEqual(VoiceRuleBook.parse("I had breakfast cereal"), .logFood(items: [food("breakfast cereal")], slot: nil))
        XCTAssertEqual(VoiceRuleBook.parse("breakfast cereal"), .unknown("breakfast cereal"))
        // With a preposition, or at the end or the start, it is the meal.
        XCTAssertEqual(VoiceRuleBook.parse("I had a snack bar for a snack"), .logFood(items: [food("snack bar")], slot: .snack))
        XCTAssertEqual(VoiceRuleBook.parse("log breakfast cereal for breakfast"), .logFood(items: [food("breakfast cereal")], slot: .breakfast))
        XCTAssertEqual(VoiceRuleBook.parse("I ate 200g of greek yogurt as a snack"), .logFood(items: [food("greek yogurt", 200, .gram)], slot: .snack))
        XCTAssertEqual(VoiceRuleBook.parse("two eggs lunch"), .logFood(items: [food("eggs", 2)], slot: .lunch))
        XCTAssertEqual(VoiceRuleBook.parse("breakfast two eggs"), .logFood(items: [food("eggs", 2)], slot: .breakfast))
    }

    func testBothSpellingsOfYogurt() {
        XCTAssertEqual(VoiceRuleBook.parse("log 200 g of strawberry yoghurt"), .logFood(items: [food("strawberry yogurt", 200, .gram)], slot: nil))
    }

    // MARK: Calorie questions

    func testOnlyQuestionsAboutWhatIsLeftAnswerCaloriesLeft() {
        XCTAssertEqual(VoiceRuleBook.parse("How many calories do I have left?"), .caloriesLeft)
        XCTAssertEqual(VoiceRuleBook.parse("calories remaining"), .caloriesLeft)
        XCTAssertEqual(VoiceRuleBook.parse("how many calories can I eat"), .caloriesLeft)
        XCTAssertEqual(VoiceRuleBook.parse("how many calories have I got"), .caloriesLeft)
        XCTAssertEqual(VoiceRuleBook.parse("how many calories are left in the day"), .caloriesLeft)
        // About a food, not about today.
        XCTAssertNotEqual(VoiceRuleBook.parse("how many calories in a banana"), .caloriesLeft)
        XCTAssertNotEqual(VoiceRuleBook.parse("how many calories are in an apple"), .caloriesLeft)
        XCTAssertNotEqual(VoiceRuleBook.parse("how many calories do I have in the rice"), .caloriesLeft)
        XCTAssertNotEqual(VoiceRuleBook.parse("how much is a kcal"), .caloriesLeft)
    }
}
