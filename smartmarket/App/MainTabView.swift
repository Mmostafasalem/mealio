import SwiftUI

struct MainTabView: View {

    @State private var selection = 0
    @State private var showQuickActions = false
    @State private var quickQuery = ""
    /// The bar rides the keyboard while the command field is open (and until that keyboard is gone).
    @State private var barFollowsKeyboard = false
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
            // Open, results float directly above the bar; a tap outside folds it back.
            .overlay(alignment: .bottom) {
                if showQuickActions {
                    ZStack(alignment: .bottom) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { closeQuickActions() }
                            .accessibilityHidden(true)
                        QuickActionsPanel(query: quickQuery, choose: chooseQuickAction)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.top, Spacing.xl)
                            .padding(.bottom, Spacing.sm)
                            .transition(panelTransition)
                    }
                }
            }
            // Reserve the small companion's footprint so it never covers the
            // last row or a screen's bottom action.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if guideVisible && !keyboardVisible { Color.clear.frame(height: 84) }
            }
            // A sibling reserves real layout space on every tab, including iPad.
            FloatingTabBar(
                selection: $selection,
                isOpen: quickActionsOpen,
                query: $quickQuery,
                choose: chooseQuickAction
            )
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: NavigationHeightKey.self, value: geometry.size.height)
                })
        }
        .onPreferenceChange(NavigationHeightKey.self) { navigationHeight = $0 }
        // Keep the companion outside TabView's UIKit hierarchy.
        .overlay(alignment: .bottom) {
            if !keyboardVisible && !showQuickActions {
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
        // Tab screens keep their layout under the keyboard; only the open
        // command field lifts the bar above it.
        .ignoresSafeArea(showQuickActions || barFollowsKeyboard ? [] : .keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
            if !showQuickActions { barFollowsKeyboard = false }
        }
        .onChange(of: showQuickActions) { _, open in
            if open { barFollowsKeyboard = true } else if !keyboardVisible { barFollowsKeyboard = false }
        }
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

    /// Opening is gated on no action sheet being up; closing always goes through.
    private var quickActionsOpen: Binding<Bool> {
        Binding(
            get: { showQuickActions },
            set: { open in if !open || activeAction == nil { showQuickActions = open } }
        )
    }

    /// Results rise with the field's stretch (no entry delay).
    private var panelTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8))
                .animation(reduceMotion ? .easeOut(duration: 0.12) : CommandButtonMotion.swapCurve),
            removal: .opacity.animation(CommandButtonMotion.swapCurve))
    }

    private func closeQuickActions() {
        guard showQuickActions else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(reduceMotion ? nil : CommandButtonMotion.open) {
            showQuickActions = false
            quickQuery = ""
        }
    }

    private func chooseQuickAction(_ action: MealioQuickAction) {
        closeQuickActions()
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
        guard activeAction == nil, !showQuickActions else { return }
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
    @Binding var isOpen: Bool
    @Binding var query: String
    let choose: (MealioQuickAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selection: Binding<Int>, isOpen: Binding<Bool>, query: Binding<String>,
         choose: @escaping (MealioQuickAction) -> Void) {
        _selection = selection
        _isOpen = isOpen
        _query = query
        self.choose = choose
    }

    private let items: [(icon: String, filled: String, label: String)] = [
        ("house",               "house.fill",               "Home"),
        ("fork.knife.circle",   "fork.knife.circle.fill",   "Meals"),
        ("storefront",          "storefront.fill",          "Shop"),
        ("figure.run",          "figure.run",               "Train"),
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
                // Open, the tabs collapse so the field spans the bar.
                .frame(minWidth: 0, maxWidth: .infinity)
                .opacity(isOpen ? 0 : 1)
                .blur(radius: isOpen && !reduceMotion ? CommandButtonMotion.swapBlur : 0)
                .clipped()
                .disabled(isOpen)
                .accessibilityHidden(isOpen)
            }
            CommandButton(
                isOpen: $isOpen,
                query: $query,
                label: "Quick Actions",
                idle: .icon,
                buttonIdentifier: "navigation.quickActions",
                fieldIdentifier: "quickActions.search",
                onSubmit: { if let first = MealioQuickAction.matching(query).first { choose(first) } }
            )
            .layoutPriority(1)
        }
        // One shared pill behind the tabs: its edges are springs that chase the
        // selected tab's icon frame, so it stretches toward the new tab.
        .backgroundPreferenceValue(StretchTabPillAnchors.self) { anchors in
            GeometryReader { geometry in
                StretchTabPill(target: anchors[selection].map { geometry[$0] }, id: selection, isHidden: isOpen) {
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

/// Results for the command field: local screens and actions only, never AI.
private struct QuickActionsPanel: View {
    let query: String
    let choose: (MealioQuickAction) -> Void

    var body: some View {
        let matches = MealioQuickAction.matching(query)
        ViewThatFits(in: .vertical) {
            content(matches)
            ScrollView { content(matches) }.scrollBounceBehavior(.basedOnSize)
        }
        .glassCard(radius: Radius.card)
    }

    private func content(_ matches: [MealioQuickAction]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if matches.isEmpty {
                Text("No screen or action matches \u{201C}\(query)\u{201D}.")
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                ForEach(matches) { action in
                    Button { choose(action) } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: action.symbol)
                                .frame(width: 24).foregroundStyle(Color.brandPrimary)
                            Text(action.title).foregroundStyle(Color.labelPrimary)
                            Spacer(minLength: Spacing.sm)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quickActions." + action.rawValue)
                }
            }
            Text("Nothing here uses online AI.")
                .font(.footnote)
                .foregroundStyle(Color.labelSecondary)
                .padding(.top, Spacing.sm)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
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
