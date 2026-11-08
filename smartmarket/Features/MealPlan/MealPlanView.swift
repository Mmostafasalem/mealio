import SwiftUI

struct MealPlanView: View {

    @State private var vm = MealPlanViewModel()
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
                Picker("View", selection: $vm.selectedTab) {
                    ForEach(MealPlanTab.allCases) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.lg)

                if vm.isGenerating && vm.todaysPlan != nil {
                    HStack(spacing: Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Updating plan…").font(.footnote)
                    }
                    .foregroundStyle(Color.labelSecondary)
                }
                switch vm.selectedTab {
                case .today: todayContent
                case .week:  weekContent
                }
            }
            .padding(.vertical, Spacing.lg)
            .animation(reduceMotion ? .none : .snappyValue, value: vm.selectedTab)
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
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
                ForEach(Array(plan.allMeals.enumerated()), id: \.offset) { _, meal in
                    MealSectionCard(title: meal.title, sfSymbol: meal.sfSymbol, entries: meal.entries)
                }

                WhyThisPlanCard(notes: plan.agentNotes)

                if !vm.recommendations.isEmpty {
                    RecommendationsSection(items: vm.recommendations) {
                        vm.addAllToGroceryList()
                    }
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
        } else {
            EmptyStateView(icon: "fork.knife", title: "No meal plan yet",
                           message: "Generate a plan tailored to your goals and favourite foods.",
                           actionTitle: "Generate Plan") { Task { await vm.loadTodaysPlan() } }
                .padding(.top, Spacing.xxl)
        }
    }

    // MARK: - Week

    private var weekContent: some View {
        VStack(spacing: 12) {
            if vm.weekPlans.isEmpty {
                SkeletonWeekContent()
            } else {
                ForEach(vm.weekPlans) { plan in
                    WeekDayCard(
                        date: plan.date,
                        totalCalories: plan.totalCalories,
                        goal: vm.goal
                    )
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Meal section

private struct MealSectionCard: View {
    let title: String
    let sfSymbol: String
    let entries: [MealEntry]
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
                ForEach(entries) { entry in
                    MealEntryRow(entry: entry)
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
    @State private var showRecipe = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            showRecipe = true
        } label: {
            let rowLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
                : AnyLayout(HStackLayout(spacing: Spacing.md))
            rowLayout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.foodName)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundStyle(Color.labelPrimary)
                    Text(entry.notes?.isEmpty == false ? entry.notes! : (entry.portionG > 0 ? "\(entry.portionG) g" : "Portion not specified"))
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                    Text("\(entry.calories) kcal")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.labelSecondary).monospacedDigit()
                    Text(entry.nutritionIngredients == nil ? "Estimated calories · macros unavailable" : "Calculated from ingredient portions")
                        .font(.caption2).foregroundStyle(Color.labelSecondary)
                    if entry.proteinG + entry.carbsG + entry.fatG > 0 {
                        Text("P\(Int(entry.proteinG))  C\(Int(entry.carbsG))  F\(Int(entry.fatG))")
                            .font(.caption2).foregroundStyle(Color.labelTertiary).monospacedDigit()
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.labelTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xs)
        .accessibilityHint("Opens the recipe")
        .sheet(isPresented: $showRecipe) {
            RecipeSheet(mealName: entry.foodName)
        }
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
    let onAddAll: () -> Void
    @State private var addedTrigger = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gaps & Recommendations")
                .font(.headline)

            ForEach(items) { item in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.foodName).font(.subheadline).fontWeight(.semibold)
                        Text(item.reason).font(.caption).foregroundStyle(Color.labelSecondary)
                        Text("\(item.storeName) · €\(item.estimatedPrice, specifier: "%.2f")")
                            .font(.caption2).foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    PriorityBadge(priority: item.priority)
                }
                .padding(.vertical, 4)
            }

            Button {
                addedTrigger.toggle()
                onAddAll()
            } label: {
                Label("Add all to grocery list", systemImage: "cart.badge.plus")
                    .font(.subheadline).fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.onAccent)
                    .background(Color.dullPink)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .sensoryFeedback(.success, trigger: addedTrigger)
        }
        .padding(16)
        .premiumCard(radius: 16)
    }
}

private struct PriorityBadge: View {
    let priority: Int

    private var label: String {
        switch priority {
        case 1: return "High"
        case 2: return "Medium"
        default: return "Low"
        }
    }
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
    let onTap: () -> Void

    var body: some View {
        PrimaryButton(
            title: isGenerating ? "Agent is thinking…" : "Regenerate plan",
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

private struct WeekDayCard: View {
    let date: Date
    let totalCalories: Int
    let goal: Int

    private var percent: Int { goal > 0 ? min(Int(Double(totalCalories) / Double(goal) * 100), 100) : 0 }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var fillColor: Color {
        percent >= 100 ? .brandDanger : percent >= 80 ? .brandAmber : .brandPrimary
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption2).fontWeight(.bold).foregroundStyle(Color.labelSecondary)
                Text(date, format: .dateTime.day())
                    .font(.headline).fontWeight(.bold)
                    .foregroundStyle(isToday ? Color.brandPrimary : .primary)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(totalCalories) kcal")
                        .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                    Spacer()
                    Text("\(percent)%")
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemFill)).frame(height: 6)
                        Capsule().fill(fillColor)
                            .frame(width: geo.size.width * CGFloat(percent) / 100, height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isToday ? Color.brandPrimary.opacity(0.07) : Color.surface,
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.tile)
                .strokeBorder(isToday ? Color.brandPrimary : Color.hairline,
                              lineWidth: isToday ? 1.5 : 0.7)
        )
    }
}

#Preview {
    NavigationStack { MealPlanView() }
}
