import XCTest
@testable import smartmarket

/// "Pick your foods" opens with a ready list made from the diet and goal, and offers
/// nothing the diet rules out (tester feedback H1); Profile › Favourite foods uses the
/// same filter.
@MainActor
final class FoodChoicesTests: XCTestCase {

    private func ids(_ items: [CatalogItem]) -> Set<String> { Set(items.map(\.id)) }
    private func starter(_ diets: Set<DietaryPreference>, _ goal: WeightGoal = .maintain) -> [CatalogItem] {
        FoodChoices.starterList(diets: diets, goal: goal)
    }

    func testEveryDietAndGoalStartsWithAtLeastFiveEverydayFoods() {
        var combos: [Set<DietaryPreference>] = [[]] + DietaryPreference.allCases.map { [$0] }
        for a in DietaryPreference.allCases { for b in DietaryPreference.allCases where a.rawValue < b.rawValue { combos.append([a, b]) } }
        for diets in combos {
            for goal in WeightGoal.allCases {
                let list = starter(diets, goal)
                XCTAssertGreaterThanOrEqual(list.count, Constants.Onboarding.minimumFavorites, "\(diets) \(goal)")
                XCTAssertLessThanOrEqual(list.count, 40, "\(diets) \(goal)")
                XCTAssertEqual(Set(list).count, list.count, "no food twice")
                for item in list {
                    XCTAssertTrue(diets.allows(name: item.name, category: item.category.rawValue), "\(item.name) for \(diets)")
                }
            }
        }
    }

    func testAnOmnivoreListCoversEveryPartOfThePlan() {
        let list = starter([])
        XCTAssertTrue((25...40).contains(list.count), "\(list.count)")
        let roles = Set(list.compactMap { FallbackData.planRole(name: $0.name, category: $0.category.rawValue) })
        for role in ["grains", "fruits", "dairy", "eggs", "meat", "seafood", "legumes", "vegetables", "nuts"] {
            XCTAssertTrue(roles.contains(role), role)
        }
        XCTAssertTrue(ids(list).contains("oats"), "a breakfast grain")
    }

    func testVeganGetsNoDairyMeatEggsOrFishButPlantMilk() {
        let list = starter([.vegan])
        let categories = Set(list.map(\.category))
        XCTAssertTrue(categories.isDisjoint(with: [.meat, .seafood, .eggs]))
        for item in list where item.category == .dairy { XCTAssertTrue(FoodChoices.isPlantMilk(item), item.name) }
        XCTAssertTrue(ids(list).contains("oat-milk"))
        XCTAssertTrue(ids(list).contains("red-lentils"))
        // Offered: no Meat, Fish, Eggs or Dairy section; plant milk instead.
        let sections = FoodChoices.sections(diets: [.vegan])
        let sectionIDs = Set(sections.map(\.id))
        XCTAssertTrue(sectionIDs.isDisjoint(with: ["meat", "seafood", "eggs", "dairy"]), "\(sectionIDs)")
        let plant = sections.first { $0.id == "plantMilk" }
        XCTAssertEqual(plant?.title, "Plant milk")
        XCTAssertEqual(Set(plant?.items.map(\.id) ?? []), ["oat-milk", "almond-milk"])
        let offered = ids(FoodChoices.offeredItems(diets: [.vegan]))
        for id in ["greek-yogurt", "butter", "cheddar", "eggs-10", "chicken-breast", "salmon-fillet", "honey"] {
            XCTAssertFalse(offered.contains(id), id)
        }
    }

    func testVegetarianKeepsEggsAndDairyButNoMeatOrFish() {
        let list = starter([.vegetarian])
        XCTAssertTrue(Set(list.map(\.category)).isDisjoint(with: [.meat, .seafood]))
        XCTAssertTrue(ids(list).contains("eggs-10"))
        XCTAssertTrue(ids(list).contains("greek-yogurt"))
        let sectionIDs = Set(FoodChoices.sections(diets: [.vegetarian]).map(\.id))
        XCTAssertTrue(sectionIDs.isSuperset(of: ["eggs", "dairy"]))
        XCTAssertTrue(sectionIDs.isDisjoint(with: ["meat", "seafood"]))
    }

    func testLactoseFreeOffersPlantMilkInsteadOfDairy() {
        let sections = FoodChoices.sections(diets: [.lactoseFree])
        XCTAssertFalse(sections.contains { $0.id == "dairy" })
        XCTAssertTrue(sections.contains { $0.id == "plantMilk" })
        XCTAssertTrue(ids(starter([.lactoseFree])).contains("oat-milk"))
    }

    func testHalalOffersNoPork() {
        let offered = FoodChoices.offeredItems(diets: [.halal])
        for item in offered { XCTAssertFalse(["pork", "bacon", "ham", "salami", "sausage"].contains { item.name.lowercased().contains($0) }, item.name) }
        XCTAssertFalse(offered.contains { ["beer", "red-wine", "white-wine", "sparkling-wine", "lard"].contains($0.id) })
        // Halal meat is bought, so chicken is still offered; the ready list follows the plan's rule.
        XCTAssertTrue(ids(offered).contains("chicken-breast"))
        for item in starter([.halal]) { XCTAssertFalse(item.category == .meat, item.name) }
        XCTAssertFalse(ids(FoodChoices.offeredItems(diets: [.noPork])).contains("bacon"))
    }

    func testKetoHasNoHighCarbStaples() {
        let list = ids(starter([.keto]))
        for id in ["oats", "whole-grain-bread", "brown-rice", "potato", "spaghetti", "banana", "apple", "red-lentils", "oat-milk"] {
            XCTAssertFalse(list.contains(id), id)
        }
        XCTAssertTrue(list.contains("eggs-10"))
        XCTAssertTrue(list.contains("avocado"))
    }

