import SwiftUI
import TipKit

/// Every sheet `MainTabView` presents. One `sheet(item:)` shows them, so a new
/// destination (from a link, Spotlight or a quick action) always replaces the
/// current one instead of being lost or popping up later.
enum MainSheet: Identifiable, Equatable {
    case logFood, cart, groceries, chat, quickActions, voice, mealPhoto
    case exercise(String)

    var id: String {
        switch self {
        case .logFood: return "logFood"
        case .cart: return "cart"
        case .groceries: return "groceries"
        case .chat: return "chat"
        case .quickActions: return "quickActions"
        case .voice: return "voice"
        case .mealPhoto: return "mealPhoto"
        case .exercise(let id): return "exercise:" + id
        }
    }
}

struct MainTabView: View {

    @State private var selection = 0
    @State private var sheet: MainSheet?
    /// What to show once the current presentation has gone (`nil`: nothing).
    @State private var queuedSheet: MainSheet?
    @State private var awaitingDismissal = false
    @State private var dismissalTimeout: Task<Void, Never>?
    @State private var quickLog = HomeViewModel()
    @State private var keyboardVisible = false
    /// A new week has started: ask whether to empty the cart and My Stock.
    @State private var askNewWeek = false
    /// Height of the system tab bar above the home indicator (sizes the bowl's guide panel).
    @State private var tabBarHeight: CGFloat = 49
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// The "+" in the middle of the tab bar is a button, not a screen: choosing it
    /// opens the quick actions and leaves the current tab selected.
    private static let quickActionsTag = 4

    private var tabSelection: Binding<Int> {
        Binding(get: { selection }, set: { tag in
            if tag == Self.quickActionsTag { present(.quickActions) } else { selection = tag }
        })
    }

