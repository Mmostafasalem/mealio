import XCTest
@testable import smartmarket

/// The rule book: what a spoken phrase means, with no network and no model.
@MainActor
final class VoiceRuleBookTests: XCTestCase {

    private func food(_ name: String, _ quantity: Double? = nil, _ unit: VoiceUnit? = nil) -> VoiceFoodPhrase {
        VoiceFoodPhrase(name: name, quantity: quantity, unit: unit)
    }

    // MARK: Food

    func testLogsCountedFoodsWithAMeal() {
        XCTAssertEqual(VoiceRuleBook.parse("Log two eggs and toast for breakfast"),
                       .logFood(items: [food("eggs", 2), food("toast")], slot: .breakfast))
        XCTAssertEqual(VoiceRuleBook.parse("I just had a banana."),
                       .logFood(items: [food("banana")], slot: nil))
        XCTAssertEqual(VoiceRuleBook.parse("For lunch I had chicken breast, rice and a salad"),
                       .logFood(items: [food("chicken breast"), food("rice"), food("salad")], slot: .lunch))
    }

    func testUnderstandsAmountsAndUnits() {
        XCTAssertEqual(VoiceRuleBook.parse("add 200 grams of chicken breast to dinner"),
                       .logFood(items: [food("chicken breast", 200, .gram)], slot: .dinner))
        XCTAssertEqual(VoiceRuleBook.parse("I ate 200g of greek yogurt as a snack"),
                       .logFood(items: [food("greek yogurt", 200, .gram)], slot: .snack))
        XCTAssertEqual(VoiceRuleBook.parse("log a cup of rice and half a banana"),
                       .logFood(items: [food("rice", 1, .cup), food("banana", 0.5)], slot: nil))
        XCTAssertEqual(VoiceRuleBook.parse("I drank a glass of milk"),
                       .logFood(items: [food("milk", 1, .glass)], slot: nil))
        XCTAssertEqual(VoiceRuleBook.parse("log one and a half servings of oatmeal"),
                       .logFood(items: [food("oatmeal", 1.5, .serving)], slot: nil))
        XCTAssertEqual(VoiceRuleBook.parse("track two slices of pizza"),
                       .logFood(items: [food("pizza", 2, .slice)], slot: nil))
        XCTAssertEqual(VoiceRuleBook.parse("log chicken breast 150 grams"),
                       .logFood(items: [food("chicken breast", 150, .gram)], slot: nil))
    }

    func testAPhraseStartingWithAnAmountIsFoodWithoutAVerb() {
        XCTAssertEqual(VoiceRuleBook.parse("two eggs and a slice of toast"),
                       .logFood(items: [food("eggs", 2), food("toast", 1, .slice)], slot: nil))
        // A bare name isn't assumed to be food by the rules; the runner looks it up.
        XCTAssertEqual(VoiceRuleBook.parse("banana"), .unknown("banana"))
    }

    func testNumberWords() {
        XCTAssertEqual(VoiceRuleBook.numberWordsToDigits("twenty five grams"), "25 grams")
        XCTAssertEqual(VoiceRuleBook.numberWordsToDigits("a hundred and fifty grams of rice"), "150 grams of rice")
        XCTAssertEqual(VoiceRuleBook.numberWordsToDigits("two hundred grams"), "200 grams")
        XCTAssertEqual(VoiceRuleBook.numberWordsToDigits("three eggs and two toast"), "3 eggs and 2 toast")
        XCTAssertEqual(VoiceRuleBook.parse("log a hundred and fifty grams of rice"),
                       .logFood(items: [food("rice", 150, .gram)], slot: nil))
    }

    func testFillersAreIgnored() {
        XCTAssertEqual(VoiceRuleBook.parse("Hey Nourlo, can you log two eggs please"),
                       .logFood(items: [food("eggs", 2)], slot: nil))
    }

    // MARK: Cart and checklist

    func testCartAndChecklist() {
        XCTAssertEqual(VoiceRuleBook.parse("Add milk and eggs to my cart"), .addToCart(["milk", "eggs"]))
        XCTAssertEqual(VoiceRuleBook.parse("put bread in the basket"), .addToCart(["bread"]))
        XCTAssertEqual(VoiceRuleBook.parse("add olive oil to my shopping list"), .addToChecklist(["olive oil"]))
        XCTAssertEqual(VoiceRuleBook.parse("I need to buy milk, eggs and bread"), .addToChecklist(["milk", "eggs", "bread"]))
        XCTAssertEqual(VoiceRuleBook.parse("remind me to buy two bottles of water"), .addToChecklist(["water"]))
        XCTAssertEqual(VoiceRuleBook.parse("we're out of coffee"), .addToChecklist(["coffee"]))
    }

