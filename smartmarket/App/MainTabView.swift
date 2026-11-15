import SwiftUI
import TipKit

/// Every sheet `MainTabView` presents. One `sheet(item:)` shows them, so a new
/// destination (from a link, Spotlight or a quick action) always replaces the
/// current one instead of being lost or popping up later.
enum MainSheet: Identifiable, Equatable {
    case logFood, cart, groceries, chat, quickActions
    case exercise(String)

    var id: String {
        switch self {
        case .logFood: return "logFood"
        case .cart: return "cart"
        case .groceries: return "groceries"
        case .chat: return "chat"
        case .quickActions: return "quickActions"
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

    var body: some View {
        // The system tab bar (Liquid Glass on iOS 26), icons only, like Apple's own apps.
        TabView(selection: tabSelection) {
            HomeView()
                .background(TabBarInsetReader())
                .tabItem { TabIcon(symbol: "house.fill", name: "Home") }
                .tag(0)
            NavigationStack { MealPlanView() }
                .tabItem { TabIcon(symbol: "fork.knife", name: "Meals") }
                .tag(1)
            Color.clear
                .tabItem { TabIcon(symbol: "plus.circle.fill", name: "Quick actions") }
                .tag(Self.quickActionsTag)
            StoreBrowserView()
                .tabItem { TabIcon(symbol: "storefront.fill", name: "Shop") }
                .tag(2)
            TrainView()
                .tabItem { TabIcon(symbol: "figure.run", name: "Train") }
                .tag(3)
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .openHome)) { _ in selection = 0 }
        .onReceive(NotificationCenter.default.publisher(for: .openShop)) { _ in selection = 2 }
        // Widgets, the Control Center button, Siri, Shortcuts and Spotlight open screens through the router.
        .onAppear { AppRouter.shared.takeInbox(); routeRequest() }
        .onChange(of: AppRouter.shared.request?.id) { _, _ in routeRequest() }
        .onChange(of: scenePhase) { _, phase in
            // A link left by another process (the widget extension) has no in-process notification.
            if phase == .active { AppRouter.shared.takeInbox(); routeRequest() }
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
            case .quickActions:
                QuickActionsMenu(close: { self.sheet = nil }) { choice in
                    switch choice {
                    case .chat: present(.chat)
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
            // An open food logger stays and opens the scanner itself.
            case .logFood, .scan: present(.logFood)
            case .groceries: present(.groceries)
            }
        }
    }

    private func chooseQuickAction(_ action: MealioQuickAction) {
        if action == .profile {
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
    enum Choice { case action(MealioQuickAction), chat }
    /// Closes the sheet through `MainTabView`'s own state (its single sheet path).
    let close: () -> Void
    let choose: (Choice) -> Void

    private let rows: [(id: String, title: String, symbol: String, choice: Choice)] = [
        (MealioQuickAction.logFood.rawValue, "Log food", "fork.knife", .action(.logFood)),
        (MealioQuickAction.cart.rawValue, "Cart", "cart", .action(.cart)),
        (MealioQuickAction.groceries.rawValue, "Checklist", "checklist", .action(.groceries)),
        ("chat", "Ask Nourlo", "bubble.left.and.text.bubble.right", .chat),
    ]

    var body: some View {
        NavigationStack {
            List(rows, id: \.id) { row in
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
        .presentationDetents([.height(300), .medium])
        .presentationDragIndicator(.visible)
    }
}
