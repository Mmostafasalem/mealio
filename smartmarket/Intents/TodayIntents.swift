import AppIntents
import SwiftUI

// MARK: - Calories left

/// Today's calorie numbers, worded for Siri.
nonisolated struct CaloriesLeftSummary: Equatable, Sendable {
    let eaten: Int
    /// 0 when there's no goal yet (onboarding not finished).
    let goal: Int

    var hasGoal: Bool { goal > 0 }
    var left: Int { max(goal - eaten, 0) }
    var over: Int { max(eaten - goal, 0) }
    var progress: Double { hasGoal ? min(Double(eaten) / Double(goal), 1) : 0 }

    func dialog(locale: Locale = .current) -> String {
        func n(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
        guard hasGoal else {
            let logged = eaten > 0 ? " You've eaten \(n(eaten)) kcal today." : ""
            return "Finish setting up Nourlo so it can work out your daily calorie goal." + logged
        }
        if eaten > goal { return "You're \(n(over)) kcal over today: \(n(eaten)) of \(n(goal)) eaten." }
        if eaten == goal { return "You've reached your goal today: \(n(eaten)) of \(n(goal)) eaten." }
        return "You have \(n(left)) kcal left today: \(n(eaten)) of \(n(goal)) eaten."
    }

    /// Read from the app's own data, in the app's process.
    @MainActor static func current(now: Date = Date()) -> CaloriesLeftSummary {
        let eaten = FoodLogStore.shared.entries(on: now).reduce(0) { $0 + $1.calories }
        let state = AppState.shared
        let goal = state.isOnboarded ? max(state.userProfile.dailyCalorieGoal, 0) : 0
        return CaloriesLeftSummary(eaten: eaten, goal: goal)
    }
}

/// "How many calories do I have left?" Answers without opening the app.
nonisolated struct CaloriesLeftIntent: AppIntent {
    static var title: LocalizedStringResource { "Calories left today" }
    static var description: IntentDescription {
        IntentDescription("Tells you how many calories you have left today, from what you've logged.", categoryName: "Food log")
    }
    static var openAppWhenRun: Bool { false }
    /// Health data: answered only on an unlocked device, never from the lock screen.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let summary = CaloriesLeftSummary.current()
        return .result(dialog: IntentDialog(stringLiteral: summary.dialog()), view: CaloriesLeftSnippet(summary: summary))
    }
}

struct CaloriesLeftSnippet: View {
    let summary: CaloriesLeftSummary

