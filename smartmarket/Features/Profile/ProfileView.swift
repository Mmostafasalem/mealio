import SwiftUI

struct ProfileView: View {

    @State private var vm = ProfileViewModel()
    @State private var sync = PrivateSyncService.shared
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
                syncSection
                dangerSection
            }
            .navigationTitle("Profile")
            .alert("Delete all Mealio data?", isPresented: $vm.showResetAlert) {
                Button("Delete Data", role: .destructive) {
                    vm.resetOnboarding()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes your profile, food log, cart, budget and meal plans from this iPhone, and your synced shopping data from iCloud. If offline, iCloud deletion will finish when you reconnect to the same Apple Account.")
            }
            .alert("Deletion could not start", isPresented: Binding(get: { vm.deletionError != nil }, set: { if !$0 { vm.deletionError = nil } })) {
                Button("OK", role: .cancel) { vm.deletionError = nil }
            } message: { Text(vm.deletionError ?? "Please try again.") }
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
            Toggle("Favourite item reminders", isOn: $dealAlertsEnabled)
            Toggle("Daily meal plan digest", isOn: $mealDigestEnabled)
        }
        .tint(.brandPrimary)
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                vm.showResetAlert = true
            } label: {
                Label("Delete All Data", systemImage: "trash")
            }
        } footer: {
            Text("Deletes local data and requests deletion of your Mealio iCloud data, then restarts setup.")
        }
    }

    private var syncSection: some View {
        Section {
            Toggle("Sync with iCloud", isOn: Binding(
                get: { sync.isEnabled },
                set: { enabled in Task { await sync.setEnabled(enabled) } }
            ))
            .disabled(sync.isSyncing)
            .accessibilityIdentifier("profile.icloudSync")
            Text(sync.status).font(.footnote).foregroundStyle(.secondary)
            if let date = sync.lastSync {
                Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if sync.isEnabled || sync.deletionPending {
                Button { Task { await sync.sync() } } label: {
                    HStack {
                        Text(sync.deletionPending ? "Retry iCloud Deletion" : "Sync Now")
                        if sync.isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(sync.isSyncing)
                .accessibilityIdentifier("profile.syncNow")
            }
        } header: {
            Text("Data & iCloud")
        } footer: {
            Text("Optional sync uses your private iCloud storage for shopping lists, cart, budget and price corrections. Body measurements, food logs, dietary preferences and nutrition plans stay on this iPhone. No Mealio account is needed. Turning sync off keeps existing iCloud data; use Delete All Data to erase it. AI requests still use our backend and Groq.")
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let unit: String
    var icon: String = ""

    var body: some View {
        VStack(spacing: Spacing.xs) {
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
                .contentTransition(.numericText())
            if !unit.isEmpty {
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .background(Color.brandPrimary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

#Preview {
    ProfileView()
}
