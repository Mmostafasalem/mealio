import SwiftUI

struct HomeView: View {

    @State private var vm = HomeViewModel()
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.surfaceGrouped.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerBanner
                            .padding(.bottom, 20)

                        VStack(spacing: 16) {
                            calorieCard
                            agentCard
                            dealsSection
                            mealPlanPreview
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
                .refreshable { await vm.refresh() }

                // Deal banner drops from top
                if let deal = vm.activeDealBanner {
                    DealNotificationBanner(
                        deal: deal,
                        onBuy:  { Task { await vm.respondToDeal(deal, bought: true) } },
                        onSkip: { Task { await vm.respondToDeal(deal, bought: false) } }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .animation(reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.8),
                       value: vm.activeDealBanner?.id)
            .navigationBarHidden(true)
        }
        .task { await vm.load() }
        .onAppear { LocationService.shared.startUpdating() }
        .sheet(isPresented: $vm.showLogSheet) { LogMealSheet(vm: vm) }
    }

    // MARK: - Header banner

    private var headerBanner: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.brandPrimary, Color.brandPrimary.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Text(profileName)
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 20)

            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Date(), format: .dateTime.weekday(.wide))
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                    Text(Date(), format: .dateTime.day().month(.abbreviated))
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Calorie card

    private var calorieCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 24) {
                CalorieRingView(consumed: vm.consumed, goal: vm.goal)
                    .frame(width: 100, height: 100)

                VStack(alignment: .leading, spacing: 10) {
                    MacroProgressBarView(label: "Protein", sfSymbol: "bolt.fill",
                                         current: vm.proteinCurrent, goal: vm.proteinGoal,
                                         color: .brandPrimary)
                    MacroProgressBarView(label: "Carbs", sfSymbol: "leaf.fill",
                                         current: vm.carbsCurrent, goal: vm.carbsGoal,
                                         color: .brandAmber)
                    MacroProgressBarView(label: "Fat", sfSymbol: "drop.fill",
                                         current: vm.fatCurrent, goal: vm.fatGoal,
                                         color: Color(hex: "#EC4899"))
                }
                .frame(maxWidth: .infinity)
            }

            Button { vm.showLogSheet = true } label: {
                Label("Log a Meal", systemImage: "fork.knife")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .card()
    }

    // MARK: - Agent card

    private var agentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.brandPrimary)
                        .frame(width: 32, height: 32)
                    Text("SM")
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                Text("SmartMarket Agent")
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                if appState.isGeneratingMealPlan {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(Color.brandPrimary)
                }
            }

            AgentMessageCardView(
                message: vm.mealPlan?.agentNotes,
                isLoading: vm.isLoading || appState.isGeneratingMealPlan
            )
        }
        .padding(16)
        .card()
    }

    // MARK: - Deals section

    private var dealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Deals Near You", systemImage: "tag.fill")
                    .font(.headline)
                Spacer()
                if !vm.nearbyDeals.isEmpty {
                    Text("\(vm.nearbyDeals.count) deals")
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }

            if vm.isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonDealCard()
                        }
                    }
                }
            } else if vm.nearbyDeals.isEmpty {
                emptyDealsRow
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(vm.nearbyDeals) { deal in
                            DealCardView(deal: deal) {
                                vm.activeDealBanner = deal
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .padding(16)
        .card()
    }

    private var emptyDealsRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Color.brandPrimary.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text("No nearby deals found")
                    .font(.subheadline).fontWeight(.medium)
                Text("Pull to refresh or check back later")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Meal plan preview

    private var mealPlanPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today's Meals", systemImage: "fork.knife.circle.fill")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    MealPlanView()
                } label: {
                    Text("Full Plan")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.brandPrimary)
                }
            }

            if vm.isLoading {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle()
                        .fill(Color(.systemFill))
                        .frame(height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shimmer(active: !reduceMotion)
                }
            } else if let plan = vm.mealPlan {
                ForEach(Array(plan.allMeals.enumerated()), id: \.offset) { idx, meal in
                    MealPreviewRow(
                        icon: meal.sfSymbol,
                        title: meal.title,
                        calories: meal.entries.reduce(0) { $0 + $1.calories },
                        accent: mealAccent(idx)
                    )
                    if idx < plan.allMeals.count - 1 {
                        Divider().padding(.leading, 36)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(Color.brandPrimary.opacity(0.5))
                    Text("Pull to refresh and generate today's plan")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .card()
    }

    // MARK: - Helpers

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var profileName: String {
        AppState.shared.userProfile?.name.isEmpty == false
            ? AppState.shared.userProfile!.name
            : "there"
    }

    private func mealAccent(_ idx: Int) -> Color {
        [Color.brandPrimary, Color.brandAmber, Color(hex: "#EC4899"), Color(hex: "#10B981")][idx % 4]
    }
}

// MARK: - Sub-views

private struct MealPreviewRow: View {
    let icon: String
    let title: String
    let calories: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.12))
                .clipShape(Circle())

            Text(title)
                .font(.subheadline).fontWeight(.medium)
                .lineLimit(1)
            Spacer()
            Text("\(calories) kcal")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

private struct SkeletonDealCard: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(.systemFill))
            .frame(width: 160, height: 100)
            .shimmer(active: true)
    }
}

private extension View {
    func card() -> some View {
        background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Log Meal Sheet

private struct LogMealSheet: View {
    @Bindable var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    private var allEntries: [(label: String, entry: MealEntry)] {
        guard let plan = vm.mealPlan else { return [] }
        return plan.allMeals.flatMap { s in s.entries.map { (s.title, $0) } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allEntries.isEmpty {
                    ContentUnavailableView(
                        "No meal plan yet",
                        systemImage: "fork.knife",
                        description: Text("Go to the Meal Plan tab to generate today's plan.")
                    )
                } else {
                    List {
                        ForEach(allEntries, id: \.entry.id) { item in
                            LogEntryRow(
                                label: item.label,
                                entry: item.entry,
                                isLogged: vm.isLogged(item.entry)
                            ) { vm.logMealEntry(item.entry) }
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
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text("·").font(.caption).foregroundStyle(.secondary)
                    Text("\(entry.calories) kcal").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer()
            if isLogged {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.brandPrimary).font(.system(size: 22))
            } else {
                Button(action: onLog) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.brandPrimary).font(.system(size: 22))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if !isLogged { onLog() } }
    }
}

#Preview { HomeView() }
