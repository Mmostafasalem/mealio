import SwiftUI

struct MainTabView: View {

    @State private var selection = 0
    @State private var activeAction: MealioQuickAction?
    @State private var quickLog = HomeViewModel()
    @State private var showGuideChat = false
    @State private var keyboardVisible = false
    @State private var navigationHeight: CGFloat = 80
    @AppStorage("bowlGuideVisible_v2") private var guideVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            // Reserve the small companion's footprint so it never covers the
            // last row or a screen's bottom action.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if guideVisible && !keyboardVisible { Color.clear.frame(height: 84) }
            }
            // A sibling reserves real layout space on every tab, including iPad.
            FloatingTabBar(selection: $selection, choose: chooseQuickAction, openChat: {
                guard activeAction == nil else { return }
                showGuideChat = true
            })
                // Its goo menu pours out over the content above the bar.
                .zIndex(2)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: NavigationHeightKey.self, value: geometry.size.height)
                })
        }
        .onPreferenceChange(NavigationHeightKey.self) { navigationHeight = $0 }
        // Keep the companion outside TabView's UIKit hierarchy.
        .overlay(alignment: .bottom) {
            if !keyboardVisible {
                GeometryReader { geometry in
                    FloatingBowlGuide(selectedTab: $selection, availableHeight: geometry.size.height - navigationHeight,
                                      attention: activeAction != nil || showGuideChat, choose: followGuide)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, navigationHeight)
                }
                .zIndex(10)
            }
        }
        .background(Color.surfaceGrouped)
        // Tab screens keep their layout under the keyboard.
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .sheet(isPresented: $showGuideChat) { AgentChatSheet(vm: quickLog) }
        .sheet(item: $activeAction) { action in
            switch action {
            case .logFood: LogFoodSheet(vm: quickLog)
            case .cart:
                NavigationStack {
                    CartView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { activeAction = nil }
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
            default: EmptyView()
            }
        }
    }

    private func chooseQuickAction(_ action: MealioQuickAction) {
        if action == .profile {
            openProfile()
        } else if let tab = action.tab {
            selection = tab
        } else {
            activeAction = action
        }
    }

    /// Profile lives behind the avatar on Home, not in the tab bar.
    private func openProfile() {
        selection = 0
        // Let Home become the visible tab before it pushes Profile.
        DispatchQueue.main.async { NotificationCenter.default.post(name: .openProfile, object: nil) }
    }

    private func followGuide(_ pathway: BowlPathway) {
        guard activeAction == nil else { return }
        switch pathway {
        case .logFood: activeAction = .logFood
        case .groceries: activeAction = .groceries
        case .meals: selection = 1
        case .shop: selection = 2
        case .profile: openProfile()
        case .chat: showGuideChat = true
        }
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
                    buttonIdentifier: "navigation.quickActions", itemIdentifierPrefix: "quickActions.") { item in
                if item.id == "chat" { openChat() }
                else if let action = MealioQuickAction(rawValue: item.id) { choose(action) }
            }
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
        .glassCard(radius: 24)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
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
