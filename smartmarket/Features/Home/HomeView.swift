import SwiftUI

struct HomeView: View {

    /// Profile opens from the avatar in the header (and from quick actions).
    @State private var showProfile = false

    @State private var vm = HomeViewModel()
    /// Shown for a moment after the connection comes back.
    @State private var showBackOnline = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                GrainyGradient().ignoresSafeArea()

                // Custom goo pull-to-refresh (replaces the system `.refreshable`);
                // the island floats above the list for Home's transient notices.
                GooPullRefresh(action: { await vm.refresh() }) {
                    MorphIsland(item: notice, style: \.islandStyle) { notice in
                        noticeView(notice)
                    }
                } content: {
                    VStack(spacing: Spacing.md) {
                        HomeHeaderView(vm: vm) { showProfile = true }
                        VStack(spacing: Spacing.lg) {
                            HStack {
                                NavigationLink { StockView() } label: { Label("My Stock", systemImage: "cabinet") }
                                    .accessibilityIdentifier("home.stock")
                                Spacer()
                                NavigationLink { FoodHistoryView() } label: { Label("History", systemImage: "clock") }
                            }
                            .font(.subheadline.weight(.semibold))
                            CalorieSummaryCard(vm: vm, onLog: { vm.openLog() })
                            // Above the cards below it: its goo menu pours out over them.
                            TodaysLogCard(vm: vm).zIndex(1)
                            HomeDealsSection(vm: vm)
                            MealPlanPreviewCard(vm: vm)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.xxl)
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showProfile) {
                ProfileView().navigationBarHidden(false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openProfile)) { _ in showProfile = true }
        }
        .sheet(isPresented: $vm.showLogSheet) { LogFoodSheet(vm: vm) }
        .sheet(isPresented: $vm.showAgentChat) { AgentChatSheet(vm: vm) }
        .task { await vm.load() }
        .onChange(of: NetworkMonitor.shared.isOnline) { _, online in
            showBackOnline = online
            AccessibilityNotification.Announcement(online ? "Back online" : "Offline, using saved data").post()
        }
        .task(id: showBackOnline) {
            guard showBackOnline else { return }
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { showBackOnline = false }
        }
    }

    // MARK: Island notices

    /// The deal the person tapped wins over connection status.
    private var notice: HomeNotice? {
        if let deal = vm.activeDealBanner { return .deal(deal) }
        if !NetworkMonitor.shared.isOnline { return .offline }
        if showBackOnline { return .backOnline }
        return nil
    }

    @ViewBuilder private func noticeView(_ notice: HomeNotice) -> some View {
        switch notice {
        case .offline:
            statusPill("Offline · using saved data", systemImage: "wifi.slash")
                .accessibilityLabel("Offline, using saved data")
        case .backOnline:
            statusPill("Back online", systemImage: "wifi")
        case .deal(let deal):
            DealNotificationBanner(
                deal: deal,
                onBuy:  { Task { await vm.respondToDeal(deal, bought: true) } },
                onSkip: { Task { await vm.respondToDeal(deal, bought: false) } }
            )
        }
    }

    private func statusPill(_ text: String, systemImage: String) -> some View {
        HStack(spacing: Spacing.xs + 2) {
            Image(systemName: systemImage).accessibilityHidden(true)
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.labelPrimary)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

/// What Home's MorphIsland can show.
enum HomeNotice: Identifiable, Equatable {
    case offline
    case backOnline
    case deal(MarketDeal)

    var id: String {
        switch self {
        case .offline: return "offline"
        case .backOnline: return "backOnline"
        case .deal(let deal): return "deal-\(deal.id)"
        }
    }

    var islandStyle: MorphIslandStyle {
        if case .deal = self { return .expanded }
        return .compact
    }
}

#Preview { HomeView().environment(AppState.shared) }
