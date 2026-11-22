import SwiftUI

// MARK: - What do you want Nourlo for?

/// The second screen: which parts of Nourlo the person wants. Several can be
/// picked (all are on to start), at least one is needed. The choice decides
/// the later questions and, once set up, the tabs, Home cards, quests and quick
/// actions. It can be changed any time in Profile › Features.
struct FeatureChoiceView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(vm: vm, step: .features, title: "What do you want Nourlo for?",
                           subtitle: "Pick one or more. You can change this later in Profile.") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                OnboardingOptionList {
                    ForEach(AppFeature.allCases) { feature in
                        OnboardingOptionRow(symbol: feature.symbol, title: feature.choiceTitle,
                                            subtitle: feature.detail, multiSelect: true,
                                            isSelected: vm.features.contains(feature)) {
                            vm.toggleFeature(feature)
                        }
                        .accessibilityIdentifier("onboarding.feature." + feature.rawValue)
                    }
                }
                if !vm.canContinueFromFeatures {
                    Label("Choose at least one to continue.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Color.labelSecondary)
                        .transition(.opacity)
                }
            }
            .animation(.snappyValue, value: vm.canContinueFromFeatures)
        } footer: {
            OnboardingNextButton(vm: vm, from: .features, identifier: "onboarding.features.continue")
                .disabled(!vm.canContinueFromFeatures)
                .opacity(vm.canContinueFromFeatures ? 1 : 0.5)
        }
    }
}

#Preview { NavigationStack { FeatureChoiceView(vm: OnboardingViewModel()) } }