    // MARK: Workouts, screens, questions

    func testWorkouts() {
        XCTAssertEqual(VoiceRuleBook.parse("Start a 30 minute cardio workout"), .startWorkout(kind: .cardio, minutes: 30))
        XCTAssertEqual(VoiceRuleBook.parse("build me a gym session"), .startWorkout(kind: .gym, minutes: nil))
        XCTAssertEqual(VoiceRuleBook.parse("I want a twenty minute stretching routine"), .startWorkout(kind: .mobility, minutes: 20))
        XCTAssertEqual(VoiceRuleBook.parse("start a workout for half an hour"), .startWorkout(kind: nil, minutes: 30))
        // Food that mentions training stays food.
        XCTAssertEqual(VoiceRuleBook.parse("I had a protein shake after my training today"),
                       .logFood(items: [food("protein shake after my training")], slot: nil))
    }

    func testScreens() {
        XCTAssertEqual(VoiceRuleBook.parse("open my cart"), .open(.cart))
        XCTAssertEqual(VoiceRuleBook.parse("show me the meal plan"), .open(.meals))
        XCTAssertEqual(VoiceRuleBook.parse("go to settings"), .open(.profile))
        XCTAssertEqual(VoiceRuleBook.parse("take me to the shopping list"), .open(.checklist))
        XCTAssertEqual(VoiceRuleBook.parse("open the barcode scanner"), .open(.scan))
        XCTAssertEqual(VoiceRuleBook.parse("profile"), .open(.profile))
    }

    func testQuestions() {
        XCTAssertEqual(VoiceRuleBook.parse("How many calories do I have left?"), .caloriesLeft)
        XCTAssertEqual(VoiceRuleBook.parse("calories remaining"), .caloriesLeft)
        XCTAssertEqual(VoiceRuleBook.parse("Show me how to do a push up"), .showExercise("push up"))
        XCTAssertEqual(VoiceRuleBook.parse("how do I do squats"), .showExercise("squats"))
    }

    func testNonsenseIsUnknown() {
        XCTAssertEqual(VoiceRuleBook.parse(""), .unknown(""))
        XCTAssertEqual(VoiceRuleBook.parse("what's the weather like"), .unknown("what's the weather like"))
    }

    // MARK: Other languages

    func testGerman() {
        func parse(_ text: String) -> VoiceCommand { VoiceRuleBook.parse(text, language: .german) }
        XCTAssertEqual(parse("Ich habe zwei Eier und eine Scheibe Toast zum Frühstück gegessen"),
                       .logFood(items: [food("egg", 2), food("bread white toasted", 1, .slice)], slot: .breakfast))
        XCTAssertEqual(parse("Trage 200 Gramm Hähnchenbrust zum Abendessen ein"),
                       .logFood(items: [food("chicken breast", 200, .gram)], slot: .dinner))
        XCTAssertEqual(parse("ich trinke ein Glas Milch"), .logFood(items: [food("milk", 1, .glass)], slot: nil))
        XCTAssertEqual(parse("logge fünfundzwanzig Gramm Mandeln als Snack"), .logFood(items: [food("almonds", 25, .gram)], slot: .snack))
        XCTAssertEqual(parse("Trage 1,5 Portionen Haferflocken ein"), .logFood(items: [food("oatmeal", 1.5, .serving)], slot: nil))
        XCTAssertEqual(parse("Füge Milch und Eier zum Warenkorb hinzu"), .addToCart(["milk", "egg"]))
        XCTAssertEqual(parse("Ich muss Brot und Käse kaufen"), .addToChecklist(["brot", "käse"]))
        XCTAssertEqual(parse("Starte ein 30 Minuten Cardio Training"), .startWorkout(kind: .cardio, minutes: 30))
        XCTAssertEqual(parse("Öffne den Warenkorb"), .open(.cart))
        XCTAssertEqual(parse("zeig mir die Einstellungen"), .open(.profile))
        XCTAssertEqual(parse("Wie viele Kalorien habe ich noch übrig?"), .caloriesLeft)
        XCTAssertEqual(parse("Wie mache ich Liegestütze"), .showExercise("push up"))
    }

