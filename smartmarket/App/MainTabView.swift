import SwiftUI

/// Root tab bar shown after onboarding is complete.
struct MainTabView: View {

    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            NavigationStack { MealPlanView() }
                .tabItem { Label("Meal Plan", systemImage: "fork.knife") }
                .tag(1)

            GroceryListView(selectedTab: $selection)
                .tabItem { Label("Groceries", systemImage: "cart.fill") }
                .tag(2)

            NavigationStack { StoreMapView() }
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(3)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(4)
        }
        .tint(.brandPrimary)
    }
}

#Preview {
    MainTabView()
}
