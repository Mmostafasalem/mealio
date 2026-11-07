import SwiftUI

struct MainTabView: View {

    @State private var selection = 0
    @State private var showQuickActions = false
    @State private var pendingAction: MealioQuickAction?
    @State private var activeAction: MealioQuickAction?
    @State private var quickLog = HomeViewModel()
    @State private var showGuideChat = false
    @State private var keyboardVisible = false
    @State private var navigationHeight: CGFloat = 80
    @AppStorage("bowlGuideVisible_v2") private var guideVisible = true

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
            // Reserve the small companion's footprint so it never covers the
            // last row, map controls or a screen's bottom action.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if guideVisible && !keyboardVisible { Color.clear.frame(height: 84) }
            }
            // A sibling reserves real layout space on every tab, including iPad.
            FloatingTabBar(selection: $selection) { if activeAction == nil { showQuickActions = true } }
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: NavigationHeightKey.self, value: geometry.size.height)
                })
        }
        .onPreferenceChange(NavigationHeightKey.self) { navigationHeight = $0 }
        // Keep the companion outside TabView's UIKit hierarchy. In particular,
        // MapKit's gesture surface must not intercept the floating button.
        .overlay(alignment: .bottom) {
            if !keyboardVisible {
                GeometryReader { geometry in
                    FloatingBowlGuide(selectedTab: $selection, availableHeight: geometry.size.height - navigationHeight, choose: followGuide)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, navigationHeight)
                }
                .zIndex(10)
            }
        }
        .background(Color.surfaceGrouped)
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .sheet(isPresented: $showGuideChat) { AgentChatSheet(vm: quickLog) }
        .sheet(isPresented: $showQuickActions, onDismiss: {
            activeAction = pendingAction
            pendingAction = nil
        }) {
            QuickActionsSheet { action in
                if let tab = action.tab { selection = tab }
                else { pendingAction = action }
                showQuickActions = false
            }
        }
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
    let onSearch: () -> Void
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private let items: [(icon: String, filled: String, label: String)] = [
        ("house",               "house.fill",               "Home"),
        ("fork.knife.circle",   "fork.knife.circle.fill",   "Meals"),
        ("storefront",          "storefront.fill",          "Shop"),
        ("map",                 "map.fill",                 "Map"),
        ("person.crop.circle",  "person.crop.circle.fill",  "Profile"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                TabItem(
                    icon:      item.icon,
                    filled:    item.filled,
                    label:     item.label,
                    isActive:  selection == idx,
                    namespace: pill,
                    shortcut: KeyEquivalent(Character(String(idx + 1)))
                ) {
                    withAnimation(reduceMotion ? .none : .snappyValue) {
                        selection = idx
                    }
                }
            }
            Button(action: onSearch) {
                VStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.medium)).dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(height: 30)
                    if !typeSize.isAccessibilitySize { Text("Search").font(.caption2) }
                }
                .foregroundStyle(Color.labelSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)
            .accessibilityLabel("Quick Actions")
            .accessibilityHint("Find a screen or action. Keyboard shortcut Command K.")
            .accessibilityIdentifier("navigation.quickActions")
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
    let namespace: Namespace.ID
    let shortcut: KeyEquivalent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.brandLight)
                            .frame(width: 46, height: 30)
                            .matchedGeometryEffect(id: "tabPill", in: namespace)
                    }
                    Image(systemName: isActive ? filled : icon)
                        .font(.body.weight(isActive ? .semibold : .regular))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(isActive ? Color.brandPrimary : Color.labelSecondary)
                        .animation(reduceMotion ? .none : .snappyValue, value: isActive)
                }
                .frame(width: 46, height: 30)

                if !typeSize.isAccessibilitySize {
                    Text(label)
                        .font(.caption2.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Color.brandPrimary : Color.labelSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
        .accessibilityLabel(label)
        .accessibilityIdentifier("tab.\(label.lowercased())")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isActive)
    }
}
