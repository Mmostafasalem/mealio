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

    /// The day shown, as days from today (0 = today … 6), picked in the day strip.
    var selectedDay = 0
    var todaysPlan: MealPlan?
    var weekPlans: [MealPlan] = []
    var isGenerating = false
    var errorMessage: String?
    /// Said under the button when another plan can't differ (one food for each part of the plate).
    var notice: String?
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
        guard !isGenerating else { return }
        errorMessage = nil
        notice = nil
        let before = Self.fingerprint(AppState.shared.weeklyMealPlan)
        // The next pairing of the same foods: a new plan even when the kitchen hasn't changed.
        let key = FallbackData.variationKey
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) &+ 1, forKey: key)
        // Preserve the saved plan until its replacement is ready.
        await fetchTodaysPlan()
        if errorMessage == nil, before != nil, Self.fingerprint(AppState.shared.weeklyMealPlan) == before {
            notice = "Same plan: there's one food for each part of the plate. Add more foods to your cart or stock for variety."
        }
        await loadWeekPlans()
    }

    /// What a plan shows (each meal's name and portions), to tell whether a new one differs.
    static func fingerprint(_ plan: WeeklyMealPlan?) -> Data? {
        guard let plan else { return nil }
        let text = plan.allDays.map(\.plan).flatMap { day in
            [day.pusryciai, day.pietus, day.vakariene, day.uzkandziai].map { meal in
                meal.map { $0.pavadinimas + ":" + $0.ingredientai.joined(separator: ",") } ?? "-"
            }
        }.joined(separator: "|")
        return Data(text.utf8)
    }

    static let offlinePlanNotice = "Couldn't reach the planner. Showing an offline plan."

    private func fetchTodaysPlan() async {
        guard !isGenerating else { return }
        let appState = AppState.shared
        // One shared slot with the agent loop; the user's request takes over
        // from a background one instead of racing it.
        guard let ticket = appState.beginMealPlanRequest(.user) else { return }
        let generation = appState.dataGeneration
        profile = .load()
        groceryList = GroceryStorage.load()
        isGenerating = true
        errorMessage = nil
        defer {
            isGenerating = false
            appState.endMealPlanRequest(ticket)
        }
        do {
            let builtFor = AgentLoop.PlanInputs.current(appState)
            let request = MealPlanRequest.current(profile: profile, bmr: appState.bmrData)
            // Built on the phone from the cart, stock and preferences (no online AI for plans).
            var weekly = FallbackData.mealPlan(targetKcal: request.bmrData.calories(forGoal: request.goal))
            weekly.generationSource = "local"
            try Task.checkCancellation()
            guard appState.dataGeneration == generation, appState.ownsMealPlanRequest(ticket) else { return }
            todaysPlan = MealPlan.from(weekly: weekly)
            appState.saveMealPlan(weekly)
            AgentLoop.recordPlanInputs(builtFor)
        } catch {
            appLog("[MealPlan] load failed:", error)
            errorMessage = "Could not update your meal plan. Your saved plan is kept; please try again."
        }
    }

    // MARK: - Recommendations

    /// Online shopping advice is off (online AI is only for chat and recipes).
    static let onlineShoppingAdvice = false

    func loadRecommendations() async {
        guard recommendations.isEmpty, Self.onlineShoppingAdvice else { return }
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

    /// Remaining intake is based on food actually logged today, never purchases.
    func computeNutritionalGaps() -> NutritionalGaps {
        FoodLogStore.shared.reload()
        return nutritionalGaps(entries: FoodLogStore.shared.entries)
    }

    func nutritionalGaps(entries: [FoodLogEntry]) -> NutritionalGaps {
        let isKeto = Set<DietaryPreference>.load().contains(.keto)
        let targets = BMRCalculator.macroTargets(calories: goal, isKeto: isKeto)
        return NutritionalGaps(
            caloriesNeeded: max(goal - entries.reduce(0) { $0 + $1.calories }, 0),
            proteinNeeded: max(Double(targets.proteinG) - entries.reduce(0) { $0 + $1.proteinG }, 0),
            carbsNeeded: max(Double(targets.carbsG) - entries.reduce(0) { $0 + $1.carbsG }, 0),
            fatNeeded: max(Double(targets.fatG) - entries.reduce(0) { $0 + $1.fatG }, 0)
        )
    }

    // MARK: - Week plan

    /// The next seven days, starting today: each weekday's plan on its next date.
    static func buildWeek(from weekly: WeeklyMealPlan, now: Date = Date(), calendar: Calendar = .current) -> [MealPlan] {
        // Index = weekday - 1 (Sunday first, as Calendar numbers them).
        let dayPlans: [DayPlan?] = [weekly.sekmadienis, weekly.pirmadienis, weekly.antradienis, weekly.treciadienis,
                                    weekly.ketvirtadienis, weekly.pentadienis, weekly.sestadienis]
        let todayIndex = calendar.component(.weekday, from: now) - 1
        return dayPlans.enumerated().compactMap { idx, day -> MealPlan? in
            guard let day else { return nil }
            let offset = (idx - todayIndex + 7) % 7
            return MealPlan.from(day: day, date: calendar.date(byAdding: .day, value: offset, to: now) ?? now,
                                 notes: weekly.agentMessage ?? "")
        }
        .sorted { $0.date < $1.date }
    }

    func loadWeekPlans() async {

        func buildWeekPlans(from weekly: WeeklyMealPlan) -> [MealPlan] { Self.buildWeek(from: weekly) }

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
        weekPlans = []
    }

    // MARK: - Add recommendations to grocery list

    func addAllToGroceryList() {
        addToGroceryList(recommendations)
    }

    /// Adds the given recommendations (skipping names already on the list).
    func addToGroceryList(_ items: [ShoppingRecommendation]) {
        var list = GroceryStorage.load()
        for rec in items {
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
