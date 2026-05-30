import SwiftUI

struct ProfileView: View {

    @State private var vm = ProfileViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("dealAlertsEnabled") private var dealAlertsEnabled = true
    @AppStorage("mealDigestEnabled") private var mealDigestEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                statsSection
                editSection
                notificationSection
                dangerSection
            }
            .navigationTitle("Profile")
            .alert("Reset Onboarding", isPresented: $vm.showResetAlert) {
                Button("Reset", role: .destructive) {
                    vm.resetOnboarding()
                    hasCompletedOnboarding = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear all your data. Continue?")
            }
        }
        .onAppear { vm.load() }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                Text(vm.initials)
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.brandPrimary)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.profile.name.isEmpty ? "SmartMarket User" : vm.profile.name)
                        .font(.headline)
                    Text(vm.profile.email.isEmpty ? "Vilnius, Lithuania" : vm.profile.email)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var statsSection: some View {
        Section {
            HStack(spacing: 12) {
                MetricTile(title: "BMR", value: "\(Int(vm.profile.bmr))", unit: "kcal")
                MetricTile(title: "Daily Goal", value: "\(vm.profile.dailyCalorieGoal)", unit: "kcal")
                MetricTile(title: "Goal", value: vm.profile.weightGoal.displayName, unit: "")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    private var editSection: some View {
        Section("Edit") {
            NavigationLink {
                EditBodyStatsView(vm: vm)
            } label: { Label("Body Stats", systemImage: "figure") }

            NavigationLink {
                EditDietaryPrefsView(vm: vm)
            } label: { Label("Dietary Preferences", systemImage: "leaf") }

            NavigationLink {
                EditFavoriteFoodsView(vm: vm)
            } label: { Label("Favorite Foods", systemImage: "heart") }
        }
    }

    private var notificationSection: some View {
        Section("Notifications") {
            Toggle("Deal alerts", isOn: $dealAlertsEnabled)
            Toggle("Daily meal plan digest", isOn: $mealDigestEnabled)
        }
        .tint(.brandPrimary)
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                vm.showResetAlert = true
            } label: {
                Label("Reset Onboarding", systemImage: "arrow.counterclockwise")
            }
        } footer: {
            Text("Clears your profile and restarts setup.")
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline)
                .foregroundStyle(Color.brandPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            if !unit.isEmpty {
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.brandPrimary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ProfileView()
}
