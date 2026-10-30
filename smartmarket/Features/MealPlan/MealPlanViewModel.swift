import SwiftUI
import Observation

enum MealPlanTab: String, CaseIterable, Identifiable {
    case today
    case week
    var id: String { rawValue }
    var displayName: String { self == .today ? "Today" : "This Week" }
}

@MainActor
@Observable
final class MealPlanViewModel {

    var selectedTab: MealPlanTab = .today
    var todaysPlan: MealPlan?
    var weekPlans: [MealPlan] = []
    var isGenerating = false
    var errorMessage: String?
    var recommendations: [ShoppingRecommendation] = []
    var profile: UserProfile = .load()
    var groceryList: [GroceryItem] = GroceryStorage.load()

    var goal: Int { max(profile.dailyCalorieGoal, 1) }

    // MARK: - Today's plan

    func loadTodaysPlan() async {
        // Always apply the latest plan from AppState (covers agent-regenerated plans).
        if let weekly = AppState.shared.weeklyMealPlan {
            todaysPlan = MealPlan.from(weekly: weekly)
            return
        }
        // Only hit the network if we have no plan at all yet.
        if todaysPlan == nil {
            await fetchTodaysPlan()
        }
    }

    func regenerate() async {
        todaysPlan  = nil
        weekPlans   = []
        errorMessage = nil
        // Clear cache and daily-refresh gate so backend is always hit fresh
        UserDefaults.standard.removeObject(forKey: Constants.Storage.currentMealPlan)
        UserDefaults.standard.removeObject(forKey: "lastMealPlanGeneratedDate")
        AppState.shared.weeklyMealPlan = nil
        await fetchTodaysPlan()
    }