    /// The system tab bar (Liquid Glass on iOS 26), icons only, like Apple's own apps.
    /// From iOS 18 quick actions is a separate tab; on iOS 26 the system draws it as its
    /// own round glass button at the end of the bar, apart from the four screens.
    @ViewBuilder private var tabs: some View {
        if #available(iOS 18, *) {
            TabView(selection: tabSelection) {
                Tab(value: 0) { HomeView().background(TabBarInsetReader()) } label: { TabIcon(symbol: "house.fill", name: "Home") }
                Tab(value: 1) { NavigationStack { MealPlanView() } } label: { TabIcon(symbol: "fork.knife", name: "Meals") }
                Tab(value: 2) { StoreBrowserView() } label: { TabIcon(symbol: "storefront.fill", name: "Shop") }
                Tab(value: 3) { TrainView() } label: { TabIcon(symbol: "figure.run", name: "Train") }
                Tab(value: Self.quickActionsTag, role: .search) { Color.clear } label: {
                    TabIcon(symbol: "bolt.fill", name: "Quick actions")
                }
            }
        } else {
            TabView(selection: tabSelection) {
                HomeView()
                    .background(TabBarInsetReader())
                    .tabItem { TabIcon(symbol: "house.fill", name: "Home") }
                    .tag(0)
                NavigationStack { MealPlanView() }
                    .tabItem { TabIcon(symbol: "fork.knife", name: "Meals") }
                    .tag(1)
                StoreBrowserView()
                    .tabItem { TabIcon(symbol: "storefront.fill", name: "Shop") }
                    .tag(2)
                TrainView()
                    .tabItem { TabIcon(symbol: "figure.run", name: "Train") }
                    .tag(3)
                Color.clear
                    .tabItem { TabIcon(symbol: "bolt.fill", name: "Quick actions") }
                    .tag(Self.quickActionsTag)
            }
        }
    }

    var body: some View {
        tabs
        .tint(Color.brandPrimary)
        .sensoryFeedback(.selection, trigger: selection)
        .onPreferenceChange(TabBarInsetKey.self) { tabBarHeight = $0 }
        // The bowl's guide panel, above every tab (the bowl itself is in Home's header).
        .overlay(alignment: .top) {
            if !keyboardVisible {
                GeometryReader { geometry in
                    FloatingBowlGuide(selectedTab: $selection, availableHeight: geometry.size.height - tabBarHeight,
                                      choose: followGuide)
                }
                .zIndex(10)
            }
        }
        .background(Color.surfaceGrouped)
        // Tab screens keep their layout under the keyboard.
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: .openTrain)) { _ in selection = 3 }
        .onReceive(NotificationCenter.default.publisher(for: .openVoice)) { _ in present(.voice) }
        .onReceive(NotificationCenter.default.publisher(for: .openMealPhoto)) { _ in present(.mealPhoto) }
        .onReceive(NotificationCenter.default.publisher(for: .openHome)) { _ in selection = 0 }
        .onReceive(NotificationCenter.default.publisher(for: .openShop)) { _ in selection = 2 }
        // Widgets, the Control Center button, Siri, Shortcuts and Spotlight open screens through the router.
        .onAppear { AppRouter.shared.takeInbox(); routeRequest(); checkNewWeek() }
        .onChange(of: AppRouter.shared.request?.id) { _, _ in routeRequest() }
        .onChange(of: scenePhase) { _, phase in
            // A link left by another process (the widget extension) has no in-process notification.
            if phase == .active { AppRouter.shared.takeInbox(); routeRequest(); checkNewWeek() }
        }
        .confirmationDialog("A new week has started", isPresented: $askNewWeek, titleVisibility: .visible) {
            Button("Empty cart and stock") { WeeklyReset.answer(.cartAndStock) }
            Button("Empty the cart only") { WeeklyReset.answer(.cartOnly) }
            Button("Keep everything", role: .cancel) { WeeklyReset.answer(.keep) }
        } message: {
            Text("Start this week fresh? Emptying clears last week's cart and the food in My Stock. Your food log and history stay. You can change your week's start day in Profile.")
        }
        .sheet(item: $sheet, onDismiss: { if awaitingDismissal { finishDismissal() } }) { sheet in
            switch sheet {
            case .logFood: LogFoodSheet(vm: quickLog)
            case .cart:
                NavigationStack {
                    CartView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { self.sheet = nil }
                                    .accessibilityIdentifier("quickCart.done")
                            }
                        }
                }
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
            case .groceries:
                GroceryListView()
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.large])
            case .chat:
                AgentChatSheet(vm: quickLog)
            case .voice:
                VoiceCommandSheet(close: { self.sheet = nil }, navigate: openFromVoice)
            case .mealPhoto:
                VoiceCommandSheet(photoMode: true, close: { self.sheet = nil }, navigate: openFromVoice)
            case .quickActions:
                QuickActionsMenu(close: { self.sheet = nil }) { choice in
                    switch choice {
                    case .chat: present(.chat)
                    case .voice: present(.voice)
                    case .mealPhoto: present(.mealPhoto)
                    case .action(let action): chooseQuickAction(action)
                    }
                }
            case .exercise(let id):
                if let exercise = Exercise.catalog.first(where: { $0.id == id }) {
                    ExerciseGuideSheet(guide: ExerciseGuide(exercise: exercise))
                }
            }
        }
    }

    // MARK: Presentation

    /// Shows `next` (or nothing), first dismissing whatever is on screen: one of
    /// our sheets, or a sheet or popover another screen presented. The new one
    /// appears only after the old one has gone, so it is never dropped.
    private func present(_ next: MainSheet?) {
        // Chat needs online AI: while it isn't offered, Siri, links and voice don't open it.
        if next == .chat && !AIAccountService.shared.offersOnlineAI { return }
        // Meal photos need online AI that can be used right now (offered, allowed, signed in).
        if next == .mealPhoto && !MealPhotoAccess.isUsable { return }
        if awaitingDismissal {
            // Something is already going away; show the newest request after it.
            queuedSheet = next
            return
        }
        if let current = sheet {
            guard current != next else { return }
            queuedSheet = next
            beginDismissal()
            sheet = nil                       // onDismiss → finishDismissal()
        } else if PresentedScreens.hasPresentation {
            queuedSheet = next
            beginDismissal()
            PresentedScreens.dismissAll { finishDismissal() }
        } else {
            sheet = next
        }
    }

    private func beginDismissal() {
        awaitingDismissal = true
        // In case a dismissal never reports back, don't hold requests forever.
        dismissalTimeout?.cancel()
        dismissalTimeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, awaitingDismissal else { return }
            finishDismissal()
        }
    }

    private func finishDismissal() {
        guard awaitingDismissal else { return }
        awaitingDismissal = false
        dismissalTimeout?.cancel()
        dismissalTimeout = nil
        let next = queuedSheet
        queuedSheet = nil
        if let next { sheet = next }
    }

    /// Shows the screen an outside entry point asked for. Each request is taken
    /// once; stale ones are dropped by the router.
    private func routeRequest() {
        guard let destination = AppRouter.shared.takeRequest() else { return }
        switch destination {
        case .exercise(let id):
            present(.exercise(id))
        case .link(let link):
            switch link {
            case .home: present(nil); selection = 0
            case .meals: present(nil); selection = 1
            case .train: present(nil); selection = 3
            // An open food logger stays (with what was typed) and opens the scanner itself.
            case .logFood, .scan: if sheet != .logFood { present(.logFood) }
            case .groceries: present(.groceries)
            }
        }
    }

    private func chooseQuickAction(_ action: MealioQuickAction) {
        if action == .profile {
            // Chosen from the "+" sheet: close it, then show Profile on Home.
            present(nil)
            openProfile()
        } else if let tab = action.tab {
            selection = tab
        } else {
            switch action {
            case .logFood: present(.logFood)
            case .cart: present(.cart)
            case .groceries: present(.groceries)
            default: break
            }
        }
    }

    /// Where a spoken command leads; the voice sheet is replaced by its destination.
    private func openFromVoice(_ navigation: VoiceNavigation) {
        switch navigation {
        case .screen(let screen):
            switch screen {
            case .home: present(nil); selection = 0
            case .meals: present(nil); selection = 1
            case .shop: present(nil); selection = 2
            case .train: present(nil); selection = 3
            case .cart: present(.cart)
            case .checklist: present(.groceries)
            case .logFood: present(.logFood)
            case .chat: present(.chat)
            case .scan: AppRouter.shared.open(.scan)
            case .profile: present(nil); openProfile()
            }
        case .workout(let kind, let minutes):
            AppRouter.shared.startWorkout(kind: kind, minutes: minutes)
        case .exercise(let id):
            AppRouter.shared.showExercise(id: id)
        }
    }

    /// Profile lives behind the avatar on Home, not in the tab bar.
    private func openProfile() {
        selection = 0
        // Let Home become the visible tab before it pushes Profile.
        DispatchQueue.main.async { NotificationCenter.default.post(name: .openProfile, object: nil) }
    }

    private func followGuide(_ pathway: BowlPathway) {
        guard sheet == nil else { return }
        switch pathway {
        case .logFood: present(.logFood)
        case .groceries: present(.groceries)
        case .meals: selection = 1
        case .shop: selection = 2
        case .profile: openProfile()
        case .chat: present(.chat)
        }
    }
}

