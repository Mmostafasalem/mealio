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
        guard !isGenerating else { return }
        errorMessage = nil
        // Preserve the saved plan until its replacement is ready.
        await fetchTodaysPlan()
        if selectedTab == .week { await loadWeekPlans() }
    }

    private func fetchTodaysPlan() async {
        guard !isGenerating else { return }
        let generation = AppState.shared.dataGeneration
        profile = .load()
        groceryList = GroceryStorage.load()
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            let request = MealPlanRequest.current(profile: profile, bmr: AppState.shared.bmrData)
            let weekly = try await APIService.shared.generateMealPlan(request)
            guard !Task.isCancelled, AppState.shared.dataGeneration == generation else { return }
            todaysPlan = MealPlan.from(weekly: weekly)
            AppState.shared.saveMealPlan(weekly)
            AgentLoop.markPlanGeneratedToday()
        } catch {
            appLog("[MealPlan] load failed:", error)
            errorMessage = "Could not update your meal plan. Your saved plan is kept. Check the AI connection in Profile, then retry."
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
                let weekday = Calendar.current.component(.weekday, from: Date()) - 1
                let offset = (idx - weekday + 7) % 7
                return MealPlan.from(day: day,
                                     date: Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date(),
                                     notes: weekly.agentMessage ?? "")
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
        weekPlans = []
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
