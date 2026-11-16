import SwiftUI

struct MealPlanView: View {

    @State private var vm = MealPlanViewModel()
    /// One meal open at a time, across every section.
    @State private var expandGroup = ExpandCardGroup()
    /// Last title shown per meal slot, so only titles a new plan changed decode.
    @State private var titleMemory = ScrambleMemory()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("aiSharingConsent_v1") private var aiSharingConsent = false
    @AppStorage("ownerAISharingConsent_v1") private var ownerAISharingConsent = false

    private var sharingEnabled: Bool {
        OwnerAITestConfiguration.current == nil ? aiSharingConsent : ownerAISharingConsent
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                if !sharingEnabled {
                    Label("Online AI sharing is off. Local suggestions are shown. You can enable online AI in Profile.", systemImage: "iphone")
                        .font(.footnote).foregroundStyle(Color.labelSecondary)
                        .padding(.horizontal, Spacing.lg)
                } else if AppState.shared.weeklyMealPlan?.generationSource != "online" {
                    Label("Local meal suggestions. A verified AI-generated plan is not currently shown.", systemImage: "iphone")
                        .font(.footnote).foregroundStyle(Color.labelSecondary)
                        .padding(.horizontal, Spacing.lg)
                }
                if let message = vm.errorMessage, vm.todaysPlan != nil {
                    Text(message).font(.footnote).foregroundStyle(Color.brandDanger)
                        .padding(.horizontal, Spacing.lg)
                }
                SpringSegmentedControl(
                    selection: $vm.selectedTab,
                    options: MealPlanTab.allCases,
                    label: \.displayName
                )
                .padding(.horizontal, Spacing.lg)

                if vm.isGenerating && vm.todaysPlan != nil {
                    HStack(spacing: Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Updating plan…").font(.footnote)
                    }
                    .foregroundStyle(Color.labelSecondary)
                    .transition(.opacity)
                }
                switch vm.selectedTab {
                case .today: todayContent
                case .week:  weekContent
                }
            }
            .padding(.vertical, Spacing.lg)
            .animation(reduceMotion ? .none : .snappyValue, value: vm.selectedTab)
            .animation(reduceMotion ? .reducedFade : .snappyValue, value: vm.isGenerating)
        }
        .background { GrainyGradient().ignoresSafeArea() }
        .navigationTitle("Meal Plan")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink("My Stock") { StockView() } } }
        .task {
            if vm.todaysPlan == nil { await vm.loadTodaysPlan() }
        }
        .task(id: vm.selectedTab) {
            if vm.selectedTab == .week { await vm.loadWeekPlans() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mealPlanDidUpdate)) { _ in
            Task {
                await vm.loadTodaysPlan()
                if vm.selectedTab == .week { await vm.loadWeekPlans() }
            }
        }
    }

    // MARK: - Today

    @ViewBuilder
    private var todayContent: some View {
        if vm.isGenerating && vm.todaysPlan == nil {
            SkeletonMealPlanContent()
        } else if let errorMessage = vm.errorMessage, vm.todaysPlan == nil {
            ErrorStateView(message: errorMessage) { Task { await vm.loadTodaysPlan() } }
                .padding(.top, Spacing.xxl)
        } else if let plan = vm.todaysPlan {
            VStack(spacing: Spacing.lg) {
                // New identity per plan content, so a regenerated plan cross-fades in.
                VStack(spacing: Spacing.lg) {
                    ForEach(Array(plan.allMeals.enumerated()), id: \.offset) { _, meal in
                        MealSectionCard(title: meal.title, sfSymbol: meal.sfSymbol, entries: meal.entries,
                                        expandGroup: expandGroup, titleMemory: titleMemory)
                    }
                }
                .id(planGenerationToken(plan))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))

                WhyThisPlanCard(notes: plan.agentNotes)

                if !vm.recommendations.isEmpty {
                    RecommendationsSection(items: vm.recommendations,
                                           onAdd: { vm.addToGroceryList([$0]) },
                                           onAddAll: { vm.addToGroceryList($0) })
                }

                RegenerateButton(isGenerating: vm.isGenerating) {
                    Task { await vm.regenerate() }
                }

                Text("Calorie & macro values are estimates and may vary by product and preparation.")
                    .font(.caption2)
                    .foregroundStyle(Color.labelTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .padding(.horizontal, Spacing.lg)
            .animation(.smoothCard, value: planGenerationToken(plan))
            // A new plan starts with every meal folded.
            .onChange(of: planGenerationToken(plan)) { _, _ in expandGroup.show(nil, animated: false) }
        } else {
            EmptyStateView(icon: "fork.knife", title: "No meal plan yet",
                           message: "Generate a plan tailored to your goals and favourite foods.",
                           actionTitle: "Generate Plan") { Task { await vm.loadTodaysPlan() } }
                .padding(.top, Spacing.xxl)
        }
    }

    /// Changes only when the plan's meals change (not on a reload of the same plan).
    private func planGenerationToken(_ plan: MealPlan) -> String {
        plan.allMeals
            .flatMap { meal in meal.entries.map { "\(meal.title):\($0.foodName):\($0.portionG)" } }
            .joined(separator: "|")
    }

    // MARK: - Week

    @ViewBuilder
    private var weekContent: some View {
        if vm.weekPlans.isEmpty {
            if vm.isGenerating {
                SkeletonWeekContent().padding(.horizontal, Spacing.lg)
            } else {
                EmptyStateView(icon: "calendar", title: "No week plan yet",
                               message: "Generate seven days of meals built around your goals and favourite foods.",
                               actionTitle: "Generate week") { Task { await vm.regenerate() } }
                    .padding(.top, Spacing.xxl)
            }
        } else {
            VStack(spacing: Spacing.lg) {
                ForEach(vm.weekPlans) { plan in
                    WeekDayCard(plan: plan)
                }
                // One request writes all seven days.
                RegenerateButton(isGenerating: vm.isGenerating, idleTitle: "Regenerate week") {
                    Task { await vm.regenerate() }
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
    }
}

// MARK: - Meal section

private struct MealSectionCard: View {
    let title: String
    let sfSymbol: String
    let entries: [MealEntry]
    let expandGroup: ExpandCardGroup
    let titleMemory: ScrambleMemory
    @State private var expanded = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var accentColor: Color {
        switch sfSymbol {
        case "sunrise.fill": return .carbsAccent
        case "sun.max.fill": return .calorieAccent
        case "moon.fill":    return .fatAccent
        case "sparkles":     return .proteinAccent
        default:             return .brandPrimary
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 8) {
                if entries.isEmpty {
                    Text("Nothing planned")
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    MealEntryRow(entry: entry, slot: title == "Breakfast" ? .breakfast : title == "Lunch" ? .lunch : title == "Dinner" ? .dinner : .snack,
                                 slotKey: "\(title)#\(index)", expandGroup: expandGroup, titleMemory: titleMemory)
                }
            }
            .padding(.top, 8)
        } label: {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
                : AnyLayout(HStackLayout(spacing: Spacing.md))
            headerLayout {
                Image(systemName: sfSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 34, height: 34)
                    .background(accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(title).font(.headline)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Text("\(entries.reduce(0) { $0 + $1.calories }) kcal")
                    .font(.subheadline).foregroundStyle(Color.labelSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .tint(.primary)
        .padding(Spacing.lg)
        .premiumCard(radius: Radius.tile)
    }
}

private struct MealEntryRow: View {
    let entry: MealEntry
    let slot: MealSlot
    /// Stable per slot position ("Lunch#0"), so a new plan's title can decode in.
    let slotKey: String
    let expandGroup: ExpandCardGroup
    let titleMemory: ScrambleMemory

    private enum RowSheet: String, Identifiable {
        case recipe, stock
        var id: String { rawValue }
    }

    @State private var sheet: RowSheet?
    @State private var stock = StockStore.shared
    @State private var addedNotice: String?
    @State private var addedTrigger = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var ingredients: [NutritionIngredient] { entry.nutritionIngredients ?? [] }
    private var cardID: String { slotKey + "|" + entry.id }

    private var subtitle: String {
        entry.notes?.isEmpty == false ? entry.notes! : (entry.portionG > 0 ? "\(entry.portionG) g" : "Portion not specified")
    }

    var body: some View {
        ExpandCard(id: cardID, group: expandGroup,
                   accessibilityLabel: "\(entry.foodName), \(subtitle), \(entry.calories) kcal",
                   hint: "Shows ingredients, portions and macros") { p in
            header(p)
        } detail: {
            detail
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .stock: PlannedMealStockSheet(entry: entry, slot: slot)
            case .recipe: RecipeSheet(mealName: entry.foodName)
            }
        }
    }

    // MARK: Header

    private func header(_ p: Double) -> some View {
        let q = motionClamp(p, 0, 1)
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Spacing.md))
        return rowLayout {
            VStack(alignment: .leading, spacing: 2) {
                ScrambleText(text: entry.foodName, key: slotKey, memory: titleMemory,
                             font: .subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption).foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The title rides up a little as the card opens.
            .offset(y: -2 * q)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                Text("\(entry.calories) kcal")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color.labelSecondary).monospacedDigit()
                // The macro summary moves into the details while open.
                Group {
                    // Nothing extra when a meal has only an estimated calorie figure.
                    if entry.macrosAvailable {
                        Text("Calculated from ingredient portions")
                            .font(.caption2).foregroundStyle(Color.labelSecondary)
                        Text("P\(Int(entry.proteinG))  C\(Int(entry.carbsG))  F\(Int(entry.fatG))")
                            .font(.caption2).foregroundStyle(Color.labelTertiary).monospacedDigit()
                    }
                }
                .opacity(1 - q)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color.labelTertiary)
                    .rotationEffect(.degrees(90 * q))
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: Details

    private var detail: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Divider().overlay(Color.hairline)
            if !ingredients.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Ingredients").font(.caption.weight(.semibold)).foregroundStyle(Color.labelSecondary)
                    ForEach(ingredients) { ingredient in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            Text(ingredient.food.name)
                                .font(.subheadline).foregroundStyle(Color.labelPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Spacing.sm)
                            Text("\(ingredient.amount.formatted()) \(ingredient.food.basis.rawValue)")
                                .font(.caption.weight(.medium)).foregroundStyle(Color.labelSecondary)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            macros
            actions
            if let addedNotice {
                Label(addedNotice, systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xs)
    }

    @ViewBuilder private var macros: some View {
        if entry.macrosAvailable {
            let chips = [("Protein", entry.proteinG), ("Carbs", entry.carbsG), ("Fat", entry.fatG)]
            FlowLayout(spacing: 6) {
                ForEach(chips, id: \.0) { chip in
                    Text("\(chip.0) \(chip.1.formatted(.number.precision(.fractionLength(0...1)))) g")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.labelPrimary)
                        .monospacedDigit()
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.surfaceSecondary, in: Capsule())
                }
            }
        }
    }

    private var missing: [NutritionIngredient]? {
        guard entry.macrosAvailable else { return nil }
        if let id = entry.stockOperationID, stock.hasLoggedMeal(id) { return [] }
        return try? stock.missingIngredients(for: ingredients)
    }

    private var actions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Spacing.sm))
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            layout {
                actionButton("Recipe", systemImage: "book", prominent: !entry.macrosAvailable) { sheet = .recipe }
                    .accessibilityHint("Opens the recipe")
                if entry.macrosAvailable {
                    actionButton("Review and log", systemImage: "checklist", prominent: true) { sheet = .stock }
                        .accessibilityHint("Review ingredient portions and log from stock")
                }
            }
            if let missing, !missing.isEmpty, entry.stockOperationID != nil {
                actionButton("Add missing ingredients to groceries", systemImage: "cart.badge.plus", prominent: false) {
                    if PlannedMealStockSheet.addMissingToGroceries(entry: entry, missing: missing) {
                        addedNotice = "Missing quantities added to Groceries."
                        addedTrigger.toggle()
                    }
                }
                .sensoryFeedback(.success, trigger: addedTrigger)
                .accessibilityIdentifier("mealPlan.addMissing")
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, prominent: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? Color.onAccent : Color.labelPrimary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 40)
                .background(prominent ? Color.progress : Color.surfaceSecondary,
                            in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        }
        .buttonStyle(ScalePressStyle())
    }
}

