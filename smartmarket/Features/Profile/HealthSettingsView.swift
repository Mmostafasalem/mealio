import SwiftUI

/// Apple Health: one switch, what is shared and read, the last sync and, when
/// Health has a newer weight, an offer to use it. Reached from Profile and
/// from the activity card on Home.
struct HealthSettingsView: View {

    @State private var health = HealthService.shared
    /// Profile passes its own view model so a weight taken from Health shows
    /// there at once; from Home this screen loads its own.
    private let externalVM: ProfileViewModel?
    @State private var ownVM = ProfileViewModel()
    @AppStorage(Constants.Storage.weightUnit) private var weightUnit: WeightUnit = .kg
    @Environment(\.openURL) private var openURL

    init(vm: ProfileViewModel? = nil) {
        externalVM = vm
    }

    private var vm: ProfileViewModel { externalVM ?? ownVM }

    private var toggle: Binding<Bool> {
        Binding(get: { health.isEnabled },
                set: { on in Task { await health.setEnabled(on) } })
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: toggle) {
                    Label("Apple Health", systemImage: "heart.text.square")
                }
                .toggleStyle(.spring)
                .disabled(!health.isAvailable || health.isRequesting)
                .accessibilityIdentifier("health.toggle")
                .accessibilityHint("Saves food and tracked workouts to Apple Health and reads your weight, steps and active energy")

                Label(health.statusText, systemImage: statusSymbol)
                    .font(.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("health.status")

                if health.access == .needsPermission {
                    Button("Ask for access") { Task { await health.requestAccessAgain() } }
                        .disabled(health.isRequesting)
                }
                if health.access == .denied {
                    Button("Open the Health app") {
                        if let url = URL(string: "x-apple-health://") { openURL(url) }
                    }
                }
            } footer: {
                Text("Turning this off stops syncing. Data already in Apple Health stays there; you can review or delete it in the Health app.")
            }

            if health.isEnabled, let suggestion = health.weightSuggestion(profileKg: vm.profile.weight) {
                weightSection(suggestion)
            }

            Section {
                infoRow("Food energy, protein, carbs and fat for each food you log", symbol: "fork.knife")
                infoRow("Workouts you track with Start workout, with their real start and finish time", symbol: "figure.strengthtraining.traditional")
                infoRow("Active energy for those workouts, estimated from the plan and how long you trained", symbol: "flame")
            } header: {
                Text("Saved to Apple Health")
            } footer: {
                Text("Workouts you only mark as done stay in Nourlo and aren't saved to Apple Health.")
            }

            Section {
                infoRow("Your latest weight, only offered as a suggestion", symbol: "scalemass")
                infoRow("Today's steps and active energy, shown on Home", symbol: "figure.walk")
            } header: {
                Text("Read from Apple Health")
            } footer: {
                Text("If steps or active energy stay at zero, allow them for Nourlo in the Health app.")
            }

            if health.isEnabled {
                syncSection
            }

            Section {
                Text("Health data stays on this iPhone and in Apple Health and isn't sent anywhere. If you use your Health weight in your profile, it's used like a weight you type in, including for AI meal plans if you've allowed online AI.")
                    .font(.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .scrollContentBackground(.hidden)
        .background { GrainyGradient().ignoresSafeArea() }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if externalVM == nil { ownVM.load() }
        }
        .task { await health.refreshReads() }
    }

    private var statusSymbol: String {
        switch health.access {
        case .ready: return "checkmark.circle"
        case .off: return "circle"
        default: return "exclamationmark.triangle"
        }
    }

    private func weightSection(_ kilograms: Double) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Health says \(WeightRuler.text(kilograms, weightUnit)). Use it?")
                    .font(.body)
                    .foregroundStyle(Color.labelPrimary)
                Text("Your profile says \(WeightRuler.text(vm.profile.weight, weightUnit)). Using Health's weight updates your daily targets.")
                    .font(.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = health.latestWeightDate {
                    Text("Measured \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
            .padding(.vertical, Spacing.xs)
            .accessibilityElement(children: .combine)

            Button("Use \(WeightRuler.text(kilograms, weightUnit))") {
                vm.applyHealthWeight(kilograms)
            }
            .font(.body.weight(.semibold))
            .accessibilityIdentifier("health.useWeight")
        } header: {
            Text("Weight")
        }
    }

    private var syncSection: some View {
        Section("Last sync") {
            HStack {
                Text(health.lastSyncMessage ?? "Not synced yet.")
                    .font(.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if health.isSyncing {
                    Spacer()
                    ProgressView().accessibilityLabel("Syncing")
                }
            }
            if let date = health.lastSync {
                Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Color.labelSecondary)
            }
            Button("Sync now") { Task { await health.syncNow() } }
                .disabled(health.isSyncing || health.access == .needsPermission)
                .accessibilityIdentifier("health.syncNow")
        }
    }

    private func infoRow(_ text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(Color.labelPrimary)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.labelPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack { HealthSettingsView() }
}
