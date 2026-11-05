import SwiftUI

struct HomeView: View {

    @State private var vm = HomeViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.surfaceGrouped.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Spacing.md) {
                        HomeHeaderView(vm: vm)
                        VStack(spacing: Spacing.lg) {
                            CalorieSummaryCard(vm: vm, onLog: { vm.openLog() })
                            TodaysLogCard(vm: vm)
                            HomeAgentCard(vm: vm)
                            HomeDealsSection(vm: vm)
                            MealPlanPreviewCard(vm: vm)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.xxl)
                    }
                }
                .refreshable { await vm.refresh() }

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
            .overlay(alignment: .bottomTrailing) { quickLogButton }
            .animation(reduceMotion ? .none : .smoothCard, value: vm.activeDealBanner?.id)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $vm.showLogSheet) { LogFoodSheet(vm: vm) }
        .sheet(isPresented: $vm.showAgentChat) { AgentChatSheet(vm: vm) }
        .task { await vm.load() }
        .onAppear { LocationService.shared.startUpdating() }
    }

    private var quickLogButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            vm.openLog()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.onAccent)
                .frame(width: 58, height: 58)
                .background(Color.coral, in: Circle())
                .elevation(Elevation.high)
        }
        .buttonStyle(ScalePressStyle())
        .padding(.trailing, Spacing.xl)
        // Keep the floating action clear of the custom bottom navigation.
        .padding(.bottom, 104)
        .accessibilityLabel("Log food")
    }
}

#Preview { HomeView().environment(AppState.shared) }