// MARK: - Why this plan

private struct WhyThisPlanCard: View {
    let notes: String
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("Why this plan?", isExpanded: $expanded) {
            Text(notes.isEmpty ? "No notes provided." : notes)
                .font(.subheadline).italic()
                .foregroundStyle(Color.labelSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .tint(Color.brandPrimary)
        .padding(16)
        .background(Color.brandPrimary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Recommendations

private struct RecommendationsSection: View {
    let items: [ShoppingRecommendation]
    let onAdd: (ShoppingRecommendation) -> Void
    let onAddAll: ([ShoppingRecommendation]) -> Void
    /// Cards still in the deck this session (skipped ones just leave it).
    @State private var remaining: [ShoppingRecommendation] = []
    @State private var addedTrigger = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gaps & Recommendations")
                    .font(.headline)
                Spacer()
                if !remaining.isEmpty {
                    Text("\(remaining.count) left")
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            SwipeDeck(items: remaining, acceptLabel: "Add to groceries", skipLabel: "Skip",
                      label: { item in
                          "\(item.foodName). \(item.reason). €\(String(format: "%.2f", item.estimatedPrice)). \(PriorityBadge.label(item.priority)) priority"
                      },
                      onDecide: { item, accepted in
                          if accepted { onAdd(item); addedTrigger.toggle() }
                          remaining.removeAll { $0.id == item.id }
                      }) { item in
                recommendationCard(item)
            } empty: {
                VStack(spacing: 4) {
                    Label("All done", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.labelPrimary)
                    Text("Added items are in Groceries.")
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }

            if remaining.count > 1 {
                Button {
                    addedTrigger.toggle()
                    onAddAll(remaining)
                    remaining = []
                } label: {
                    Label("Add all to grocery list", systemImage: "cart.badge.plus")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color.labelPrimary)
                }
                .buttonStyle(ScalePressStyle())
            }
        }
        .sensoryFeedback(.success, trigger: addedTrigger)
        .padding(16)
        .premiumCard(radius: 16)
        .onAppear { if remaining.isEmpty { remaining = items } }
        .onChange(of: items.map(\.id)) { _, _ in remaining = items }
    }

    private func recommendationCard(_ item: ShoppingRecommendation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.foodName).font(.headline).foregroundStyle(Color.labelPrimary)
                Spacer(minLength: Spacing.sm)
                PriorityBadge(priority: item.priority)
            }
            Text(item.reason)
                .font(.subheadline).foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("est. €\(item.estimatedPrice, specifier: "%.2f")")
                .font(.caption).foregroundStyle(Color.labelSecondary)
        }
        .padding(Spacing.lg)
        .padding(.top, Spacing.lg)   // room for the Add / Skip stamps
    }
}

