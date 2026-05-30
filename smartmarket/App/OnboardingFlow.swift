import SwiftUI

/// Root of the onboarding NavigationStack.
/// All 4 screens share a single OnboardingViewModel injected as environment object.
struct OnboardingFlow: View {

    @State private var vm = OnboardingViewModel()

    var body: some View {
        NavigationStack(path: $vm.path) {
            BMRInputView(vm: vm)
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .location:      LocationPermissionView(vm: vm)
                    case .goal:          GoalSelectionView(vm: vm)
                    case .diet:          DietaryPreferencesView(vm: vm)
                    case .notifications: NotificationPermissionView(vm: vm)
                    case .favorites:     FavoriteFoodsView(vm: vm)
                    }
                }
        }
        .tint(.brandPrimary)
    }
}

enum OnboardingStep: Hashable {
    case location
    case goal
    case diet
    case notifications
    case favorites
}
