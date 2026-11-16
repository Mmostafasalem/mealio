import SwiftUI

struct HomeView: View {

    /// Profile opens from the avatar in the header (and from quick actions).
    @State private var showProfile = false
    @State private var showReminders = false
    @State private var reminders = ReminderStore.shared
    @State private var loop = DailyLoopStore.shared
    @State private var showStock = false

    @State private var vm = HomeViewModel()
    /// Shown for a moment after the connection comes back.
    @State private var showBackOnline = false

    /// Today's reminders whose time has come, as a pile of cards. Tap to fan
    /// them out, tap one to act on it, swipe one away to dismiss it. Meals
    /// already logged today have nothing left to remind about.
    @ViewBuilder
    private var dueReminders: some View {
        let loggedSlots = vm.loggedSlots
        let due = reminders.due(now: vm.now, loggedSlots: loggedSlots)
        if !due.isEmpty {
            NotificationStack(
                notices: due.map { StackNotice(id: $0.id, symbol: $0.symbol, title: $0.title, body: $0.message, detail: $0.timeText) },
                title: "Reminders",
                onOpen: { notice in
                    guard let reminder = due.first(where: { $0.id == notice.id }) else { return }
                    reminders.dismiss(reminder)
                    if reminder.kind == .workout {
                        NotificationCenter.default.post(name: .openTrain, object: nil)
                    } else {
                        vm.openLog(slot: reminder.mealSlot)
                    }
                },
                onDismiss: { notice in
                    if let reminder = due.first(where: { $0.id == notice.id }) { reminders.dismiss(reminder) }
                },
                onClearAll: { reminders.dismissAllDue(now: vm.now, loggedSlots: loggedSlots) })
            .accessibilityIdentifier("home.dueReminders")
        }
    }

    private func openQuest(_ destination: QuestDestination) {
        switch destination {
        case .logFood: vm.openLog()
        case .train: NotificationCenter.default.post(name: .openTrain, object: nil)
        case .shop: NotificationCenter.default.post(name: .openShop, object: nil)
        case .stock: showStock = true
        }
    }

    private func shortcut(_ title: String, symbol: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: symbol)
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.labelPrimary)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
        .contentShape(Capsule())
    }

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
                        HomeHeaderView(vm: vm, onProfile: { showProfile = true }, onReminders: { showReminders = true })
                        VStack(spacing: Spacing.lg) {
                            dueReminders
                            // Two matching pills with the microphone between them.
                            HStack(spacing: Spacing.md) {
                                NavigationLink { StockView() } label: { shortcut("My Stock", symbol: "cabinet") }
                                    .accessibilityIdentifier("home.stock")
                                // One tap to speak a command (the same sheet as "+" › Speak a command).
                                Button { NotificationCenter.default.post(name: .openVoice, object: nil) } label: {
                                    Image(systemName: "mic.fill")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color.onAccent)
                                        .frame(width: 44, height: 44)
                                        .background(Color.dullPink, in: Circle())
                                        .contentShape(Circle())
                                }
                                .accessibilityLabel("Speak a command")
                                .accessibilityIdentifier("home.voice")
                                // The same small "i" as the macros, centred just above the microphone,
                                // in the gap under the header, so the row stays symmetrical.
                                .overlay {
                                    InfoTooltip(text: "Tap the microphone and say what you ate or want, like \u{201C}two eggs for breakfast\u{201D}, \u{201C}add milk to my cart\u{201D} or \u{201C}start a 30 minute workout\u{201D}. It listens on this iPhone and shows what it understood before saving.")
                                        .offset(y: -34)
                                }
                                NavigationLink { FoodHistoryView() } label: { shortcut("History", symbol: "clock") }
                            }
                            .buttonStyle(ScalePressStyle())
                            CalorieSummaryCard(vm: vm, onLog: { vm.openLog() })
                            DailyQuestCard(state: loop.state, onOpen: openQuest)
                            // Only while Apple Health is on; refreshes itself when shown.
                            ActivityCard()
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
            // Content scrolling up no longer shows through the clock and battery.
            .overlay(alignment: .top) {
                Color.clear.frame(height: 0)
                    .background(Color.surfaceGrouped.opacity(0.94), ignoresSafeAreaEdges: .top)
                    .allowsHitTesting(false)
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showReminders) { RemindersView() }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView().navigationBarHidden(false)
            }
            .navigationDestination(isPresented: $showStock) { StockView() }
            .onReceive(NotificationCenter.default.publisher(for: .openProfile)) { _ in showProfile = true }
        }
        .sheet(isPresented: $vm.showLogSheet) { LogFoodSheet(vm: vm) }
        .sheet(isPresented: $vm.showAgentChat) { AgentChatSheet(vm: vm) }
        .task { await vm.load() }
        // Keeps the date, today's log and due reminders current while Home is
        // on screen: one cheap tick at each minute boundary.
        .task {
            while !Task.isCancelled {
                let seconds = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(for: .seconds(seconds + 0.05))
                guard !Task.isCancelled else { return }
                vm.tick()
            }
        }
        .onAppear {
            vm.activate()
            loop.refresh()
        }
        // A new day: today's quest starts over.
        .onChange(of: Calendar.current.startOfDay(for: vm.now)) { _, _ in loop.refresh() }
        .onChange(of: FoodLogStore.shared.revision) { _, _ in loop.refresh() }
        .onChange(of: StockStore.shared.logs.count) { _, _ in loop.refresh() }
        // The newest session's id changes even once the history is capped at 200.
        .onChange(of: WorkoutStore.shared.completed.first?.id) { _, _ in loop.refresh() }
        .onChange(of: WorkoutStore.shared.completed.count) { _, _ in loop.refresh() }
        .onChange(of: AppState.shared.userProfile.dailyCalorieGoal) { _, _ in loop.refresh() }
        .task(id: loop.pendingMilestone) {
            guard loop.pendingMilestone != nil else { return }
            try? await Task.sleep(for: .seconds(3.5))
            if !Task.isCancelled { loop.consumeMilestone() }
        }
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
        if let days = loop.pendingMilestone { return .milestone(days) }
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
        case .milestone(let days):
            statusPill("\(days)-day streak! Nourlo is proud of you.", systemImage: "sparkles")
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
    case milestone(Int)

    var id: String {
        switch self {
        case .offline: return "offline"
        case .backOnline: return "backOnline"
        case .deal(let deal): return "deal-\(deal.id)"
        case .milestone(let days): return "milestone-\(days)"
        }
    }

    var islandStyle: MorphIslandStyle {
        if case .deal = self { return .expanded }
        return .compact
    }
}

#Preview { HomeView().environment(AppState.shared) }