private struct PriorityBadge: View {
    let priority: Int

    static func label(_ priority: Int) -> String {
        switch priority {
        case 1: return "High"
        case 2: return "Medium"
        default: return "Low"
        }
    }
    private var label: String { Self.label(priority) }
    private var color: Color {
        switch priority {
        case 1: return .brandDanger
        case 2: return .brandAmber
        default: return .secondary
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2).fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Regenerate

private struct RegenerateButton: View {
    let isGenerating: Bool
    var idleTitle = "Regenerate plan"
    let onTap: () -> Void

    var body: some View {
        PrimaryButton(
            title: isGenerating ? "Agent is thinking…" : idleTitle,
            systemImage: isGenerating ? nil : "arrow.clockwise",
            isLoading: isGenerating,
            action: onTap
        )
    }
}

// MARK: - States

// MARK: - Skeleton loaders

private struct SkeletonMealPlanContent: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in SkeletonMealSection() }
            // Placeholder for regenerate button
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemFill))
                .frame(height: 54)
                .shimmer()
        }
        .padding(.horizontal, 16)
    }
}

private struct SkeletonMealSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemFill))
                    .frame(width: 34, height: 34)
                    .shimmer()
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemFill))
                    .frame(width: 110, height: 15)
                    .shimmer()
                Spacer()
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemFill))
                    .frame(width: 55, height: 13)
                    .shimmer()
            }
            ForEach(0..<2, id: \.self) { i in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(width: i == 0 ? 160 : 120, height: 13)
                        .shimmer()
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(width: 48, height: 13)
                        .shimmer()
                }
                .padding(.leading, 46)
            }
        }
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

