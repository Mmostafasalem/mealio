import SwiftUI

struct MealPlanView: View {

    @State private var vm = MealPlanViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("View", selection: $vm.selectedTab) {
                    ForEach(MealPlanTab.allCases) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                switch vm.selectedTab {
                case .today: todayContent
                case .week:  weekContent
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle("Meal Plan")
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
            ErrorStateCard(message: errorMessage) { Task { await vm.loadTodaysPlan() } }
        } else if let plan = vm.todaysPlan {
            VStack(spacing: 16) {
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
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
        } else {
            EmptyPlanView { Task { await vm.loadTodaysPlan() } }
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

    private var accentColor: Color {
        switch sfSymbol {
        case "sunrise.fill": return .carbsAccent      // amber — breakfast
        case "sun.max.fill": return .calorieAccent    // green — lunch
        case "moon.fill":    return .fatAccent        // violet — dinner
        case "sparkles":     return .proteinAccent    // orange — snack
        default:             return .brandPrimary
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 8) {
                if entries.isEmpty {
                    Text("Nothing planned")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(entries) { entry in
                    MealEntryRow(entry: entry)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: sfSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 34, height: 34)
                    .background(accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(title).font(.headline)
                Spacer()
                Text("\(entries.reduce(0) { $0 + $1.calories }) kcal")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .tint(.primary)
        .padding(16)
        .premiumCard(radius: 16)
    }
}

private struct MealEntryRow: View {
    let entry: MealEntry
    @State private var showRecipe = false

    var body: some View {
        Button {
            showRecipe = true
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.foodName)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(entry.notes?.isEmpty == false ? entry.notes! : "\(entry.portionG)g")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(entry.calories) kcal")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary).monospacedDigit()
                    if entry.proteinG + entry.carbsG + entry.fatG > 0 {
                        Text("P\(Int(entry.proteinG))  C\(Int(entry.carbsG))  F\(Int(entry.fatG))")
                            .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
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
                .foregroundStyle(.secondary)
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
                        Text(item.reason).font(.caption).foregroundStyle(.secondary)
                        Text("\(item.storeName) · €\(item.estimatedPrice, specifier: "%.2f")")
                            .font(.caption2).foregroundStyle(.secondary)
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
                    .foregroundStyle(.white)
                    .background(Color.brandPrimary)
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
        Button(action: onTap) {
            HStack {
                if isGenerating {
                    ProgressView().tint(.white)
                    Text("Agent is thinking...")
                } else {
                    Image(systemName: "arrow.clockwise")
                    Text("Regenerate plan")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundStyle(.white)
            .background(Color.brandPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isGenerating)
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

private struct GeneratingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large).tint(.brandPrimary)
            Text("Agent is thinking...")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct EmptyPlanView: View {
    let onGenerate: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "fork.knife")
                .font(.system(size: 40))
                .foregroundStyle(Color.brandPrimary.opacity(0.5))
            Text("No meal plan yet")
                .font(.headline)
            Button(action: onGenerate) {
                Text("Generate Plan")
                    .font(.subheadline).fontWeight(.semibold)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Color.brandPrimary)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct ErrorStateCard: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30))
                .foregroundStyle(Color.brandDanger)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry", action: onRetry)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(Color.brandPrimary)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.brandDanger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
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
                    .font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
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
                        .font(.caption).foregroundStyle(.secondary)
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
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isToday
                        ? LinearGradient(colors: [Color.brandPrimary.opacity(0.5), Color.brandPrimary.opacity(0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.white.opacity(0.45), Color(.separator).opacity(0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: isToday ? 1.5 : 1
                )
        )
    }
}

#Preview {
    NavigationStack { MealPlanView() }
}
