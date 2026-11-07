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
                        if let deal = vm.activeDealBanner {
                            DealNotificationBanner(
                                deal: deal,
                                onBuy:  { Task { await vm.respondToDeal(deal, bought: true) } },
                                onSkip: { Task { await vm.respondToDeal(deal, bought: false) } }
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        HomeHeaderView(vm: vm)
                        VStack(spacing: Spacing.lg) {
                            CalorieSummaryCard(vm: vm, onLog: { vm.openLog() })
                            TodaysLogCard(vm: vm)
                            HomeDealsSection(vm: vm)
                            MealPlanPreviewCard(vm: vm)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.xxl)
                    }
                }
                .refreshable { await vm.refresh() }
            }
            .animation(reduceMotion ? .none : .smoothCard, value: vm.activeDealBanner?.id)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $vm.showLogSheet) { LogFoodSheet(vm: vm) }
        .sheet(isPresented: $vm.showAgentChat) { AgentChatSheet(vm: vm) }
        .task { await vm.load() }
        .onAppear { LocationService.shared.startUpdating() }
    }
}

#Preview { HomeView().environment(AppState.shared) }