    func testArabic() {
        func parse(_ text: String) -> VoiceCommand { VoiceRuleBook.parse(text, language: .arabic) }
        XCTAssertEqual(parse("أكلت بيضتين وخبز على الفطور"),
                       .logFood(items: [food("egg", 2), food("bread")], slot: .breakfast))
        XCTAssertEqual(parse("سجل ٢٠٠ غرام صدر دجاج للعشاء"),
                       .logFood(items: [food("chicken breast", 200, .gram)], slot: .dinner))
        XCTAssertEqual(parse("شربت كوب حليب"), .logFood(items: [food("milk", 1, .cup)], slot: nil))
        XCTAssertEqual(parse("أضف ثلاث تمرات كوجبة خفيفة"), .logFood(items: [food("dates", 3)], slot: .snack))
        XCTAssertEqual(parse("أضف الحليب والبيض إلى السلة"), .addToCart(["milk", "egg"]))
        XCTAssertEqual(parse("لازم اشتري خبز وجبنة"), .addToChecklist(["خبز", "جبنه"]))
        XCTAssertEqual(parse("ابدأ تمرين كارديو ٣٠ دقيقة"), .startWorkout(kind: .cardio, minutes: 30))
        XCTAssertEqual(parse("افتح السلة"), .open(.cart))
        XCTAssertEqual(parse("افتح الإعدادات"), .open(.profile))
        XCTAssertEqual(parse("كم سعرة حرارية باقي لي اليوم؟"), .caloriesLeft)
    }

    /// The offline model misspells Lithuanian: a word a letter or two off still counts, when asked.
    func testMisheardWordsAreReadWhenTolerant() {
        let heard = "Joutiana Bakarenei."
        XCTAssertEqual(VoiceRuleBook.parse(heard, language: .lithuanian), .unknown("joutiana bakarenei"))
        XCTAssertEqual(VoiceRuleBook.parse(heard, language: .lithuanian, tolerant: true),
                       .logFood(items: [food("beef", nil)], slot: .dinner))
        XCTAssertEqual(VoiceRuleBook.parse("Sivalgiau du kiausinus", language: .lithuanian, tolerant: true),
                       .logFood(items: [food("egg", 2)], slot: nil))
        // Short words and words that are far off stay as said.
        XCTAssertEqual(VoiceSpelling.near("kova", "kava"), nil)
        XCTAssertEqual(VoiceSpelling.near("stalas", "vakarienei"), nil)
        XCTAssertEqual(VoiceSpelling.near("jautiena", "jautien*"), nil)
        XCTAssertEqual(VoiceSpelling.near("joutiana", "jautien*"), 2)
        // An exact reading is the same with or without it.
        XCTAssertEqual(VoiceRuleBook.parse("Suvalgiau du kiaušinius pusryčiams", language: .lithuanian, tolerant: true),
                       VoiceRuleBook.parse("Suvalgiau du kiaušinius pusryčiams", language: .lithuanian))
    }

    func testLithuanian() {
        func parse(_ text: String) -> VoiceCommand { VoiceRuleBook.parse(text, language: .lithuanian) }
        XCTAssertEqual(parse("Suvalgiau du kiaušinius ir riekelę duonos pusryčiams"),
                       .logFood(items: [food("egg", 2), food("bread", 1, .slice)], slot: .breakfast))
        XCTAssertEqual(parse("Užregistruok 200 gramų vištienos krūtinėlės vakarienei"),
                       .logFood(items: [food("chicken breast", 200, .gram)], slot: .dinner))
        XCTAssertEqual(parse("Išgėriau stiklinę pieno"), .logFood(items: [food("milk", 1, .glass)], slot: nil))
        XCTAssertEqual(parse("Įdėk pieną ir kiaušinius į krepšelį"), .addToCart(["milk", "egg"]))
        XCTAssertEqual(parse("Reikia nupirkti duonos ir sūrio"), .addToChecklist(["duonos", "surio"]))
        XCTAssertEqual(parse("Pradėk 30 minučių kardio treniruotę"), .startWorkout(kind: .cardio, minutes: 30))
        XCTAssertEqual(parse("Atidaryk krepšelį"), .open(.cart))
        XCTAssertEqual(parse("Atidaryk nustatymus"), .open(.profile))
        XCTAssertEqual(parse("Kiek kalorijų man liko?"), .caloriesLeft)
        XCTAssertEqual(parse("Kaip daryti atsispaudimus"), .showExercise("push up"))
    }

    // MARK: Amounts

    private func usda(_ name: String, basis: NutritionFood.Basis = .grams, kcal: Double = 100) -> NutritionFood {
        NutritionFood(id: "usda:1", name: name, brand: nil, basis: basis, kcal: kcal, protein: 5, carbs: 10, fat: 3,
                      source: .usda, sourceID: "1", sourceDate: nil)
    }

