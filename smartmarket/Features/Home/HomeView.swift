import SwiftUI

struct HomeView: View {

    @State private var vm = HomeViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    if let errorMessage = vm.errorMessage {
                        ErrorBanner(message: errorMessage) {
                            Task { await vm.load() }
                        }
                    }

                    calorieHeader
                    mealPlanPreview
                    dealsSection
                    agentSection
                }
                .padding(.vertical, 16)
            }
            .background(Color.surfaceGrouped.ignoresSafeArea())
            .navigationTitle("SmartMarket")
            .refreshable { await vm.refresh() }
            .overlay(alignment: .top) { bannerOverlay }
            .animation(reduceMotion ? .none : .spring(duration: 0.4), value: vm.activeDealBanner?.id)
        }
        .task { await vm.load() }
        .onAppear { LocationService.shared.startUpdating() }
    }

    // MARK: - Calorie header

    private var calorieHeader: some View {
        VStack(spacing: 20) {
            CalorieRingView(consumed: vm.consumed, goal: vm.goal)

            VStack(spacing: 12) {
                MacroProgressBarView(label: "Protein", sfSymbol: "bolt.fill",
                                     current: vm.proteinCurrent, goal: vm.proteinGoal, color: .brandPrimary)
                MacroProgressBarView(label: "Carbs", sfSymbol: "leaf.fill",
                                     current: vm.carbsCurrent, goal: vm.carbsGoal, color: .brandAmber)
                MacroProgressBarView(label: "Fat", sfSymbol: "drop.fill",
                                     current: vm.fatCurrent, goal: vm.fatGoal, color: .brandPrimary)
            }

            Button {
                vm.showLogSheet = true
            } label: {
                Label("Log Meal", systemImage: "plus.circle.fill")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .cardBackground()
        .padding(.horizontal, 16)
        .sheet(isPresented: $vm.showLogSheet) {
            LogMealSheet(vm: vm)
        }
    }

    // MARK: - Meal plan preview

    private var mealPlanPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's Plan")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    MealPlanView()
                } label: {
                    Text("See full plan")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundStyle(Color.brandPrimary)
                }
            }

            if vm.isLoading {
                ForEach(0..<4, id: \.self) { _ in
                    MealPreviewRow(symbol: "circle", title: "Loading meal", calories: 000)
                        .redacted(reason: .placeholder)
                        .shimmer(active: !reduceMotion)
                }
            } else if let plan = vm.mealPlan {
                ForEach(Array(plan.allMeals.enumerated()), id: \.offset) { _, meal in
                    let cals = meal.entries.reduce(0) { $0 + $1.calories }
                    MealPreviewRow(symbol: meal.sfSymbol, title: meal.title, calories: cals)
                }
            } else {
                Text("No plan yet. Pull to refresh.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .cardBackground()
        .padding(.horizontal, 16)
    }

    // MARK: - Deals

    private var dealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nearby Deals")
                .font(.headline)
                .padding(.horizontal, 16)

            if vm.isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            DealCardView(deal: MarketDeal.mocked[0], onTap: {})
                                .redacted(reason: .placeholder)
                                .shimmer(active: !reduceMotion)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else if vm.nearbyDeals.isEmpty {
                EmptyDealsView()
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(vm.nearbyDeals) { deal in
                            DealCardView(deal: deal) {
                                vm.activeDealBanner = deal
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Agent

    private var agentSection: some View {
        AgentMessageCardView(
            message: vm.mealPlan?.agentNotes,
            isLoading: vm.isLoading || AppState.shared.isGeneratingMealPlan
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Banner overlay

    @ViewBuilder
    private var bannerOverlay: some View {
        if let deal = vm.activeDealBanner {
            DealNotificationBanner(
                deal: deal,
                onBuy: { Task { await vm.respondToDeal(deal, bought: true) } },
                onSkip: { Task { await vm.respondToDeal(deal, bought: false) } }
            )
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Subviews

private struct MealPreviewRow: View {
    let symbol: String
    let title: String
    let calories: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 26)
            Text(title)
                .font(.subheadline).fontWeight(.medium)
            Spacer()
            Text("\(calories) kcal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

private struct EmptyDealsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "leaf")
                .font(.system(size: 30))
                .foregroundStyle(Color.brandPrimary.opacity(0.5))
            Text("No deals near you today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .cardBackground()
    }
}

private struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.brandAmber)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button("Retry", action: onRetry)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(Color.brandPrimary)
        }
        .padding(12)
        .background(Color.brandAmberLight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

// MARK: - Helpers

private extension View {
    func cardBackground() -> some View {
        background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
    }
}

#Preview {
    HomeView()
}

// MARK: - Log Meal Sheet

private struct LogMealSheet: View {
    @Bindable var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    private var allEntries: [(label: String, entry: MealEntry)] {
        guard let plan = vm.mealPlan else { return [] }
        return plan.allMeals.flatMap { section in
            section.entries.map { (label: section.title, entry: $0) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allEntries.isEmpty {
                    ContentUnavailableView(
                        "No meal plan yet",
                        systemImage: "fork.knife",
                        description: Text("Pull to refresh on the Home tab to generate today's plan.")
                    )
                } else {
                    List {
                        ForEach(allEntries, id: \.entry.id) { item in
                            LogEntryRow(
                                label: item.label,
                                entry: item.entry,
                                isLogged: vm.isLogged(item.entry)
                            ) {
                                vm.logMealEntry(item.entry)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct LogEntryRow: View {
    let label: String
    let entry: MealEntry
    let isLogged: Bool
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                    .font(.subheadline).fontWeight(.medium)
                    .strikethrough(isLogged, color: .secondary)
                HStack(spacing: 6) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(entry.calories) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            if isLogged {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.brandPrimary)
                    .font(.system(size: 22))
            } else {
                Button(action: onLog) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.brandPrimary)
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isLogged { onLog() }
        }
    }
}