    private func fetchTodaysPlan() async {
        let generation = AppState.shared.dataGeneration
        profile = .load()
        groceryList = GroceryStorage.load()
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            // Read actual user preferences
            let favNames = ProductCatalogService.shared.nameFor(ids: AppState.shared.favoriteFoodIDs)
            let dietaryPrefs = Set<DietaryPreference>.load()
            let dietOptions = dietaryPrefs.filter { !$0.isAllergy }.map { $0.rawValue }
            let allergies = dietaryPrefs.filter { $0.isAllergy }.map { $0.rawValue }
            // Prefer the Shop cart (what the user is buying) for the plan.
            let cartDeals = ShoppingCartService.shared.planDeals()
            let groceriesForPlan = cartDeals.isEmpty ? AppState.shared.groceryList : cartDeals

            let request = MealPlanRequest(
                user: MealPlanUser(
                    name:           "",
                    age:            profile.age,
                    gender:         profile.gender == .male ? "male" : "female",
                    weight:         profile.weight,
                    height:         profile.height,
                    goal:           profile.weightGoal.rawValue,
                    activityLevel:  profile.activityLevel.rawValue,
                    dietaryOptions: dietOptions,
                    allergies:      allergies,
                    favoriteFoods:  favNames
                ),
                bmrData: AppState.shared.bmrData ?? BMRResponse(
                    bmr:              Int(profile.bmr),
                    tdee:             Int(profile.tdee),
                    loseCalories:     max(Int(profile.tdee) - 350, 1200),
                    maintainCalories: Int(profile.tdee),
                    gainCalories:     Int(profile.tdee) + 350,
                    macros: BMRResponse.MacroTargets(protein: 150, carbs: 200, fat: 60)
                ),
                groceryList: groceriesForPlan,
                goal: profile.weightGoal.rawValue,
                lang: AppState.shared.lang
            )
            let weekly = try await APIService.shared.generateMealPlan(request)
            guard !Task.isCancelled, AppState.shared.dataGeneration == generation else { return }
            todaysPlan = MealPlan.from(weekly: weekly)
            AppState.shared.saveMealPlan(weekly)
        } catch {
            appLog("[MealPlan] load failed:", error)
            errorMessage = "Could not load your meal plan. Tap to retry."
        }
    }

    // MARK: - Recommendations

    func loadRecommendations() async {
        guard recommendations.isEmpty else { return }
        do {
            let gaps = computeNutritionalGaps()
            let adviceRequest = ShoppingAdviceRequest(
                groceryList: AppState.shared.groceryList,
                goal: profile.weightGoal.rawValue,
                macros: BMRResponse.MacroTargets(
                    protein: Int(gaps.proteinNeeded),
                    carbs:   Int(gaps.carbsNeeded),
                    fat:     Int(gaps.fatNeeded)
                ),
                lang: AppState.shared.lang
            )
            let advice = try await APIService.shared.getShoppingAdvice(adviceRequest)
            recommendations = advice.enumerated().map { idx, a in
                ShoppingRecommendation(
                    id: "\(idx)",
                    foodName:       a.produktas,
                    reason:         a.priezastis,
                    storeName:      a.kurPirkti,
                    estimatedPrice: Double(a.apytiksleCena.filter { $0.isNumber || $0 == "." }) ?? 0,
                    priority:       idx + 1
                )
            }
        } catch {
            appLog("[MealPlan] recommendations failed:", error)
            recommendations = []
        }
    }

    // MARK: - Nutritional gaps

    /// Estimates how far the current grocery list is from the daily targets,
    /// using one typical serving per grocery item resolved against the food catalog.
    func computeNutritionalGaps() -> NutritionalGaps {
        let isKeto = Set<DietaryPreference>.load().contains(.keto)
        let targets = BMRCalculator.macroTargets(calories: goal, isKeto: isKeto)

        var calories = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
        let index = productCatalogIndex
        for item in groceryList {
            guard let product = index[item.foodId] else { continue }
            let factor = 200.0 / 100.0  // assume 200g serving if not specified
            calories += Double(product.kcalPer100g) * factor
            protein  += product.proteinPer100g * factor
            carbs    += product.carbsPer100g * factor
            fat      += product.fatPer100g * factor
        }

        return NutritionalGaps(
            caloriesNeeded: max(goal - Int(calories), 0),
            proteinNeeded: max(Double(targets.proteinG) - protein, 0),
            carbsNeeded: max(Double(targets.carbsG) - carbs, 0),
            fatNeeded: max(Double(targets.fatG) - fat, 0)
        )
    }

    // MARK: - Week plan

    // Nutritional gap computation uses the live catalog for accurate macro data
    private var productCatalogIndex: [String: Product] {
        Dictionary(uniqueKeysWithValues: ProductCatalogService.shared.products.map { ($0.id, $0) })
    }

    func loadWeekPlans() async {

        func buildWeekPlans(from weekly: WeeklyMealPlan) -> [MealPlan] {
            let dayPlans: [DayPlan?] = [
                weekly.sekmadienis,
                weekly.pirmadienis,
                weekly.antradienis,
                weekly.treciadienis,
                weekly.ketvirtadienis,
                weekly.pentadienis,
                weekly.sestadienis
            ]
            let _ = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
            return dayPlans.enumerated().compactMap { idx, day in
                guard let day else { return nil }
                func entry(_ item: MealItem?) -> [MealEntry] {
                    guard let item else { return [] }
                    return [MealEntry(id: UUID().uuidString,
                                     foodName: item.pavadinimas,
                                     portionG: 0,
                                     calories: item.kcal,
                                     proteinG: 0,
                                     carbsG:   0,
                                     fatG:     0,
                                     notes:    item.ingredientai.joined(separator: ", "))]
                }
                return MealPlan(id: UUID().uuidString,
                                date: Calendar.current.date(byAdding: .day, value: idx, to: Date()) ?? Date(),
                                breakfast: entry(day.pusryciai),
                                lunch:     entry(day.pietus),
                                dinner:    entry(day.vakariene),
                                snacks:    entry(day.uzkandziai),
                                totalCalories:  day.visoKcal ?? 0,
                                totalProteinG:  0,
                                totalCarbsG:    0,
                                totalFatG:      0,
                                agentNotes:     weekly.agentMessage ?? "")
            }
        }

        // Try persisted WeeklyMealPlan
        if let data = UserDefaults.standard.data(forKey: Constants.Storage.currentMealPlan),
           let weekly = try? JSONDecoder().decode(WeeklyMealPlan.self, from: data) {
            let plans = buildWeekPlans(from: weekly)
            if !plans.isEmpty { weekPlans = plans; return }
        }
        // Try in-memory AppState
        if let weekly = AppState.shared.weeklyMealPlan {
            let plans = buildWeekPlans(from: weekly)
            if !plans.isEmpty { weekPlans = plans; return }
        }
        #if DEBUG
        weekPlans = Self.mockedWeekPlans(goal: goal)
        #endif
    }

    private static func mockedWeekPlans(goal: Int) -> [MealPlan] {
        let _: [(String, [(String, Int, Double, Double, Double, String?)])] = [
            ("Breakfast", [("Oats with banana", 350, 12, 55, 6, nil)]),
            ("Lunch",     [("Chicken breast with rice", 550, 45, 60, 10, "Grilled")]),
            ("Dinner",    [("Salmon with vegetables", 480, 38, 30, 18, "Baked")]),
            ("Snacks",    [("Apple", 80, 0.5, 20, 0.3, nil)]),
        ]
        let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let dayTemplates: [(String, String, String, String)] = [
            ("Oats with banana",         "Chicken breast with rice", "Salmon with vegetables",   "Apple"),
            ("Scrambled eggs",           "Tuna salad",               "Pasta with tomato sauce",  "Yogurt"),
            ("Avocado toast",            "Lentil soup",              "Beef steak",               "Almonds"),
            ("Protein shake",            "Rice with chicken",        "Baked hake",               "Banana"),
            ("Spanish omelette",         "Turkey sandwich",          "Light homemade pizza",     "Orange"),
            ("Oat pancakes",             "Caesar salad",             "Grilled ribs",             "Mixed nuts"),
            ("Salmon toast",             "Gazpacho with ham",        "Roast chicken & potatoes", "Kefir"),
        ]

        let calendar = Calendar.current
        let today = Date()
        let weekdayOffset = calendar.component(.weekday, from: today) - 2 // Mon=0 offset

        func entry(_ name: String, _ cal: Int, _ protein: Double, _ carbs: Double, _ fat: Double, _ notes: String?) -> MealEntry {
            MealEntry(
                id: UUID().uuidString,
                foodName: name,
                portionG: 200,
                calories: cal,
                proteinG: protein,
                carbsG: carbs,
                fatG: fat,
                notes: notes
            )
        }

        return dayTemplates.enumerated().map { idx, names in
            let (bName, lName, dName, sName) = names
            let date = calendar.date(byAdding: .day, value: idx - weekdayOffset, to: today) ?? today

            let bCal = Int(Double(goal) * 0.25)
            let lCal = Int(Double(goal) * 0.35)
            let dCal = Int(Double(goal) * 0.30)
            let sCal = goal - bCal - lCal - dCal

            let b = [entry(bName, bCal, Double(bCal)*0.25/4, Double(bCal)*0.45/4, Double(bCal)*0.30/9, nil)]
            let l = [entry(lName, lCal, Double(lCal)*0.30/4, Double(lCal)*0.40/4, Double(lCal)*0.30/9, "Grilled")]
            let d = [entry(dName, dCal, Double(dCal)*0.30/4, Double(dCal)*0.40/4, Double(dCal)*0.30/9, "Baked")]
            let s = [entry(sName, sCal, Double(sCal)*0.10/4, Double(sCal)*0.60/4, Double(sCal)*0.30/9, nil)]
            let all = b + l + d + s

            return MealPlan(
                id: UUID().uuidString,
                date: date,
                breakfast: b,
                lunch: l,
                dinner: d,
                snacks: s,
                totalCalories: goal,
                totalProteinG: all.reduce(0) { $0 + $1.proteinG },
                totalCarbsG:   all.reduce(0) { $0 + $1.carbsG },
                totalFatG:     all.reduce(0) { $0 + $1.fatG },
                agentNotes: "\(dayNames[idx]): balanced \(goal) kcal plan."
            )
        }
    }

    // MARK: - Add recommendations to grocery list

    func addAllToGroceryList() {
        var list = GroceryStorage.load()
        for rec in recommendations {
            guard !list.contains(where: { $0.foodName == rec.foodName }) else { continue }
            list.append(GroceryItem(
                id: UUID().uuidString,
                foodId: rec.id,
                foodName: rec.foodName,
                quantity: "1 serving",
                estimatedPrice: rec.estimatedPrice,
                storeId: rec.storeName,
                storeName: rec.storeName,
                isBought: false
            ))
        }
        GroceryStorage.save(list)
        groceryList = list
    }
}
