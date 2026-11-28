import SwiftUI

/// Profile › Features: the same choice as onboarding's "What do you want
/// Nourlo for?". Changes apply at once (tabs, Home cards, quests, quick
/// actions). The last feature that is on can't be turned off.
struct FeaturesSection: View {
    private var appState: AppState { AppState.shared }

    var body: some View {
        Section {
            ForEach(AppFeature.allCases) { feature in
                let isOn = appState.isEnabled(feature)
                let isLast = isOn && appState.enabledFeatures.count == 1
                Toggle(isOn: Binding(get: { appState.isEnabled(feature) },
                                     set: { appState.setFeature(feature, enabled: $0) })) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.name)
                            Text(feature.detail)
                                .font(.caption)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    } icon: {
                        Image(systemName: feature.symbol)
                    }
                }
                .toggleStyle(.spring)
                .disabled(isLast)
                .accessibilityHint(isLast ? "At least one feature stays on." : "")
                .accessibilityIdentifier("profile.feature." + feature.rawValue)
            }
        } header: {
            Text("Features")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var text = "Choose what you use Nourlo for. Turned-off parts leave the tab bar, Home and quick actions; your data stays."
        // Groceries alone skips the body questions in onboarding.
        if !FeatureLayout.asksBodyStats(appState.enabledFeatures) {
            text += " Tracking, meals and workouts use your body stats: check them under Edit when you turn one on."
        }
        return text
    }
}
