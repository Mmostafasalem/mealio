import SwiftUI
import TipKit

/// Every sheet `MainTabView` presents. One `sheet(item:)` shows them, so a new
/// destination (from a link, Spotlight or a quick action) always replaces the
/// current one instead of being lost or popping up later.
enum MainSheet: Identifiable, Equatable {
    case logFood, cart, groceries, chat, quickActions, voice, mealPhoto
    case exercise(String)
    /// Something asked for a feature the person turned off: offer to turn it on.
    case featureOff(AppFeature)

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
        case .featureOff(let feature): return "featureOff:" + feature.rawValue
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
    private static let quickActionsTag = AppTab.quickActions.rawValue

    /// What the person uses Nourlo for; decides tabs, quick actions and where links may go.
    private var features: Set<AppFeature> { AppState.shared.enabledFeatures }
    /// Runs after the person turns a feature back on from the "turned off" prompt.
    @State private var afterFeatureEnabled: (() -> Void)?

    @ViewBuilder private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView().background(TabBarInsetReader())
        case .meals: NavigationStack { MealPlanView() }
        case .quickActions: Color.clear
        case .shop: StoreBrowserView()
        case .train: TrainView()
        }
    }

    /// Runs `action` when `feature` is on; otherwise asks whether to turn it on
    /// (a link, Siri or a reminder can still ask for a feature the person turned off).
    private func requiring(_ feature: AppFeature?, _ action: @escaping () -> Void) {
        guard let feature, !AppState.shared.isEnabled(feature) else { action(); return }
        afterFeatureEnabled = action
        present(.featureOff(feature))
    }

    /// Shows a tab, or the prompt to turn its feature on.
    private func show(_ tab: AppTab) {
        requiring(tab.feature) { present(nil); selection = tab.rawValue }
    }

    private var tabSelection: Binding<Int> {
        Binding(get: { selection }, set: { tag in
            if tag == Self.quickActionsTag { present(.quickActions) } else { selection = tag }
        })
    }

    /// The system tab bar (Liquid Glass on iOS 26), icons only, like Apple's own apps.
    /// Only the tabs for the features the person chose; Home and quick actions are
    /// always there, quick actions in the middle of the same bar (an ordinary tab, not
    /// the separate search-style button iOS 26 would draw for a search role).
    @ViewBuilder private var tabs: some View {
        let all = FeatureLayout.tabs(for: features)
        if #available(iOS 18, *) {
            TabView(selection: tabSelection) {
                ForEach(all) { tab in
                    Tab(value: tab.rawValue) {
                        if tab == .quickActions { Color.clear } else { tabContent(tab) }
                    } label: { TabIcon(symbol: tab.symbol, name: tab.name) }
                }
            }
        } else {
            TabView(selection: tabSelection) {
                ForEach(all) { tab in
                    Group {
                        if tab == .quickActions { Color.clear } else { tabContent(tab) }
                    }
                    .tabItem { TabIcon(symbol: tab.symbol, name: tab.name) }
                    .tag(tab.rawValue)
                }
            }
        }
    }

    var body: some View {
        tabs
        .tint(Color.brandPrimary)
        .sensoryFeedback(.selection, trigger: selection)
        .onPreferenceChange(TabBarInsetKey.self) { tabBarHeight = $0 }
        // A feature turned off in Profile takes its tab with it; stay on a tab that exists.
        .onChange(of: features) { _, now in
            if !FeatureLayout.tabs(for: now).contains(where: { $0.rawValue == selection }) {
                selection = AppTab.home.rawValue
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .openTrain)) { _ in requiring(.workouts) { selection = 3 } }
        .onReceive(NotificationCenter.default.publisher(for: .openVoice)) { _ in present(.voice) }
        .onReceive(NotificationCenter.default.publisher(for: .openMealPhoto)) { _ in requiring(.tracking) { present(.mealPhoto) } }
        .onReceive(NotificationCenter.default.publisher(for: .openHome)) { _ in selection = 0 }
        .onReceive(NotificationCenter.default.publisher(for: .openShop)) { _ in requiring(.groceries) { selection = 2 } }
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
                QuickActionsMenu(features: features, close: { self.sheet = nil }) { choice in
                    switch choice {
                    case .chat: present(.chat)
                    case .voice: present(.voice)
                    case .mealPhoto: present(.mealPhoto)
                    case .action(let action): chooseQuickAction(action)
                    }
                }
            case .featureOff(let feature):
                FeatureOffPrompt(feature: feature,
                                 turnOn: { enableFromPrompt(feature) },
                                 close: { afterFeatureEnabled = nil; self.sheet = nil })
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
        // A feature the person turned off opens a prompt to turn it on instead.
        switch destination {
        case .exercise(let id):
            requiring(.workouts) { present(.exercise(id)) }
        case .link(let link):
            requiring(FeatureLayout.feature(for: link)) {
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
    }

    private func chooseQuickAction(_ action: MealioQuickAction) {
        if action == .profile {
            // Chosen from the "+" sheet: close it, then show Profile on Home.
            present(nil)
            openProfile()
        } else {
            requiring(FeatureLayout.feature(for: action)) {
                if let tab = action.tab {
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
        }
    }

    /// Where a spoken command leads; the voice sheet is replaced by its destination.
    private func openFromVoice(_ navigation: VoiceNavigation) {
        switch navigation {
        case .screen(let screen):
            switch screen {
            case .home: present(nil); selection = 0
            case .meals: show(.meals)
            case .shop: show(.shop)
            case .train: show(.train)
            case .cart: requiring(.groceries) { present(.cart) }
            case .checklist: requiring(.groceries) { present(.groceries) }
            case .logFood: requiring(.tracking) { present(.logFood) }
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
        case .logFood: requiring(.tracking) { present(.logFood) }
        case .groceries: requiring(.groceries) { present(.groceries) }
        case .meals: requiring(.meals) { selection = 1 }
        case .shop: requiring(.groceries) { selection = 2 }
        case .train: requiring(.workouts) { selection = 3 }
        case .profile: openProfile()
        case .chat: present(.chat)
        }
    }

    /// The person turned a feature on from the prompt: go where they were heading.
    private func enableFromPrompt(_ feature: AppFeature) {
        AppState.shared.setFeature(feature, enabled: true)
        let action = afterFeatureEnabled
        afterFeatureEnabled = nil
        present(nil)
        // After the prompt has gone, so a sheet destination isn't dropped.
        DispatchQueue.main.async { action?() }
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
    /// Only actions for these features are offered (`FeatureLayout.quickActionIDs`).
    let features: Set<AppFeature>
    /// Closes the sheet through `MainTabView`'s own state (its single sheet path).
    let close: () -> Void
    let choose: (Choice) -> Void

    private var rows: [(id: String, title: String, symbol: String, choice: Choice)] {
        let offered = FeatureLayout.quickActionIDs(for: features)
        return Self.allRows.filter { offered.contains($0.id) }
    }

    private static let allRows: [(id: String, title: String, symbol: String, choice: Choice)] = [
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
        // UI tests can run across a week boundary; the once-a-week question would cover the tab bar.
        if ProcessInfo.processInfo.arguments.contains("-NourloUITesting"),
           !ProcessInfo.processInfo.arguments.contains("-NourloAskNewWeek") { return }
        let hasSomething = !ShoppingCartService.shared.cartItems.isEmpty || !StockStore.shared.items.isEmpty
        if WeeklyReset.isDue(hasSomething: hasSomething) { askNewWeek = true }
    }
}