    func testAllergiesAndGlutenFreeAreStrict() {
        let nut = FoodChoices.offeredItems(diets: [.nutAllergy])
        XCTAssertFalse(nut.contains { $0.category == .nuts })
        XCTAssertFalse(ids(nut).contains("almond-milk"))
        XCTAssertFalse(ids(nut).contains("peanut-butter"))
        let gf = ids(starter([.glutenFree]))
        for id in ["oats", "whole-grain-bread", "spaghetti", "rye-bread"] { XCTAssertFalse(gf.contains(id), id) }
        XCTAssertTrue(gf.contains("buckwheat"))
        XCTAssertFalse(FoodChoices.sections(diets: [.shellfishAllergy]).flatMap(\.items).contains { $0.id == "shrimp" })
        let paleo = FoodChoices.sections(diets: [.paleo]).map(\.id)
        XCTAssertFalse(paleo.contains("dairy") || paleo.contains("plantMilk") || paleo.contains("legumes") || paleo.contains("grains"))
    }

    func testGoalShapesTheList() {
        let lose = starter([], .lose), gain = starter([], .gain)
        func count(_ list: [CatalogItem], _ role: String) -> Int {
            list.filter { FallbackData.planRole(name: $0.name, category: $0.category.rawValue) == role }.count
        }
        XCTAssertGreaterThan(count(lose, "vegetables"), count(gain, "vegetables"))
        XCTAssertGreaterThan(count(gain, "nuts"), count(lose, "nuts"))
        XCTAssertEqual(lose.first { $0.category == .meat }?.id, "chicken-breast", "lean protein first")
    }

    // MARK: Onboarding

    func testOnboardingOpensPreselectedAndCanFinish() {
        let vm = OnboardingViewModel()
        vm.selectedPreferences = [.vegan]
        vm.prepareFavorites()
        XCTAssertEqual(vm.favoriteFoodIDs, ids(starter([.vegan])))
        XCTAssertTrue(vm.canFinish, "the ready list already meets the minimum")
        XCTAssertFalse(vm.foodSections.contains { $0.id == "dairy" || $0.id == "meat" })
        // Deselect, star and add.
        let oatMilk = CatalogItem.all.first { $0.id == "oat-milk" }!
        vm.toggleFavorite(oatMilk)
        XCTAssertFalse(vm.favoriteFoodIDs.contains("oat-milk"))
        XCTAssertTrue(vm.yourList.contains(oatMilk), "a food taken off stays shown so it can go back")
        vm.toggleStar(oatMilk)
        XCTAssertTrue(vm.favoriteFoodIDs.contains("oat-milk") && vm.starredFoodIDs.contains("oat-milk"))
        let kale = CatalogItem.all.first { $0.id == "tofu" || $0.id == "kale" }!
        if !vm.favoriteFoodIDs.contains(kale.id) { vm.toggleFavorite(kale) }
        XCTAssertTrue(vm.yourList.contains(kale))
        // An edited list isn't replaced when the person goes back and comes again.
        let edited = vm.favoriteFoodIDs
        vm.prepareFavorites()
        XCTAssertEqual(vm.favoriteFoodIDs, edited)
    }

    func testChangingTheDietBeforeEditingRebuildsTheList() {
        let vm = OnboardingViewModel()
        vm.prepareFavorites()
        XCTAssertTrue(vm.favoriteFoodIDs.contains("chicken-breast"))
        vm.selectedPreferences = [.vegetarian]
        vm.prepareFavorites()
        XCTAssertFalse(vm.favoriteFoodIDs.contains("chicken-breast"))
        XCTAssertEqual(vm.favoriteFoodIDs, ids(starter([.vegetarian])))
    }

    func testAnEditedListDropsWhatANewDietRulesOut() {
        let vm = OnboardingViewModel()
        vm.prepareFavorites()
        vm.toggleFavorite(CatalogItem.all.first { $0.id == "bacon" }!)
        vm.selectedPreferences = [.halal]
        vm.prepareFavorites()
        XCTAssertFalse(vm.favoriteFoodIDs.contains("bacon"))
        XCTAssertTrue(vm.canFinish)
    }

    // MARK: Profile uses the same filter

    func testProfileSectionsAreTheOnboardingSections() {
        for diets in [Set<DietaryPreference>(), [.vegan], [.halal, .nutAllergy], [.keto]] {
            let vm = OnboardingViewModel()
            vm.selectedPreferences = diets
            vm.prepareFavorites()
            XCTAssertEqual(vm.foodSections, FoodChoices.sections(diets: diets))
            XCTAssertEqual(vm.offeredItems, FoodChoices.sections(diets: diets).flatMap(\.items))
        }
    }

    func testStarredFoodsComeFirstOnATightBudget() {
        let favourites: Set<String> = ["chicken-breast", "turkey-breast", "salmon-fillet"]
        let price: (CatalogItem) -> Double = { $0.estimatedPrice(for: .catalog) }
        let plain = WeeklyGroceryPlanner.plan(budget: 12, cart: [], favourites: favourites, preferences: [], price: price)
        let starred = WeeklyGroceryPlanner.plan(budget: 12, cart: [], favourites: favourites, preferences: [],
                                                starred: ["salmon-fillet"], price: price)
        XCTAssertTrue(starred.lines.contains { $0.id == "salmon-fillet" }, "\(starred.lines.map(\.id))")
        XCTAssertNotEqual(plain.lines.map(\.id), starred.lines.map(\.id))
    }
}
