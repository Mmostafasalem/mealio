import SwiftUI

/// Root of the onboarding NavigationStack.
/// Every screen shares a single OnboardingViewModel and asks one question.
struct OnboardingFlow: View {

    @State private var vm = OnboardingViewModel()

    var body: some View {
        NavigationStack(path: $vm.path) {
            NameStepView(vm: vm)
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .name:          NameStepView(vm: vm)
                    case .gender:        GenderStepView(vm: vm)
                    case .age:           AgeStepView(vm: vm)
                    case .height:        HeightStepView(vm: vm)
                    case .weight:        WeightStepView(vm: vm)
                    case .activity:      ActivityStepView(vm: vm)
                    case .goal:          GoalSelectionView(vm: vm)
                    case .pace:          PaceSelectionView(vm: vm)
                    case .diet:          DietaryPreferencesView(vm: vm)
                    case .notifications: NotificationPermissionView(vm: vm)
                    case .favorites:     FavoriteFoodsView(vm: vm)
                    }
                }
        }
        .tint(.brandPrimary)
    }
}

/// Screens in the order they appear. `name` is the stack's root.
enum OnboardingStep: Int, Hashable, CaseIterable {
    case name, gender, age, height, weight, activity
    case goal, pace
    case diet, notifications, favorites

    /// `pace` only appears when losing weight, so it shares the goal's number.
    static let total = 10

    /// 1-based position shown as "3 / 11".
    var number: Int { rawValue < OnboardingStep.pace.rawValue ? rawValue + 1 : rawValue }

    var progress: CGFloat { CGFloat(number) / CGFloat(Self.total) }
}