    var body: some View {
        HStack(spacing: Spacing.lg) {
            ZStack {
                Circle().stroke(Color.calorieAccent.opacity(0.18), lineWidth: 8)
                Circle().trim(from: 0, to: summary.progress)
                    .stroke(summary.over > 0 ? Color.brandDanger : Color.calorieAccent,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "flame.fill")
                    .foregroundStyle(summary.over > 0 ? Color.brandDanger : Color.calorieAccent)
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                if summary.hasGoal {
                    Text(summary.over > 0 ? "\(summary.over) kcal over" : "\(summary.left) kcal left")
                        .font(.title3.weight(.semibold)).monospacedDigit()
                    Text("\(summary.eaten) of \(summary.goal) kcal eaten")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text("No calorie goal yet").font(.headline)
                    Text("\(summary.eaten) kcal eaten today")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Today's meals

/// One planned meal, worded for Siri.
nonisolated struct PlannedMeal: Equatable, Sendable {
    let slot: MealSlotOption
    let name: String
    let kcal: Int
}

nonisolated enum TodaysMealsSummary {
    static func slotTitle(_ slot: MealSlotOption) -> String {
        switch slot {
        case .breakfast: return "breakfast"
        case .lunch: return "lunch"
        case .dinner: return "dinner"
        case .snacks: return "snacks"
        }
    }

    /// `meals` is nil when there's no plan for today at all.
    static func dialog(meals: [PlannedMeal]?, slot: MealSlotOption?, locale: Locale = .current) -> String {
        guard let meals, !meals.isEmpty else {
            return "No meal plan yet. Open Meals in Nourlo to make one."
        }
        func line(_ s: MealSlotOption) -> String? {
            let inSlot = meals.filter { $0.slot == s }
            guard !inSlot.isEmpty else { return nil }
            let kcal = inSlot.reduce(0) { $0 + $1.kcal }.formatted(.number.locale(locale))
            return inSlot.map(\.name).joined(separator: " and ") + ", \(kcal) kcal"
        }
        if let slot {
            guard let text = line(slot) else { return "Nothing is planned for \(slotTitle(slot)) today." }
            return "For \(slotTitle(slot)) today: \(text)."
        }
        let parts = MealSlotOption.allCases.compactMap { s in line(s).map { slotTitle(s).capitalized + ": " + $0 } }
        return "Today's plan. " + parts.joined(separator: ". ") + "."
    }

    /// Today's meals from the saved weekly plan, or nil when there's none.
    @MainActor static func current(now: Date = Date()) -> [PlannedMeal]? {
        guard let weekly = AppState.shared.weeklyMealPlan, let plan = MealPlan.from(weekly: weekly, date: now) else { return nil }
        func meals(_ entries: [MealEntry], _ slot: MealSlotOption) -> [PlannedMeal] {
            entries.map { PlannedMeal(slot: slot, name: $0.foodName, kcal: $0.calories) }
        }
        return meals(plan.breakfast, .breakfast) + meals(plan.lunch, .lunch) + meals(plan.dinner, .dinner) + meals(plan.snacks, .snacks)
    }
}

/// "What's for lunch?" Reads today's meal plan without opening the app.
struct TodaysMealsIntent: AppIntent {
    static var title: LocalizedStringResource { "Today's meals" }
    static var description: IntentDescription {
        IntentDescription("Tells you what's on today's meal plan, for one meal or the whole day.", categoryName: "Meals")
    }
    static var openAppWhenRun: Bool { false }
    /// Health data: answered only on an unlocked device, never from the lock screen.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Meal", description: "Leave empty for the whole day.")
    var meal: MealSlotOption?

    init() {}
    init(meal: MealSlotOption?) { self.meal = meal }

    static var parameterSummary: some ParameterSummary { Summary("Today's \(\.$meal)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        TodaysMealsSummary.result(for: meal)
    }
}

/// "What's for lunch?" The Siri phrase for one meal: App Shortcut phrases need
/// a non-optional parameter, so this is `TodaysMealsIntent` with the meal required.
struct MealPlanForMealIntent: AppIntent {
    static var title: LocalizedStringResource { "Planned meal" }
    static var description: IntentDescription {
        IntentDescription("Tells you what's planned today for one meal.", categoryName: "Meals")
    }
    static var openAppWhenRun: Bool { false }
    /// Health data: answered only on an unlocked device, never from the lock screen.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Meal", requestValueDialog: "Which meal?")
    var meal: MealSlotOption

    init() {}
    init(meal: MealSlotOption) { self.meal = meal }

    static var parameterSummary: some ParameterSummary { Summary("Today's \(\.$meal)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        TodaysMealsSummary.result(for: meal)
    }
}

extension TodaysMealsSummary {
    /// Siri's answer and snippet for one meal, or the whole day when `slot` is nil.
    @MainActor static func result(for slot: MealSlotOption?) -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let meals = current()
        let text = dialog(meals: meals, slot: slot)
        let shown = (meals ?? []).filter { slot == nil || $0.slot == slot }
        return .result(dialog: IntentDialog(stringLiteral: text), view: TodaysMealsSnippet(meals: shown, hasPlan: meals?.isEmpty == false))
    }
}

struct TodaysMealsSnippet: View {
    let meals: [PlannedMeal]
    let hasPlan: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if meals.isEmpty {
                Label(hasPlan ? "Nothing planned for this meal" : "No meal plan yet", systemImage: "fork.knife")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(meals.enumerated()), id: \.offset) { _, meal in
                    HStack(spacing: Spacing.md) {
                        Image(systemName: symbol(meal.slot))
                            .foregroundStyle(Color.calorieAccent)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TodaysMealsSummary.slotTitle(meal.slot).capitalized)
                                .font(.caption).foregroundStyle(.secondary)
                            Text(meal.name).font(.subheadline.weight(.medium)).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Text("\(meal.kcal) kcal").font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(Spacing.lg)
    }

    private func symbol(_ slot: MealSlotOption) -> String {
        switch slot {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .snacks: return "sparkles"
        }
    }
}
