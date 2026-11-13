import SwiftUI

struct DietaryPreferencesView: View {

    @Bindable var vm: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                OnboardingProgressBar(currentStep: 4)
                    .padding(.top, 8)

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("What do you eat?")
                        .font(.largeTitle).fontWeight(.bold)
                    Text("Select your preferences. Suggestions can contain mistakes; always check ingredients and allergens before eating.")
                        .font(.subheadline)
                        .foregroundStyle(Color.labelSecondary)
                }
                .padding(.horizontal, 24)

                // Chip grid
                FlowLayout(spacing: 10) {
                    ForEach(DietaryPreference.allCases) { pref in
                        DietChipView(
                            preference: pref,
                            isSelected: vm.selectedPreferences.contains(pref)
                        ) {
                            vm.togglePreference(pref)
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Info note — the parent animates the empty/non-empty swap; the count rolls in place.
                Group {
                    if vm.selectedPreferences.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(Color.labelSecondary)
                            Text("No restrictions selected — we'll include all food types.")
                                .font(.caption)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        .transition(.opacity)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(Color.brandPrimary)
                            Text("\(vm.selectedPreferences.count) preference\(vm.selectedPreferences.count == 1 ? "" : "s") selected. Check every suggestion against your dietary needs.")
                                .font(.caption)
                                .foregroundStyle(Color.brandPrimary)
                                .contentTransition(.numericText())
                                .animation(reduceMotion ? .none : .snappyValue, value: vm.selectedPreferences.count)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 24)
                .animation(reduceMotion ? .none : .snappyValue, value: vm.selectedPreferences.isEmpty)

                // Continue — no minimum required, dietary prefs are optional
                NavigationLink(value: OnboardingStep.notifications) {
                    Label("Next", systemImage: "arrow.right")
                        .primaryButtonLabel()
                }
                .accessibilityIdentifier("onboarding.diet.continue")
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .navigationBarHidden(true)
        .background(Color.surfaceGrouped.ignoresSafeArea())
    }
}


#Preview {
    NavigationStack {
        DietaryPreferencesView(vm: OnboardingViewModel())
    }
}