    func testAmountsUseTypicalSizes() {
        let egg = usda("Egg, whole, raw")
        XCTAssertEqual(VoiceAmounts.amount(for: food("eggs", 2), food: egg).amount, 100)
        XCTAssertTrue(VoiceAmounts.amount(for: food("eggs", 2), food: egg).estimated)
        // Said in grams: exact.
        let grams = VoiceAmounts.amount(for: food("chicken", 200, .gram), food: usda("Chicken"))
        XCTAssertEqual(grams.amount, 200)
        XCTAssertFalse(grams.estimated)
        XCTAssertEqual(VoiceAmounts.amount(for: food("rice", 1, .cup), food: usda("Rice")).amount, 240)
        XCTAssertEqual(VoiceAmounts.amount(for: food("pizza", 2, .slice), food: usda("Pizza")).amount, 220)
        XCTAssertEqual(VoiceAmounts.amount(for: food("banana", 0.5), food: usda("Banana")).amount, 60)
        // No amount and no typical size: the usual 100 g.
        XCTAssertEqual(VoiceAmounts.amount(for: food("soup"), food: usda("Soup")).amount, 100)
        // Dishes measured in servings are counted.
        let dish = NutritionFood(id: "recipe:x", name: "My stew", brand: nil, basis: .serving, kcal: 400, protein: 20, carbs: 30, fat: 10,
                                 source: .recipe, sourceID: UUID().uuidString, sourceDate: nil)
        XCTAssertEqual(VoiceAmounts.amount(for: food("my stew", 2), food: dish).amount, 2)
        // Never outside what the food logger allows.
        XCTAssertEqual(VoiceAmounts.amount(for: food("rice", 50, .kilogram), food: usda("Rice")).amount, 5000)
    }

    // MARK: Which food a name means

    func testSpokenNamesPickThePlainFood() {
        func top(_ name: String) -> String { VoiceFoodRanker.foods(for: name, limit: 1, recentIDs: []).first?.name ?? "" }
        XCTAssertEqual(top("eggs"), "Egg, whole, raw")
        XCTAssertEqual(top("banana"), "Banana, raw")
        XCTAssertEqual(top("toast"), "Bread, white, toasted")
        XCTAssertEqual(top("rice"), "Rice, cooked, NFS")
        XCTAssertEqual(top("greek yogurt"), "Yogurt, Greek, plain, whole milk")
        XCTAssertEqual(top("salmon"), "Fish, salmon, NFS")
        XCTAssertEqual(top("fries"), "Potato, french fries, NFS")
        XCTAssertTrue(top("chicken").lowercased().hasPrefix("chicken"), top("chicken"))
        XCTAssertFalse(top("chicken").lowercased().contains("meatless"), top("chicken"))
    }

    func testRankingPrefersRecentAndPlainForms() {
        let whole = usda("Eggs, Grade A, Large, egg whole")
        let yolk = NutritionFood(id: "usda:2", name: "Eggs, Grade A, Large, egg yolk", brand: nil, basis: .grams, kcal: 334, protein: 16, carbs: 1, fat: 28,
                                 source: .usda, sourceID: "2", sourceDate: nil)
        let found = VoiceFoodRanker.foods(for: "eggs", search: { _ in [yolk, whole] }, recentIDs: [])
        XCTAssertEqual(found.first?.id, whole.id)
        // Something the person logs often wins over the plain form.
        let again = VoiceFoodRanker.foods(for: "eggs", search: { _ in [whole, yolk] }, recentIDs: [yolk.id])
        XCTAssertEqual(again.first?.id, yolk.id)
    }

    // MARK: Regional dishes

