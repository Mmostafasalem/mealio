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
    }

    // MARK: - Today

    @ViewBuilder
    private var todayContent: some View {
        if vm.isGenerating && vm.todaysPlan == nil {
            GeneratingView()
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
                ProgressView("Loading week plan…")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
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
            HStack(spacing: 10) {
                Image(systemName: sfSymbol)
                    .foregroundStyle(Color.brandPrimary)
                Text(title).font(.headline)
                Spacer()
                Text("\(entries.reduce(0) { $0 + $1.calories }) kcal")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .tint(.primary)
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator), lineWidth: 0.5))
    }
}

private struct MealEntryRow: View {
    let entry: MealEntry

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                    .font(.subheadline).fontWeight(.medium)
                Text("\(entry.portionG)g\(entry.notes.map { " · \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                MacroDot(color: .blue)
                MacroDot(color: .brandAmber)
                MacroDot(color: .brandPrimary)
            }
            Text("\(entry.calories) kcal")
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct MacroDot: View {
    let color: Color
    var body: some View { Circle().fill(color).frame(width: 6, height: 6) }
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
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator), lineWidth: 0.5))
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

    private var percent: Int { goal > 0 ? Int(Double(totalCalories) / Double(goal) * 100) : 0 }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.weekday(.wide))
                    .font(.subheadline).fontWeight(.semibold)
                Text(date, format: .dateTime.month().day())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(totalCalories) kcal")
                    .font(.subheadline).monospacedDigit()
                Text("\(percent)% of goal")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator), lineWidth: 0.5))
    }
}

#Preview {
    NavigationStack { MealPlanView() }
}
