import SwiftUI

struct DietaryPreferencesView: View {

    @Bindable var vm: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingScaffold(vm: vm, step: .diet, title: "What do you eat?",
                           subtitle: "Pick any that apply. Suggestions can contain mistakes; always check ingredients and allergens before eating.") {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ViewThatFits(in: .vertical) {
                    chips
                    ScrollView { chips }.scrollIndicators(.hidden)
                }
                note
                    .animation(reduceMotion ? .none : .snappyValue, value: vm.selectedPreferences.count)
            }
        } footer: {
            // No minimum required — dietary preferences are optional.
            OnboardingNextButton(vm: vm, next: .notifications, identifier: "onboarding.diet.continue")
        }
    }

    private var chips: some View {
        FlowLayout(spacing: 10) {
            ForEach(DietaryPreference.allCases) { pref in
                DietChipView(preference: pref, isSelected: vm.selectedPreferences.contains(pref)) {
                    vm.togglePreference(pref)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var note: some View {
        let count = vm.selectedPreferences.count
        return HStack(spacing: Spacing.sm) {
            Image(systemName: count == 0 ? "info.circle" : "checkmark.shield.fill")
            Text(count == 0
                 ? "Nothing selected — we'll include all food types."
                 : "\(count) selected. Check every suggestion against your dietary needs.")
                .contentTransition(.numericText())
        }
        .font(.footnote)
        .foregroundStyle(count == 0 ? Color.labelSecondary : Color.labelPrimary)
    }
}

#Preview {
    NavigationStack { DietaryPreferencesView(vm: OnboardingViewModel()) }
}
