import XCTest
@testable import smartmarket

/// The fixes from the pre-release review, each pinned to the case that went wrong.
@MainActor
final class ReviewFixesTests: XCTestCase {

    // MARK: Plan roles

    func testFoodsPlayTheRightPartInThePlan() {
        XCTAssertEqual(FallbackData.planRole(name: "Eggplant", category: "vegetables"), "vegetables", "not the protein")
        XCTAssertEqual(FallbackData.planRole(name: "Eggs, whole, raw", category: ""), "eggs")
        XCTAssertNil(FallbackData.planRole(name: "Butter", category: "dairy"), "butter is never breakfast's half cup")
        XCTAssertNil(FallbackData.planRole(name: "Gouda", category: "dairy"))
        XCTAssertNil(FallbackData.planRole(name: "Heavy Cream", category: "dairy"))
        XCTAssertEqual(FallbackData.planRole(name: "Cottage Cheese", category: "dairy"), "dairy")
        XCTAssertEqual(FallbackData.planRole(name: "Greek Yogurt", category: "dairy"), "dairy")
        XCTAssertEqual(FallbackData.planRole(name: "Potato", category: "vegetables"), "grains", "potatoes are the plate's carb")
        XCTAssertEqual(FallbackData.planRole(name: "Frozen Vegetable Mix", category: "frozen"), "vegetables")
        XCTAssertEqual(FallbackData.planRole(name: "Frozen Berry Mix", category: "frozen"), "fruits")
        XCTAssertEqual(FallbackData.planRole(name: "Peanut Butter", category: "nuts"), "nuts")
        XCTAssertNil(FallbackData.planRole(name: "Potato Chips", category: "snacks"), "snacks aren't the nut handful")
        XCTAssertNil(FallbackData.planRole(name: "Graham Crackers", category: "snacks"))
        XCTAssertNil(FallbackData.planRole(name: "Peppermint Tea", category: "beverages"))
    }

    func testGroceriesAndThePlanAgreeOnDiets() throws {
        let chicken = try XCTUnwrap(CatalogItem.all.first { $0.id == "chicken-breast" })
        let oatMilk = try XCTUnwrap(CatalogItem.all.first { $0.id == "oat-milk" })
        XCTAssertFalse(WeeklyGroceryPlanner.allowed(chicken, [.halal]), "unlabelled meat isn't suggested for halal, as the plan refuses it")
        XCTAssertTrue(WeeklyGroceryPlanner.allowed(oatMilk, [.vegan]), "oat milk is vegan")
        XCTAssertTrue(Set<DietaryPreference>([.vegan]).allows(name: "Oat Milk", category: "dairy"))
        XCTAssertFalse(Set<DietaryPreference>([.vegan]).allows(name: "Milk 2.5%", category: "dairy"))
    }

    func testPlannedMealsCarryTheirFoodsOnceTheCatalogueIsRead() throws {
        _ = NutritionCatalogService.shared
        StockStore.shared.clearItems()
        let cart = [CartItem(id: UUID(), catalogId: "chicken-breast", name: "Chicken Breast", store: "Catalogue", price: 5, category: "meat", quantity: 1),
                    CartItem(id: UUID(), catalogId: "brown-rice", name: "Brown Rice", store: "Catalogue", price: 2, category: "grains", quantity: 1),
                    CartItem(id: UUID(), catalogId: "broccoli", name: "Broccoli", store: "Catalogue", price: 2, category: "vegetables", quantity: 1)]
        UserDefaults.standard.set(try JSONEncoder().encode(cart), forKey: "shoppingCart_v1")
        defer { UserDefaults.standard.removeObject(forKey: "shoppingCart_v1") }
        let plan = FallbackData.mealPlan(targetKcal: 2000, preferences: [], variation: 0)
        let lunch = try XCTUnwrap(plan.allDays.first?.plan.pietus)
        let foods = try XCTUnwrap(lunch.nutritionIngredients, "every food on the plate is matched to a record")
        XCTAssertEqual(foods.count, 3)
        XCTAssertEqual(lunch.portions?.count, 3)
        let today = try XCTUnwrap(MealPlan.from(weekly: plan)?.lunch.first)
        XCTAssertTrue(today.macrosAvailable, "the meal shows protein, carbs and fat and can be logged")
        XCTAssertGreaterThan(today.proteinG, 10)
    }

    // MARK: Workout mode

    func testIntervalRoundsShareTheirBlock() {
        let block = WorkoutExercise(name: "Bike intervals", sets: 3, reps: "1 min hard, 2 min easy", minutes: 9, restSeconds: 0, note: "")
        XCTAssertEqual(WorkoutModeModel.seconds(in: block), 180, "3 rounds in 9 minutes are 3 minutes each, not 9")
    }

    func testMobilityPrescriptionsAreReadAsSets() {
        let hold = WorkoutExercise(name: "Hip flexor stretch", sets: 0, reps: "2 × 30 sec each side", minutes: 0, restSeconds: 0, note: "")
        XCTAssertEqual(WorkoutModeModel.prescription(hold).sets, 2)
        XCTAssertEqual(WorkoutModeModel.seconds(in: hold), 30)
        let reps = WorkoutExercise(name: "Cat-cow", sets: 0, reps: "2 × 10", minutes: 0, restSeconds: 0, note: "")
        let prepared = WorkoutModeModel.prepare(reps, log: TrainingLogStore(defaults: UserDefaults(suiteName: "ReviewFixesTests")!))
        XCTAssertEqual(prepared.sets.count, 2)
        XCTAssertEqual(prepared.sets.first?.reps, 10)
    }

    func testATimedSetStoppedEarlyCountsTheTimeDone() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ReviewFixesTests.timer"))
        defaults.removePersistentDomain(forName: "ReviewFixesTests.timer")
        let plank = WorkoutExercise(name: "Plank", sets: 1, reps: "60 sec", minutes: 0, restSeconds: 0, note: "")
        let workout = Workout(title: "Core", summary: "", kind: .home, level: .beginner, durationMinutes: 5,
                              warmup: "", cooldown: "", exercises: [plank], safetyNote: "")
        let model = WorkoutModeModel(workout: workout, log: TrainingLogStore(defaults: defaults), defaults: defaults, tracksSession: false)
        let start = Date()
        model.startTimer(now: start)
        model.completeSet(now: start.addingTimeInterval(20))
        XCTAssertEqual(model.exercises[0].sets[0].seconds ?? 0, 20, accuracy: 1)
    }

    // MARK: Typing numbers

    func testArabicDigitsAreRead() {
        XCTAssertEqual(TypedNumber.parse("٧٠"), 70)
        XCTAssertEqual(TypedNumber.parse("٧٢٫٥"), 72.5)
        XCTAssertEqual(TypedNumber.parse("72,5"), 72.5)
    }
}
