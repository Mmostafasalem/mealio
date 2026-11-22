import SwiftUI

/// Root of the onboarding NavigationStack.
/// Every screen shares a single OnboardingViewModel. The first asks name, age and
/// gender together, the second what the person wants Nourlo for; the rest ask
/// one question each, and only the ones the chosen features need
/// (`FeatureLayout.onboardingSteps`).
struct OnboardingFlow: View {

    @State private var vm = OnboardingViewModel()

    var body: some View {
        NavigationStack(path: $vm.path) {
            NameStepView(vm: vm)
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .name:          NameStepView(vm: vm)
                    case .features:      FeatureChoiceView(vm: vm)
                    case .height:        HeightStepView(vm: vm)
                    case .weight:        WeightStepView(vm: vm)
                    case .activity:      ActivityStepView(vm: vm)
                    case .goal:          GoalSelectionView(vm: vm)
                    case .pace:          PaceSelectionView(vm: vm)
                    case .diet:          DietaryPreferencesView(vm: vm)
                    case .favorites:     FavoriteFoodsView(vm: vm)
                    case .week:          WeekStepView(vm: vm)
                    case .alerts:        AlertsStepView(vm: vm)
                    }
                }
        }
        .tint(.brandPrimary)
    }
}

/// Screens in the order they can appear. `name` (name, age and gender) is the
/// stack's root. Which of the others appear, and their numbers ("3 / 10"),
/// come from `OnboardingViewModel.steps`.
enum OnboardingStep: Int, Hashable, CaseIterable {
    case name, features, height, weight, activity
    case goal, pace
    case diet, favorites
    case week, alerts
}
