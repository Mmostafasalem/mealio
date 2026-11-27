import SwiftUI

/// Profile's first screen: the person's card (tap to edit name and photo) and
/// a short list of categories. Every setting lives on its category's own page
/// (`ProfileCategoryPages.swift`), so this screen fits on one screen.
struct ProfileView: View {

    @State private var vm = ProfileViewModel()
    @State private var health = HealthService.shared
    @State private var sync = PrivateSyncService.shared
    @State private var themes = ThemeStore.shared
    @State private var reminders = ReminderStore.shared
    @State private var currency = CurrencyStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        EditProfileView(vm: vm)
                    } label: {
                        ProfileCard(vm: vm)
                    }
                    .accessibilityIdentifier("profile.card")
                    .accessibilityHint("Change your name and photo")
                }

                Section {
                    category(.goals, value: "\(vm.profile.dailyCalorieGoal.formatted(.number.grouping(.never))) kcal") {
                        GoalsTargetsPage(vm: vm)
                    }
                    category(.food, value: nil) { FoodDietPage(vm: vm) }
                    category(.currency, value: Money.current.code) { CurrencySettingsView() }
                    category(.features, value: "\(AppState.shared.enabledFeatures.count) of \(AppFeature.allCases.count)") {
                        FeaturesPage()
                    }
                }

                Section {
                    category(.appearance, value: themes.theme.name) { AppearancePage() }
                    category(.voice, value: VoiceLanguage.current.name) { VoiceSettingsView() }
                    category(.notifications, value: reminders.isEnabled ? "On" : "Off") { RemindersView() }
                }

                Section {
                    if AIAccountService.shared.offersOnlineAI {
                        category(.ai, value: nil) { AIAccountPage() }
                    }
                    category(.data, value: sync.isEnabled ? "iCloud on" : nil) { DataICloudPage(vm: vm) }
                    category(.help, value: nil) { HelpLegalPage() }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background { GrainyGradient().ignoresSafeArea() }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { vm.load() }
        .task { await health.refreshReads() }
    }

    private func category<Destination: View>(_ kind: ProfileCategory, value: String?,
                                             @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            ProfileCategoryRow(kind: kind, value: value)
        }
        .accessibilityIdentifier(kind.identifier)
        .accessibilityValue(value ?? "")
    }
}

/// The categories on Profile's first screen, in order.
enum ProfileCategory: String, CaseIterable {
    case goals, food, currency, features, appearance, voice, notifications, ai, data, help

    var title: String {
        switch self {
        case .goals: return "Goals & targets"
        case .food: return "Food & diet"
        case .currency: return "Currency & prices"
        case .features: return "Features"
        case .appearance: return "Appearance"
        case .voice: return "Voice"
        case .notifications: return "Notifications"
        case .ai: return "AI & account"
        case .data: return "Data & iCloud"
        case .help: return "Help & legal"
        }
    }

    var symbol: String {
        switch self {
        case .goals: return "target"
        case .food: return "leaf.fill"
        case .currency: return "banknote.fill"
        case .features: return "square.grid.2x2.fill"
        case .appearance: return "paintpalette.fill"
        case .voice: return "mic.fill"
        case .notifications: return "bell.badge.fill"
        case .ai: return "sparkles"
        case .data: return "icloud.fill"
        case .help: return "questionmark.circle.fill"
        }
    }

    /// Settings-style tile colours, so each row is easy to find at a glance.
    var tint: Color {
        switch self {
        case .goals: return .orange
        case .food: return .green
        case .currency: return Color(red: 0.13, green: 0.6, blue: 0.45)
        case .features: return .indigo
        case .appearance: return .brandPrimary
        case .voice: return .red
        case .notifications: return Color(red: 0.95, green: 0.3, blue: 0.3)
        case .ai: return .purple
        case .data: return .blue
        case .help: return .gray
        }
    }

    /// Kept: `profile.voice` and `profile.reminders` are what UI tests always tapped.
    var identifier: String {
        switch self {
        case .voice: return "profile.voice"
        case .notifications: return "profile.reminders"
        default: return "profile.category." + rawValue
        }
    }
}

private struct ProfileCategoryRow: View {
    let kind: ProfileCategory
    let value: String?
    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 30

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: kind.symbol)
                .font(.system(size: tile * 0.52, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: tile, height: tile)
                .background(kind.tint.gradient, in: RoundedRectangle(cornerRadius: tile * 0.26, style: .continuous))
                .accessibilityHidden(true)
            Text(kind.title)
                .foregroundStyle(Color.labelPrimary)
            Spacer(minLength: Spacing.sm)
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The person's card at the top of Profile: photo or initials, name, goal.
private struct ProfileCard: View {
    let vm: ProfileViewModel

    var body: some View {
        HStack(spacing: Spacing.md) {
            ProfileAvatar(size: 60, name: vm.profile.name)
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.profile.name.isEmpty ? "Add your name" : vm.profile.name)
                    .font(.headline)
                    .foregroundStyle(Color.labelPrimary)
                Text(vm.profile.weightGoal.displayName + " · \(vm.profile.dailyCalorieGoal.formatted(.number.grouping(.never))) kcal a day")
                    .font(.subheadline).foregroundStyle(Color.labelSecondary)
                Text("Edit name and photo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandPrimary)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ProfileView()
}
