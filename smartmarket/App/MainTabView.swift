import SwiftUI
import TipKit

/// Every sheet `MainTabView` presents. One `sheet(item:)` shows them, so a new
/// destination (from a link, Spotlight or a quick action) always replaces the
/// current one instead of being lost or popping up later.
enum MainSheet: Identifiable, Equatable {
    case logFood, cart, groceries, chat
    case exercise(String)

    var id: String {
        switch self {
        case .logFood: return "logFood"
        case .cart: return "cart"
        case .groceries: return "groceries"
        case .chat: return "chat"
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
    @State private var navigationHeight: CGFloat = 80
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Hide the system tab bar so our floating one takes over
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                HomeView().tag(0).toolbar(.hidden, for: .tabBar)
                NavigationStack { MealPlanView() }.tag(1).toolbar(.hidden, for: .tabBar)
                StoreBrowserView().tag(2).toolbar(.hidden, for: .tabBar)
                TrainView().tag(3).toolbar(.hidden, for: .tabBar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A sibling reserves real layout space on every tab, including iPad.
            FloatingTabBar(selection: $selection, choose: chooseQuickAction, openChat: {
                guard sheet == nil else { return }
                present(.chat)
            })
                // Its goo menu pours out over the content above the bar.
                .zIndex(2)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: NavigationHeightKey.self, value: geometry.size.height)
                })
        }
        .onPreferenceChange(NavigationHeightKey.self) { navigationHeight = $0 }
        // The bowl's guide panel, above every tab (the bowl itself is in Home's header).
        .overlay(alignment: .top) {
            if !keyboardVisible {
                GeometryReader { geometry in
                    FloatingBowlGuide(selectedTab: $selection, availableHeight: geometry.size.height - navigationHeight,
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

private struct NavigationHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 80 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Floating tab bar

private struct FloatingTabBar: View {

    @Binding var selection: Int
    let choose: (MealioQuickAction) -> Void
    let openChat: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let quickActionsTip = QuickActionsTip()

    private let items: [(icon: String, filled: String, label: String)] = [
        ("house",               "house.fill",               "Home"),
        ("fork.knife.circle",   "fork.knife.circle.fill",   "Meals"),
        ("storefront",          "storefront.fill",          "Shop"),
        ("figure.run",          "figure.run",               "Train"),
    ]

    /// The + at the end of the bar pours these out. Ids are `MealioQuickAction`
    /// raw values, except "chat".
    private static let quickItems: [GooMenuItem] = [
        GooMenuItem(id: MealioQuickAction.logFood.rawValue, title: "Log food", systemImage: "fork.knife"),
        GooMenuItem(id: MealioQuickAction.cart.rawValue, title: "Cart", systemImage: "cart"),
        GooMenuItem(id: MealioQuickAction.groceries.rawValue, title: "Checklist", systemImage: "checklist"),
        GooMenuItem(id: "chat", title: "Ask Nourlo", systemImage: "bubble.left.and.text.bubble.right"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                TabItem(
                    icon:      item.icon,
                    filled:    item.filled,
                    label:     item.label,
                    isActive:  selection == idx,
                    index:     idx
                ) {
                    withAnimation(reduceMotion ? .none : .snappyValue) {
                        selection = idx
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            }
            // Bubbles fan out above the bar, clear of the tabs.
            GooMenu(items: Self.quickItems, accessibilityLabel: "Quick actions",
                    startAngle: 204, endAngle: 264,
                    openValue: "Quick actions shown", openHint: "Shows quick actions",
                    closeHint: "Closes the quick actions", itemHint: { "Opens \($0)" },
                    buttonIdentifier: "navigation.quickActions", itemIdentifierPrefix: "quickActions.",
                    glass: true,
                    onOpen: { quickActionsTip.invalidate(reason: .actionPerformed) }) { item in
                if item.id == "chat" { openChat() }
                else if let action = MealioQuickAction(rawValue: item.id) { choose(action) }
            }
            // The bar has no room for an inline tip; the popover points down at the +.
            .popoverTip(quickActionsTip, arrowEdge: .bottom)
            .padding(.horizontal, Spacing.sm)
        }
        // One shared pill behind the tabs: its edges are springs that chase the
        // selected tab's icon frame, so it stretches toward the new tab.
        .backgroundPreferenceValue(StretchTabPillAnchors.self) { anchors in
            GeometryReader { geometry in
                StretchTabPill(target: anchors[selection].map { geometry[$0] }, id: selection, isHidden: false) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.brandLight)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .modifier(TabBarBackground(radius: 24))
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .task { await NourloTips.donateLaunchOnce() }
    }
}

/// Liquid Glass behind the bar on iOS 26+; the solid card on earlier systems
/// and whenever Reduce Transparency is on.
private struct TabBarBackground: ViewModifier {
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content.glassCard(radius: radius)
        }
    }
}

private struct TabItem: View {

    let icon: String
    let filled: String
    let label: String
    let isActive: Bool
    /// Tab index; reports the icon frame for the shared stretch pill.
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: isActive ? filled : icon)
                    .font(.body.weight(isActive ? .semibold : .regular))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(isActive ? Color.brandPrimary : Color.labelSecondary)
                    .animation(reduceMotion ? .none : .snappyValue, value: isActive)
                    .frame(width: 46, height: 30)
                    .stretchTabPillAnchor(index)

                if !typeSize.isAccessibilitySize {
                    Text(label)
                        .font(.caption2.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Color.brandPrimary : Color.labelSecondary)
                        .lineLimit(1)
                }
            }
            // Keep its natural size while the open command field squeezes the slot to zero.
            .fixedSize()
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("tab.\(label.lowercased())")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isActive)
    }
}