private struct SkeletonWeekContent: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<7, id: \.self) { _ in SkeletonWeekDayCard() }
        }
    }
}

private struct SkeletonWeekDayCard: View {
    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemFill)).frame(width: 24, height: 10).shimmer()
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemFill)).frame(width: 20, height: 18).shimmer()
            }
            .frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill)).frame(width: 90, height: 14).shimmer()
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill)).frame(width: 32, height: 12).shimmer()
                }
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemFill)).frame(height: 6).shimmer()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
    }
}

/// One day of the week: its date, total and every planned meal. Tap a meal for its recipe.
private struct WeekDayCard: View {
    let plan: MealPlan
    @State private var recipe: RecipeTarget?

    private struct RecipeTarget: Identifiable {
        let name: String
        var id: String { name }
    }

    private var isToday: Bool { Calendar.current.isDateInToday(plan.date) }
    private var meals: [(title: String, sfSymbol: String, entries: [MealEntry])] {
        plan.allMeals.filter { !$0.entries.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(plan.date, format: .dateTime.weekday(.wide))
                    .font(.headline).foregroundStyle(Color.labelPrimary)
                Text(plan.date, format: .dateTime.day().month(.abbreviated))
                    .font(.subheadline).foregroundStyle(Color.labelSecondary)
                if isToday {
                    Text("Today")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.progress, in: Capsule())
                }
                Spacer(minLength: Spacing.sm)
                Text("\(plan.totalCalories) kcal")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.labelSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if meals.isEmpty {
                Text("Nothing planned")
                    .font(.subheadline).foregroundStyle(Color.labelSecondary)
            }
            ForEach(Array(meals.enumerated()), id: \.offset) { index, meal in
                if index > 0 { Divider().overlay(Color.hairline) }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label(meal.title, systemImage: meal.sfSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.labelSecondary)
                    ForEach(meal.entries) { entry in
                        Button { recipe = RecipeTarget(name: entry.foodName) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                                Text(entry.foodName)
                                    .font(.subheadline).foregroundStyle(Color.labelPrimary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: Spacing.sm)
                                Text("\(entry.calories) kcal")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Color.labelSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.labelTertiary)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the recipe")
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(radius: Radius.tile)
        .sheet(item: $recipe) { RecipeSheet(mealName: $0.name) }
        .accessibilityIdentifier("mealPlan.weekDay")
    }
}

#Preview {
    NavigationStack { MealPlanView() }
}
