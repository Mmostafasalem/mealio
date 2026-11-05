import SwiftUI

struct MainTabView: View {

    @State private var selection = 0

    init() {
        // Hide the system tab bar so our floating one takes over
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView().tag(0).toolbar(.hidden, for: .tabBar)
            NavigationStack { MealPlanView() }.tag(1).toolbar(.hidden, for: .tabBar)
            StoreBrowserView().tag(2).toolbar(.hidden, for: .tabBar)
            StoreMapView().tag(3).toolbar(.hidden, for: .tabBar)
            NavigationStack { ProfileView() }.tag(4).toolbar(.hidden, for: .tabBar)
        }
        // Visibility belongs to each tab's content. UIKit appearance alone can
        // leave an empty floating system bar on iPad.
        // The floating bar IS the bottom safe-area inset, so it reserves exactly
        // its own height — content on every screen clears it automatically.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $selection)
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Floating tab bar

private struct FloatingTabBar: View {

    @Binding var selection: Int
    @Namespace private var pill

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
                    namespace: pill
                ) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                        selection = idx
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .glassCard(radius: 30)
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
    }
}

private struct TabItem: View {

    let icon: String
    let filled: String
    let label: String
    let isActive: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.brandPrimary.opacity(0.13))
                            .frame(width: 46, height: 30)
                            .matchedGeometryEffect(id: "tabPill", in: namespace)
                    }
                    Image(systemName: isActive ? filled : icon)
                        .font(.system(size: 17, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Color.brandPrimary : .secondary)
                        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isActive)
                }
                .frame(width: 46, height: 30)

                Text(label)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.brandPrimary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("tab.\(label.lowercased())")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isActive)
    }
}
