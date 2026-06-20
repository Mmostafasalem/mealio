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
        .onAppear {
            vm.load()
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    LinearGradient(
                        colors: [Color.brandPrimary, Color.brandDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(vm.initials)
                        .font(.title2).fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                .shadow(color: Color.brandPrimary.opacity(0.4), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.profile.name.isEmpty ? "Mealio User" : vm.profile.name)
                        .font(.headline)
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.brandPrimary)
                        Text(vm.profile.email.isEmpty ? "Vilnius, Lithuania" : vm.profile.email)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var statsSection: some View {
        Section {
            HStack(spacing: 10) {
                MetricTile(title: "BMR", value: "\(Int(vm.profile.bmr))", unit: "kcal", icon: "flame.fill")
                MetricTile(title: "Daily Goal", value: "\(vm.profile.dailyCalorieGoal)", unit: "kcal", icon: "target")
                MetricTile(title: "Goal", value: vm.profile.weightGoal.displayName, unit: "", icon: "arrow.up.forward")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .listRowBackground(Color.clear)
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
    var icon: String = ""

    var body: some View {
        VStack(spacing: 6) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
            }
            Text(value)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.brandPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !unit.isEmpty {
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.brandPrimary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    ProfileView()
}