/// Sheets and popovers presented outside `MainTabView`'s own sheet (by a tab's
/// screen, or a tip popover), so a link can clear them before it shows its own.
@MainActor
enum PresentedScreens {
    private static var root: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController
    }

    static var hasPresentation: Bool {
        guard let presented = root?.presentedViewController else { return false }
        return !presented.isBeingDismissed
    }

    /// Dismisses everything presented on the key window, then calls `completion`.
    static func dismissAll(completion: @escaping () -> Void) {
        guard let root, root.presentedViewController != nil else { completion(); return }
        root.dismiss(animated: !UIAccessibility.isReduceMotionEnabled, completion: completion)
    }
}

// MARK: - System tab bar

/// One tab's icon. The name isn't shown (icons only, like Apple's own apps) but
/// VoiceOver and Voice Control still use it.
private struct TabIcon: View {
    let symbol: String
    let name: String

    var body: some View {
        Image(systemName: symbol)
            .environment(\.symbolVariants, .fill)
            .accessibilityLabel(name)
    }
}

/// How much of the screen bottom the tab bar covers, read from a tab's content
/// (its bottom safe area is the bar plus the home indicator).
private struct TabBarInsetReader: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: TabBarInsetKey.self, value: geometry.safeAreaInsets.bottom)
        }
    }
}

private struct TabBarInsetKey: PreferenceKey {
    static var defaultValue: CGFloat { 49 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// What the "+" tab offers, as a native sheet.
private struct QuickActionsMenu: View {
    enum Choice { case action(MealioQuickAction), chat, voice, mealPhoto }
    /// Closes the sheet through `MainTabView`'s own state (its single sheet path).
    let close: () -> Void
    let choose: (Choice) -> Void

    private let rows: [(id: String, title: String, symbol: String, choice: Choice)] = [
        ("voice", "Speak a command", "mic.fill", .voice),
        ("mealPhoto", "Snap a meal", "camera.fill", .mealPhoto),
        (MealioQuickAction.logFood.rawValue, "Log food", "fork.knife", .action(.logFood)),
        (MealioQuickAction.cart.rawValue, "Cart", "cart", .action(.cart)),
        (MealioQuickAction.groceries.rawValue, "Checklist", "checklist", .action(.groceries)),
        ("chat", "Ask Nourlo", "bubble.left.and.text.bubble.right", .chat),
        (MealioQuickAction.profile.rawValue, "Profile", "person.crop.circle", .action(.profile)),
    ]

    var body: some View {
        NavigationStack {
            List(rows.filter { row in
                if case .chat = row.choice { return AIAccountService.shared.offersOnlineAI }
                if case .mealPhoto = row.choice { return MealPhotoAccess.isUsable }
                return true
            }, id: \.id) { row in
                Button { choose(row.choice) } label: {
                    Label(row.title, systemImage: row.symbol)
                        .foregroundStyle(Color.labelPrimary)
                }
                .accessibilityIdentifier("quickActions." + row.id)
            }
            .navigationTitle("Quick actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { close() }.accessibilityIdentifier("quickActions.done")
                }
            }
        }
        .presentationDetents([.height(470), .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - New week

extension MainTabView {
    /// Asks once per new week whether to empty the cart and My Stock (see `WeeklyReset`).
    fileprivate func checkNewWeek() {
        let hasSomething = !ShoppingCartService.shared.cartItems.isEmpty || !StockStore.shared.items.isEmpty
        if WeeklyReset.isDue(hasSomething: hasSomething) { askNewWeek = true }
    }
}
