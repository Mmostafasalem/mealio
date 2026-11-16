import XCTest
@testable import smartmarket

@MainActor
final class IntentsTests: XCTestCase {

    private let en = Locale(identifier: "en_US")

    private func food(_ id: String, _ name: String, basis: NutritionFood.Basis = .grams, kcal: Double = 89,
                      protein: Double = 1.1, carbs: Double = 22.8, fat: Double = 0.3) -> NutritionFood {
        NutritionFood(id: "usda:\(id)", name: name, brand: nil, basis: basis, kcal: kcal, protein: protein,
                      carbs: carbs, fat: fat, source: .usda, sourceID: id, sourceDate: nil)
    }

    private func date(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: Date())!
    }

    // MARK: Name search

    func testSingularForgivesSimplePlurals() {
        XCTAssertEqual(IntentSearch.singular("lunges"), "lunge")
        XCTAssertEqual(IntentSearch.singular("squats"), "squat")
        XCTAssertEqual(IntentSearch.singular("berries"), "berry")
        XCTAssertEqual(IntentSearch.singular("potatoes"), "potato")
        XCTAssertEqual(IntentSearch.singular("presses"), "press")
        XCTAssertEqual(IntentSearch.singular("press"), "press")
        XCTAssertEqual(IntentSearch.singular("hummus"), "hummus")
        XCTAssertEqual(IntentSearch.words("Push-Ups"), ["push", "up"])
    }

    func testExerciseSearchByNameIgnoresCaseAndPlurals() {
        let squat = ExerciseEntityQuery.search("GOBLET SQUATS")
        XCTAssertEqual(squat.first?.id, "goblet-squat")

        let lunges = ExerciseEntityQuery.search("walking lunges")
        XCTAssertEqual(lunges.first?.id, "walking-lunge")

        let exact = ExerciseEntityQuery.search("Leg press")
        XCTAssertEqual(exact.first?.id, "leg-press", "an exact name comes first")

        XCTAssertTrue(ExerciseEntityQuery.search("").isEmpty)
        XCTAssertTrue(ExerciseEntityQuery.search("zzzz qqqq").isEmpty)
    }

    func testExerciseSearchFallsBackToMuscles() {
        let results = ExerciseEntityQuery.search("hamstrings")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.muscles.lowercased().contains("hamstring") || $0.name.lowercased().contains("hamstring") })
    }

    func testExerciseEntityRoundTripsEveryCatalogueID() async throws {
        let ids = Exercise.catalog.prefix(5).map(\.id)
        let entities = try await ExerciseEntityQuery().entities(for: ids)
        XCTAssertEqual(Set(entities.map(\.id)), Set(ids))
        XCTAssertEqual(Set(Exercise.catalog.map(\.id)).count, Exercise.catalog.count, "Spotlight and Siri ids must be unique")
    }

    func testExerciseEntityAcceptsOldSpotlightIdentifiers() async throws {
        let id = try XCTUnwrap(Exercise.catalog.first?.id)
        let entities = try await ExerciseEntityQuery().entities(for: ["exercise:" + id])
        XCTAssertEqual(entities.map(\.id), [id])
        XCTAssertEqual(AppRouter.exerciseID(fromIdentifier: "exercise:" + id), id)
        XCTAssertEqual(AppRouter.exerciseID(fromIdentifier: id), id)
    }

    // MARK: Recent foods without the catalogue

    func testRecentFoodsComeFromTheNewestLogSnapshot() {
        let old = food("1", "Banana, raw", kcal: 80)
        let new = food("1", "Banana, raw", kcal: 89)
        let apple = food("2", "Apple, raw")
        let dish = NutritionFood(id: "recipe:3", name: "My stew", brand: nil, basis: .serving, kcal: 400, protein: 20,
                             carbs: 30, fat: 10, source: .recipe, sourceID: "3", sourceDate: nil)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let entries = [
            FoodLogEntry(nutritionFood: new, slot: .lunch, amount: 100).withDate(t0.addingTimeInterval(60)),
            FoodLogEntry(nutritionFood: old, slot: .lunch, amount: 100).withDate(t0),
            FoodLogEntry(nutritionFood: apple, slot: .lunch, amount: 100).withDate(t0),
            FoodLogEntry(nutritionFood: dish, slot: .dinner, amount: 1).withDate(t0),
        ]
        let recents = FoodEntityQuery.recentFoods(ids: ["usda:2", "usda:1", "recipe:3", "usda:9", "usda:2"], entries: entries)
        XCTAssertEqual(recents.map(\.id), ["usda:2", "usda:1"], "own dishes and unknown ids come from the catalogue; no duplicates")
        XCTAssertEqual(recents.last?.kcal, 89, "the newest snapshot wins")
    }

    // MARK: Router

    func testRouterHoldsRequestsUntilOnboardedAndDropsStaleOnes() {
        let state = RouterTestState(now: Date(timeIntervalSince1970: 2_000_000))
        let router = AppRouter(isReady: { state.ready }, now: { state.now })
        router.open(.groceries)
        XCTAssertNil(router.takeRequest(), "nothing is routed before onboarding")
        state.ready = true
        XCTAssertEqual(router.takeRequest(), .link(.groceries))
        XCTAssertNil(router.takeRequest(), "a request is taken once")

        router.open(.meals)
        state.now = state.now.addingTimeInterval(AppRouter.requestLifetime + 1)
        XCTAssertNil(router.takeRequest(), "a stale request doesn't pop up later")
    }

    func testScanRequestsExpireAndAreTakenOnce() {
        let state = RouterTestState(now: Date(timeIntervalSince1970: 3_000_000))
        let router = AppRouter(isReady: { true }, now: { state.now })
        XCTAssertFalse(router.consumeScanRequest())
        let before = router.scanRequestID
        router.open(.scan)
        XCTAssertEqual(router.scanRequestID, before + 1, "an open logger is told about every scan request")
        XCTAssertTrue(router.consumeScanRequest())
        XCTAssertFalse(router.consumeScanRequest(), "taken once")

        router.open(.scan)
        state.now = state.now.addingTimeInterval(AppRouter.scanLifetime + 1)
        XCTAssertFalse(router.consumeScanRequest(), "the camera never opens unprompted later")
    }

    func testRouterShowsOnlyCatalogueExercises() throws {
        let router = AppRouter(isReady: { true })
        let id = try XCTUnwrap(Exercise.catalog.first?.id)
        router.showExercise(id: "exercise:" + id)
        XCTAssertEqual(router.takeRequest(), .exercise(id))
        router.showExercise(id: "not-an-exercise")
        XCTAssertNil(router.takeRequest())
    }

    // MARK: Link inbox

    func testInboxLinksExpire() {
        let defaults = UserDefaults(suiteName: "IntentsTests.inbox." + UUID().uuidString)!
        let t0 = Date(timeIntervalSince1970: 4_000_000)
        NourloLinkInbox.post(.train, defaults: defaults, now: t0)
        XCTAssertEqual(NourloLinkInbox.take(defaults: defaults, now: t0.addingTimeInterval(5)), .train)
        XCTAssertNil(NourloLinkInbox.take(defaults: defaults, now: t0.addingTimeInterval(6)), "taken once")

        NourloLinkInbox.post(.scan, defaults: defaults, now: t0)
        XCTAssertNil(NourloLinkInbox.take(defaults: defaults, now: t0.addingTimeInterval(NourloLinkInbox.lifetime + 1)))
        XCTAssertNil(NourloLinkInbox.take(defaults: defaults, now: t0), "an expired link is removed")
    }

    func testFoodSearchForgivesPlurals() {
        let foods = [food("1", "Banana, raw"), food("2", "Apple, raw, with skin"), food("3", "Bananas, dehydrated")]
        let index = NutritionSearchIndex(foods: foods)
        let plural = FoodEntityQuery.search("Bananas", using: { index.search($0) })
        XCTAssertEqual(plural.map(\.id).sorted(), ["usda:1", "usda:3"])
        let caps = FoodEntityQuery.search("APPLE", using: { index.search($0) })
        XCTAssertEqual(caps.map(\.id), ["usda:2"])
        XCTAssertTrue(FoodEntityQuery.search("   ", using: { index.search($0) }).isEmpty)
    }

    // MARK: Calories left

    func testCaloriesLeftDialog() {
        XCTAssertEqual(CaloriesLeftSummary(eaten: 1480, goal: 2100).dialog(locale: en),
                       "You have 620 kcal left today: 1,480 of 2,100 eaten.")
        XCTAssertEqual(CaloriesLeftSummary(eaten: 2250, goal: 2100).dialog(locale: en),
                       "You're 150 kcal over today: 2,250 of 2,100 eaten.")
        XCTAssertEqual(CaloriesLeftSummary(eaten: 2100, goal: 2100).dialog(locale: en),
                       "You've reached your goal today: 2,100 of 2,100 eaten.")
        XCTAssertEqual(CaloriesLeftSummary(eaten: 0, goal: 2100).dialog(locale: en),
                       "You have 2,100 kcal left today: 0 of 2,100 eaten.")
    }

    func testCaloriesLeftWithoutGoalIsHonest() {
        let none = CaloriesLeftSummary(eaten: 0, goal: 0)
        XCTAssertFalse(none.hasGoal)
        XCTAssertEqual(none.progress, 0)
        XCTAssertEqual(none.dialog(locale: en), "Finish setting up Nourlo so it can work out your daily calorie goal.")
        XCTAssertEqual(CaloriesLeftSummary(eaten: 350, goal: 0).dialog(locale: en),
                       "Finish setting up Nourlo so it can work out your daily calorie goal. You've eaten 350 kcal today.")
    }

    // MARK: Today's meals

    func testTodaysMealsDialog() {
        XCTAssertEqual(TodaysMealsSummary.dialog(meals: nil, slot: nil, locale: en),
                       "No meal plan yet. Open Meals in Nourlo to make one.")
        let meals = [PlannedMeal(slot: .breakfast, name: "Oats with berries", kcal: 420),
                     PlannedMeal(slot: .lunch, name: "Chicken rice bowl", kcal: 640),
                     PlannedMeal(slot: .dinner, name: "Salmon", kcal: 500),
                     PlannedMeal(slot: .dinner, name: "Potatoes", kcal: 1100)]
        XCTAssertEqual(TodaysMealsSummary.dialog(meals: meals, slot: .lunch, locale: en),
                       "For lunch today: Chicken rice bowl, 640 kcal.")
        XCTAssertEqual(TodaysMealsSummary.dialog(meals: meals, slot: .dinner, locale: en),
                       "For dinner today: Salmon and Potatoes, 1,600 kcal.")
        XCTAssertEqual(TodaysMealsSummary.dialog(meals: meals, slot: .snacks, locale: en),
                       "Nothing is planned for snacks today.")
        XCTAssertEqual(TodaysMealsSummary.dialog(meals: meals, slot: nil, locale: en),
                       "Today's plan. Breakfast: Oats with berries, 420 kcal. Lunch: Chicken rice bowl, 640 kcal. Dinner: Salmon and Potatoes, 1,600 kcal.")
    }

    func testMealSlotOptionMapsBothWays() {
        for slot in MealSlot.allCases { XCTAssertEqual(MealSlotOption(slot).mealSlot, slot) }
    }

    // MARK: Quick log

    func testMealSlotDefaultsByTimeOfDay() throws {
        let banana = food("1", "Banana, raw")
        XCTAssertEqual(try LogFoodIntent.makeEntry(food: banana, amount: nil, slot: nil, now: date(hour: 8)).slot, .breakfast)
        XCTAssertEqual(try LogFoodIntent.makeEntry(food: banana, amount: nil, slot: nil, now: date(hour: 12)).slot, .lunch)
        XCTAssertEqual(try LogFoodIntent.makeEntry(food: banana, amount: nil, slot: nil, now: date(hour: 16)).slot, .snack)
        XCTAssertEqual(try LogFoodIntent.makeEntry(food: banana, amount: nil, slot: nil, now: date(hour: 20)).slot, .dinner)
        XCTAssertEqual(try LogFoodIntent.makeEntry(food: banana, amount: nil, slot: .dinner, now: date(hour: 8)).slot, .dinner,
                       "a chosen meal wins over the clock")
    }

    func testQuickLogBuildsTheSameEntryAsTheFoodLogger() throws {
        let banana = food("1", "Banana, raw")
        let entry = try LogFoodIntent.makeEntry(food: banana, amount: 150, slot: .breakfast)
        let sheet = FoodLogEntry(nutritionFood: banana, slot: .breakfast, amount: 150)
        XCTAssertEqual(entry.foodId, sheet.foodId)
        XCTAssertEqual(entry.name, sheet.name)
        XCTAssertEqual(entry.slot, sheet.slot)
        XCTAssertEqual(entry.servingG, sheet.servingG)
        XCTAssertEqual(entry.calories, sheet.calories)
        XCTAssertEqual(entry.proteinG, sheet.proteinG, accuracy: 0.0001)
        XCTAssertEqual(entry.carbsG, sheet.carbsG, accuracy: 0.0001)
        XCTAssertEqual(entry.fatG, sheet.fatG, accuracy: 0.0001)
        XCTAssertEqual(entry.portionAmount, 150)
        XCTAssertEqual(entry.nutritionFood, banana)
        XCTAssertEqual(entry.calories, 134)

        let defaultAmount = try LogFoodIntent.makeEntry(food: banana, amount: nil, slot: .lunch)
        XCTAssertEqual(defaultAmount.amount, banana.defaultAmount)
        XCTAssertEqual(defaultAmount.calories, 89)

        let serving = food("2", "Burrito", basis: .serving, kcal: 650, protein: 30, carbs: 70, fat: 25)
        XCTAssertEqual(try LogFoodIntent.makeEntry(food: serving, amount: nil, slot: .lunch).amount, 1)
    }

    func testQuickLogRejectsUnsafeAmounts() {
        let banana = food("1", "Banana, raw")
        for bad in [0, 0.5, 6000, .nan, .infinity, -10] {
            XCTAssertThrowsError(try LogFoodIntent.makeEntry(food: banana, amount: bad, slot: .lunch), "\(bad)")
        }
        let serving = food("2", "Burrito", basis: .serving, kcal: 650, protein: 30, carbs: 70, fat: 25)
        XCTAssertThrowsError(try LogFoodIntent.makeEntry(food: serving, amount: 25, slot: .lunch))
        XCTAssertNoThrow(try LogFoodIntent.makeEntry(food: serving, amount: 0.5, slot: .lunch))
        let invalid = food("x", "Broken", kcal: -5)
        XCTAssertThrowsError(try LogFoodIntent.makeEntry(food: invalid, amount: 100, slot: .lunch))
    }

    func testQuickLogConfirmation() throws {
        let banana = food("1", "Banana, raw")
        let entry = try LogFoodIntent.makeEntry(food: banana, amount: 100, slot: .breakfast)
        XCTAssertEqual(LogFoodIntent.confirmation(for: entry, food: banana, locale: en),
                       "Logged 100 g of Banana, raw to breakfast, 89 kcal.")
        let serving = food("2", "Burrito", basis: .serving, kcal: 650, protein: 30, carbs: 70, fat: 25)
        let two = try LogFoodIntent.makeEntry(food: serving, amount: 2, slot: .dinner)
        XCTAssertEqual(LogFoodIntent.confirmation(for: two, food: serving, locale: en),
                       "Logged 2 servings of Burrito to dinner, 1,300 kcal.")
    }

    // MARK: Spotlight

    func testSpotlightItemsUseRouterIdentifiers() {
        let catalog = Array(Exercise.catalog.prefix(3))
        let items = SpotlightIndexer.items(for: catalog)
        // The same id as the associated `ExerciseEntity`, so iOS 18 can resolve it.
        XCTAssertEqual(items.map(\.uniqueIdentifier), catalog.map(\.id))
        XCTAssertEqual(items.map(\.uniqueIdentifier), catalog.map { ExerciseEntity($0).id })
        XCTAssertTrue(items.allSatisfy { $0.domainIdentifier == SpotlightIndexer.exerciseDomain })
        XCTAssertEqual(items.first?.attributeSet.title, catalog.first?.name)
        XCTAssertTrue(items.first?.attributeSet.keywords?.contains("exercise") == true)
    }

    func testSpotlightVersionTracksCatalogueChanges() {
        let catalog = Array(Exercise.catalog.prefix(10))
        XCTAssertEqual(SpotlightIndexer.catalogVersion(catalog), SpotlightIndexer.catalogVersion(catalog))
        XCTAssertNotEqual(SpotlightIndexer.catalogVersion(catalog), SpotlightIndexer.catalogVersion(Array(catalog.dropLast())))
    }

    func testSpotlightKeywordsSplitMusclesAndEquipment() {
        guard let squat = Exercise.catalog.first(where: { $0.id == "back-squat" }) else { return XCTFail("missing back squat") }
        let keywords = SpotlightIndexer.keywords(for: squat)
        XCTAssertTrue(keywords.contains("quads"))
        XCTAssertTrue(keywords.contains("glutes"))
        XCTAssertTrue(keywords.contains("barbell"))
        XCTAssertEqual(Set(keywords).count, keywords.count)
    }
}

private extension FoodLogEntry {
    func withDate(_ date: Date) -> FoodLogEntry {
        FoodLogEntry(id: id, foodId: foodId, name: name, slot: slot, servingG: servingG, calories: calories,
                     proteinG: proteinG, carbsG: carbsG, fatG: fatG, loggedAt: date,
                     nutritionFood: nutritionFood, portionAmount: portionAmount)
    }
}

/// A clock and onboarding flag the router tests can change.
private final class RouterTestState: @unchecked Sendable {
    var ready = false
    var now: Date
    init(now: Date) { self.now = now }
}
