import SwiftUI

struct ProfileView: View {

    @State private var vm = ProfileViewModel()
    @State private var sync = PrivateSyncService.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("dealAlertsEnabled") private var dealAlertsEnabled = true
    @AppStorage("mealDigestEnabled") private var mealDigestEnabled = true
    @AppStorage("aiSharingConsent_v1") private var aiSharingConsent = false
    @AppStorage("ownerAISharingConsent_v1") private var ownerAISharingConsent = false
    @AppStorage("bowlGuideVisible_v2") private var bowlGuideVisible = true
    @AppStorage(Constants.Storage.appearanceOverride) private var appearanceOverride = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                statsSection
                editSection
                appearanceSection
                Section {
                    Toggle("Floating bowl guide", isOn: $bowlGuideVisible)
                        .toggleStyle(.spring)
                        .accessibilityIdentifier("profile.bowlGuide")
                } header: {
                    Text("Your companion")
                } footer: {
                    Text("Local tips and a quick tour, available on every main screen. Hold the bowl to move it or replay the tour.")
                }
                AIAccountSection()
                syncSection
                privacySection
                dangerSection
            }
            .scrollContentBackground(.hidden)
            .background { GrainyGradient().ignoresSafeArea() }
            .navigationTitle("Profile")
            .alert("Delete all Nourlo data?", isPresented: $vm.showResetAlert) {
                Button("Delete Data", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes your online AI account, profile, food log, cart, budget and meal plans from this iPhone, and your synced shopping data from iCloud. Deleting an AI account requires a connection and valid sign-in; if that fails you can still erase this iPhone. If offline, iCloud deletion will finish when you reconnect to the same Apple Account.")
            }
            .alert("Online AI account not deleted", isPresented: Binding(get: { vm.serverDeletionFailure != nil }, set: { if !$0 { vm.serverDeletionFailure = nil } })) {
                Button("Erase This iPhone Only", role: .destructive) {
                    vm.serverDeletionFailure = nil
                    Task { await vm.resetOnboarding(localOnly: true) }
                }
                Button("Cancel", role: .cancel) { vm.serverDeletionFailure = nil }
            } message: { Text(vm.serverDeletionFailure ?? "") }
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
                    Color.dullPink
                    Text(vm.initials)
                        .font(.title2).fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.25)
                        .padding(6)
                        .foregroundStyle(Color.onAccent)
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())


                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.profile.name.isEmpty ? "Nourlo User" : vm.profile.name)
                        .font(.headline)
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.brandPrimary)
                        Text(vm.profile.email.isEmpty ? "Vilnius, Lithuania" : vm.profile.email)
                            .font(.caption).foregroundStyle(Color.labelSecondary)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var statsSection: some View {
        Section("Daily targets") {
            metricTiles
        }
    }

    @ViewBuilder private var metricTiles: some View {
        MetricTile(title: "BMR", value: "\(Int(vm.profile.bmr))", unit: "kcal", icon: "flame.fill")
        MetricTile(title: "Daily Goal", value: "\(vm.profile.dailyCalorieGoal)", unit: "kcal", icon: "target")
        MetricTile(title: "Goal", value: vm.profile.weightGoal.displayName, unit: "", icon: "arrow.up.forward")
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

            NavigationLink {
                RemindersView()
            } label: { Label("Reminders", systemImage: "bell") }
            .accessibilityIdentifier("profile.reminders")
        }
    }

    /// Light when overridden to light, or when following an iPhone that is in light mode.
    private var lightAppearance: Binding<Bool> {
        Binding(
            get: { appearanceOverride == "light" || (appearanceOverride.isEmpty && colorScheme == .light) },
            set: { appearanceOverride = $0 ? "light" : "dark" }
        )
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                PullCordToggle(isOn: lightAppearance)
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .premiumCard()
                    .accessibilityIdentifier("profile.appearanceCord")
                Text("Pull the cord to switch between light and dark. Nourlo follows your iPhone setting until you pull it.")
                    .font(.footnote).foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !appearanceOverride.isEmpty {
                    Button("Follow iPhone setting") { appearanceOverride = "" }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("profile.followSystemAppearance")
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private var dangerSection: some View {
        Section {
            // Hold to delete; a tap, VoiceOver or Switch Control opens the confirmation alert instead.
            HoldToConfirmButton(
                title: "Hold to delete all data",
                holdingTitle: "Keep holding to delete",
                doneTitle: "Deleting all data",
                tint: .brandDanger,
                systemImage: "trash",
                accessibilityName: "Delete All Data",
                accessibilityActionName: "Delete all data",
                fallback: { vm.showResetAlert = true }
            ) {
                deleteAllData()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Spacing.xs, leading: 0, bottom: Spacing.xs, trailing: 0))
        } footer: {
            Text("Deletes your online AI account, clears local data and requests deletion of your Nourlo iCloud data, then restarts setup.")
        }
    }

    /// What the "Delete Data" confirmation runs; the hold button calls the same.
    private func deleteAllData() {
        Task { await vm.resetOnboarding() }
    }

    private var syncSection: some View {
        Section {
            Toggle("Sync with iCloud", isOn: Binding(
                get: { sync.isEnabled },
                set: { enabled in Task { await sync.setEnabled(enabled) } }
            ))
            .toggleStyle(.spring)
            .disabled(sync.isSyncing || !sync.isAvailable)
            .accessibilityIdentifier("profile.icloudSync")
            Text(sync.status).font(.footnote).foregroundStyle(Color.labelSecondary)
            if let date = sync.lastSync {
                Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
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
            Text("Optional sync uses your private iCloud storage for shopping lists, cart, budget and price corrections. Body measurements, food logs, dietary preferences and nutrition plans stay on this iPhone. No Nourlo account is needed for shopping sync. Turning sync off keeps existing iCloud data; use Delete All Data to erase it. AI requests still use our backend and Groq.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Allow online AI suggestions", isOn: OwnerAITestConfiguration.current == nil ? $aiSharingConsent : $ownerAISharingConsent)
                .toggleStyle(.spring)
                .accessibilityIdentifier("profile.aiConsent")
            NavigationLink {
                LegalDocumentView(resource: "Privacy", title: "Privacy Policy")
            } label: { Label("Privacy Policy", systemImage: "hand.raised") }
            .accessibilityIdentifier("profile.privacy")
            NavigationLink {
                LegalDocumentView(resource: "Support", title: "Help & Support")
            } label: { Label("Help & Support", systemImage: "questionmark.circle") }
            .accessibilityIdentifier("profile.support")
            Link(destination: Constants.Support.mailURL) {
                Label("Email Support", systemImage: "envelope")
            }
            .accessibilityHint("Opens Mail to write to \(Constants.Support.email)")
            .accessibilityIdentifier("profile.emailSupport")
            MorphPopover(footnote: "Opens Mail to \(Constants.Support.email). Nothing is sent until you tap Send there.") { message in
                await SupportMail.send(message)
            }
            .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.md, bottom: Spacing.sm, trailing: Spacing.md))
        } header: {
            Text("Privacy & Help")
        } footer: {
            if OwnerAITestConfiguration.current != nil {
                Text("In this private test build, AI requests send relevant body measurements, goals, dietary preferences, shopping items, owned food quantities, remaining daily targets and messages \(OwnerAITestConfiguration.current?.transportDescription ?? "to your Mac") to the AI running on your Mac. Keep the Mac service running. Turn sharing off to stop future requests. No personal daily allowance is provided by this testing connection.")
            } else {
                Text("When enabled, online AI requests send relevant body measurements, goals, dietary preferences, shopping items, owned food quantities, remaining daily targets and messages through our backend to Groq. Turn this off to stop future AI requests. Local tracking and local suggestions remain available. Read the Privacy Policy before enabling.")
            }
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let unit: String
    var icon: String = ""

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Spacing.md))
        layout {
            Label(title, systemImage: icon).font(.body)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Spacing.sm) }
            Text(unit.isEmpty ? value : "\(value) \(unit)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

#Preview {
    ProfileView()
}