    func testRegionalDishesLoadAndAreFoundByLocalNames() throws {
        let dishes = NutritionDatabase.loadRegional()
        XCTAssertGreaterThanOrEqual(dishes.count, 40)
        XCTAssertTrue(dishes.allSatisfy { $0.isValid && $0.source == .regional && $0.basis == .grams })
        let catalog = NutritionCatalogService.shared
        func first(_ query: String) -> String { catalog.searchLocal(query).first?.id ?? "" }
        XCTAssertEqual(first("cepelinai su varške"), "regional:cepelinai-curd")
        XCTAssertEqual(first("šaltibarščiai"), "regional:saltibarsciai")
        XCTAssertEqual(first("saltibarsciai"), "regional:saltibarsciai")
        XCTAssertEqual(first("koshari"), "regional:koshari")
        XCTAssertEqual(first("كشري"), "regional:koshari")
        XCTAssertEqual(first("شاورما دجاج"), "regional:shawarma-chicken")
        XCTAssertEqual(catalog.find("regional:kugelis")?.name, "Kugelis, baked potato pudding with bacon")
        let kugelis = try XCTUnwrap(catalog.find("regional:kugelis"))
        XCTAssertEqual(kugelis.sourceName, "Nourlo recipe estimate · USDA ingredients")
        XCTAssertTrue(kugelis.sourceExplanation.contains("Made with potatoes"))
        XCTAssertNil(kugelis.sourceURL)
        // A made-up regional record is rejected.
        let fake = NutritionFood(id: "regional:Bad Id", name: "x", brand: nil, basis: .grams, kcal: 1, protein: 1, carbs: 1, fat: 1,
                                 source: .regional, sourceID: "Bad Id", sourceDate: nil)
        XCTAssertFalse(fake.isValid)
    }

    func testVoiceFindsRegionalDishesInEveryLanguage() {
        func top(_ text: String, _ language: VoiceLanguage) -> String {
            guard case .food(let matches, _, _) = VoiceCommandRunner.plan(for: VoiceRuleBook.parse(text, language: language), language: language) else { return "" }
            return matches.first?.food.id ?? ""
        }
        XCTAssertEqual(top("log 300 grams of cepelinai for lunch", .english), "regional:cepelinai-meat")
        XCTAssertEqual(top("I had koshari", .english), "regional:koshari")
        XCTAssertEqual(top("Suvalgiau 250 gramų kugelio pietums", .lithuanian), "regional:kugelis")
        XCTAssertEqual(top("أكلت كشري على الغداء", .arabic), "regional:koshari")
    }

    func testProductsAreLookedUpOnlyForRealSearches() {
        XCTAssertFalse(LogFoodSheet.isAutoSearchable("eg"))
        XCTAssertTrue(LogFoodSheet.isAutoSearchable("oat milk"))
        // A half-typed barcode is not a text search.
        XCTAssertFalse(LogFoodSheet.isAutoSearchable("59012345"))
        XCTAssertFalse(LogFoodSheet.isAutoSearchable("   "))
        XCTAssertFalse(LogFoodSheet.isAutoSearchable(String(repeating: "a", count: 101)))
    }

    // MARK: Plans

    func testPlanMatchesFoodsAndReportsMissingOnes() {
        let egg = usda("Egg, whole, raw")
        let search: VoiceCommandRunner.FoodSearch = { $0.contains("egg") ? [egg] : [] }
        let plan = VoiceCommandRunner.plan(for: .logFood(items: [food("eggs", 2), food("unobtainium")], slot: .breakfast), search: search)
        guard case .food(let matches, let missing, let slot) = plan else { return XCTFail("expected a food plan") }
        XCTAssertEqual(matches.map(\.food.name), ["Egg, whole, raw"])
        XCTAssertEqual(matches.first?.amount, 100)
        XCTAssertEqual(missing, ["unobtainium"])
        XCTAssertEqual(slot, .breakfast)
        XCTAssertFalse(plan.isComplete)
        XCTAssertTrue(plan.needsConfirmation)
    }

    func testABareFoodNameIsLookedUp() {
        let banana = usda("Banana, raw")
        let found = VoiceCommandRunner.plan(for: VoiceRuleBook.parse("banana"), search: { _ in [banana] })
        guard case .food(let matches, let missing, _) = found else { return XCTFail("expected a food plan") }
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(missing.isEmpty)
        let nothing = VoiceCommandRunner.plan(for: VoiceRuleBook.parse("what's the weather like"), search: { _ in [] })
        guard case .notUnderstood = nothing else { return XCTFail("expected not understood") }
    }

    func testCartPlanUsesTheCatalogue() {
        guard case .cart(let items, let missing) = VoiceCommandRunner.plan(for: .addToCart(["milk", "zzzzqqq"])) else {
            return XCTFail("expected a cart plan")
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(missing, ["zzzzqqq"])
    }

    func testNavigationPlansNeedNoConfirmation() {
        XCTAssertFalse(VoiceCommandRunner.plan(for: .open(.cart)).needsConfirmation)
        XCTAssertEqual(VoiceCommandRunner.plan(for: .startWorkout(kind: .gym, minutes: 500)), .workout(kind: .gym, minutes: 120))
        XCTAssertEqual(VoiceCommandRunner.perform(.open(.cart)).navigation, .screen(.cart))
    }
}
