import SwiftUI
import TipKit

/// Every sheet `MainTabView` presents. One `sheet(item:)` shows them, so a new
/// destination (from a link, Spotlight or a quick action) always replaces the
/// current one instead of being lost or popping up later.
enum MainSheet: Identifiable, Equatable {
    case logFood, cart, groceries, chat, voice, mealPhoto, stock, addRecipe
    case exercise(String)
    /// Something asked for a feature the person turned off: offer to turn it on.
    case featureOff(AppFeature)

    var id: String {
        switch self {
        case .logFood: return "logFood"
        case .cart: return "cart"
        case .groceries: return "groceries"
        case .chat: return "chat"
        case .voice: return "voice"
        case .mealPhoto: return "mealPhoto"
        case .stock: return "stock"
        case .addRecipe: return "addRecipe"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// The quick-actions pills that drop out of Nourlo at the top of each tab.
    @State private var quickActions = QuickActionsCenter.shared
    @State private var tour = GuidedTour.shared

    /// What the person uses Nourlo for; decides tabs, quick actions and where links may go.
    private var features: Set<AppFeature> { AppState.shared.enabledFeatures }
    /// Runs after the person turns a feature back on from the "turned off" prompt.
    @State private var afterFeatureEnabled: (() -> Void)?

    @ViewBuilder private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .meals: NavigationStack { MealPlanView() }
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

    /// The system tab bar (Liquid Glass on iOS 26), icons only, like Apple's own apps.
    /// Only the tabs for the features the person chose; Home is always there. Quick
    /// actions is Nourlo at the top of each tab (`NourloButton`), not a tab.
    @ViewBuilder private var tabs: some View {
        let all = FeatureLayout.tabs(for: features)
        if #available(iOS 18, *) {
            TabView(selection: $selection) {
                ForEach(all) { tab in
                    Tab(value: tab.rawValue) {
                        tabContent(tab)
                    } label: { TabIcon(symbol: tab.symbol, name: tab.name) }
                }
            }
        } else {
            TabView(selection: $selection) {
                ForEach(all) { tab in
                    tabContent(tab)
                        .tabItem { TabIcon(symbol: tab.symbol, name: tab.name) }
                        .tag(tab.rawValue)
                }
            }
        }
    }

    /// What a quick-action pill does.
    private func handleQuickChoice(_ choice: QuickActionsMenu.Choice) {
        switch choice {
        case .tour: GuidedTour.shared.replay()
        case .chat: present(.chat)
        case .voice: present(.voice)
        case .mealPhoto: present(.mealPhoto)
        case .stock: present(.stock)
        case .addRecipe: present(.addRecipe)
        case .action(let action): chooseQuickAction(action)
        }
    }

    var body: some View {
        tabs
        .tint(Color.brandPrimary)
        .sensoryFeedback(.selection, trigger: selection)
        // A feature turned off in Profile takes its tab with it; stay on a tab that exists.
        .onChange(of: features) { _, now in
            if !FeatureLayout.tabs(for: now).contains(where: { $0.rawValue == selection }) {
                selection = AppTab.home.rawValue
            }
        }
        // The quick-action pills that drop out of Nourlo, over everything (the bar too).
        .overlay {
            if quickActions.isOpen {
                QuickActionsMenu(features: features, choose: { handleQuickChoice($0) })
            }
        }
        // A sheet or a tab change closes them.
        .onChange(of: sheet) { _, now in if now != nil, tour.current?.page != .quickActions { quickActions.requestClose() } }
        .onChange(of: selection) { _, _ in if tour.current?.page != .quickActions { quickActions.requestClose() } }
        // The guided tour (once after onboarding, again from Profile › Help or the
        // quick actions) dims everything, the bar and the pills too.
        .overlay { GuidedTourOverlay() }
        .onChange(of: tour.current?.page) { _, page in followTour(page) }
        .sensoryFeedback(.impact(weight: .medium), trigger: quickActions.opens)
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
        .onAppear {
            AppRouter.shared.takeInbox(); routeRequest(); checkNewWeek()
            GuidedTour.shared.startIfNeeded(features: features)
        }
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
            case .stock:
                NavigationStack {
                    StockView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { self.sheet = nil }
                                    .accessibilityIdentifier("quickStock.done")
                            }
                        }
                }
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
            case .addRecipe:
                RecipeImportSheet { self.sheet = nil }
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.large])
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
        // Meal photos open even without online AI: the photo is then saved to clarify later.
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
                    // A screen, not a sheet: close the quick actions and go there.
                    present(nil)
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

    /// The tour goes to each step's page: its tab, the pills over Home, or Profile
    /// (which Home pushes itself, `HomeView`).
    private func followTour(_ page: TourPage?) {
        guard let page else {
            quickActions.requestClose()
            return
        }
        present(nil)
        selection = page.tab.rawValue
        if page == .quickActions {
            // Once Home is showing, so the pills hang under Home's Nourlo.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if tour.current?.page == .quickActions { quickActions.open() }
            }
        } else {
            quickActions.requestClose()
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
