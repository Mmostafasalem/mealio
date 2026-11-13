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
    /// The last quick-actions or tab change came from the keyboard (⌘K, Esc, ⌘1–⌘5):
    /// those apply with no motion, taps keep theirs.
    @State private var keyboardChange = false
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
                StoreMapView().tag(3).toolbar(.hidden, for: .tabBar)
                NavigationStack { ProfileView() }.tag(4).toolbar(.hidden, for: .tabBar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Open, results float directly above the bar; a tap outside folds it back.
            .overlay(alignment: .bottom) {
                if showQuickActions {
                    ZStack(alignment: .bottom) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { closeQuickActions(fromKeyboard: false) }
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
            // last row, map controls or a screen's bottom action.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if guideVisible && !keyboardVisible { Color.clear.frame(height: 84) }
            }
            // A sibling reserves real layout space on every tab, including iPad.
            FloatingTabBar(
                selection: $selection,
                isOpen: quickActionsOpen,
                query: $quickQuery,
                keyboardChange: $keyboardChange,
                choose: { chooseQuickAction($0, fromKeyboard: false) }
            )
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: NavigationHeightKey.self, value: geometry.size.height)
                })
        }
        .onPreferenceChange(NavigationHeightKey.self) { navigationHeight = $0 }
        // Keep the companion outside TabView's UIKit hierarchy. In particular,
        // MapKit's gesture surface must not intercept the floating button.
        .overlay(alignment: .bottom) {
            if !keyboardVisible && !showQuickActions {
                GeometryReader { geometry in
                    FloatingBowlGuide(selectedTab: $selection, availableHeight: geometry.size.height - navigationHeight, choose: followGuide)
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

    /// Results rise with the field's stretch (no entry delay); from the keyboard they just appear.
    private var panelTransition: AnyTransition {
        guard !keyboardChange else { return .identity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8))
                .animation(reduceMotion ? .easeOut(duration: 0.12) : CommandButtonMotion.swapCurve),
            removal: .opacity.animation(CommandButtonMotion.swapCurve))
    }

    private func closeQuickActions(fromKeyboard: Bool) {
        guard showQuickActions else { return }
        MotionKeyboard.change(fromKeyboard, flag: $keyboardChange) {
            guard showQuickActions else { return }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            let fold = {
                showQuickActions = false
                quickQuery = ""
            }
            if fromKeyboard { MotionKeyboard.withoutMotion(fold) }
            else { withAnimation(reduceMotion ? nil : CommandButtonMotion.open, fold) }
        }
    }

    private func chooseQuickAction(_ action: MealioQuickAction, fromKeyboard: Bool) {
        closeQuickActions(fromKeyboard: fromKeyboard)
        if let tab = action.tab {
            if fromKeyboard { MotionKeyboard.withoutMotion { selection = tab } } else { selection = tab }
        } else {
            activeAction = action
        }
    }

    private func followGuide(_ pathway: BowlPathway) {
        guard activeAction == nil, !showQuickActions else { return }
        switch pathway {
        case .logFood: activeAction = .logFood
        case .groceries: activeAction = .groceries
        case .meals: selection = 1
        case .shop: selection = 2
        case .map: selection = 3
        case .profile: selection = 4
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
    @Binding var keyboardChange: Bool
    let choose: (MealioQuickAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var barWidth: CGFloat = 0

    init(selection: Binding<Int>, isOpen: Binding<Bool>, query: Binding<String>,
         keyboardChange: Binding<Bool>,
         choose: @escaping (MealioQuickAction) -> Void) {
        _selection = selection
        _isOpen = isOpen
        _query = query
        _keyboardChange = keyboardChange
        self.choose = choose
    }

    private let items: [(icon: String, filled: String, label: String)] = [
        ("house",               "house.fill",               "Home"),
        ("fork.knife.circle",   "fork.knife.circle.fill",   "Meals"),
        ("storefront",          "storefront.fill",          "Shop"),
        ("map",                 "map.fill",                 "Map"),
        ("person.crop.circle",  "person.crop.circle.fill",  "Profile"),
    ]

    /// Room for the ⌘ K caps next to five tabs; compact phones get the magnifier alone.
    private var showsKeys: Bool { barWidth >= 340 && !typeSize.isAccessibilitySize }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                TabItem(
                    icon:      item.icon,
                    filled:    item.filled,
                    label:     item.label,
                    isActive:  selection == idx,
                    index:     idx,
                    shortcut: KeyEquivalent(Character(String(idx + 1))),
                    keyboardAction: {
                        // ⌘1–⌘5: switch at once, no pill stretch or icon spring.
                        MotionKeyboard.withoutMotion {
                            keyboardChange = true
                            selection = idx
                        }
                    }
                ) {
                    keyboardChange = false
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
                shortcut: "⌘K",
                idle: showsKeys ? .keys : .icon,
                buttonIdentifier: "navigation.quickActions",
                fieldIdentifier: "quickActions.search",
                keyboardChange: $keyboardChange,
                onSubmit: { if let first = MealioQuickAction.matching(query).first { choose(first) } }
            )
            .layoutPriority(1)
        }
        // One shared pill behind the tabs: its edges are springs that chase the
        // selected tab's icon frame, so it stretches toward the new tab.
        .backgroundPreferenceValue(StretchTabPillAnchors.self) { anchors in
            GeometryReader { geometry in
                StretchTabPill(target: anchors[selection].map { geometry[$0] }, id: selection, isHidden: isOpen,
                               animated: !keyboardChange) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.brandLight)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { barWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { _, width in barWidth = width }
        })
        .glassCard(radius: 24)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }
}

/// Results for the command field: local screens and actions only, never AI.
private struct QuickActionsPanel: View {
    let query: String
    /// The action, and whether it came from its keyboard shortcut.
    let choose: (MealioQuickAction, Bool) -> Void

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
                    Button { choose(action, false) } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: action.symbol)
                                .frame(width: 24).foregroundStyle(Color.brandPrimary)
                            Text(action.title).foregroundStyle(Color.labelPrimary)
                            Spacer(minLength: Spacing.sm)
                            ShortcutHint(text: "⌘" + String(action.shortcut).uppercased())
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quickActions." + action.rawValue)
                    .background {
                        MotionKeyboard.shortcut(action.title, KeyEquivalent(action.shortcut)) { choose(action, true) }
                    }
                }
            }
            Text("⌘K opens this. Nothing here uses online AI.")
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
    let shortcut: KeyEquivalent
    /// The ⌘-number shortcut's path (no motion); `action` is the tap's.
    let keyboardAction: () -> Void
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
        .background { MotionKeyboard.shortcut(label, shortcut, action: keyboardAction) }
        .accessibilityLabel(label)
        .accessibilityIdentifier("tab.\(label.lowercased())")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isActive)
    }
}
