import SwiftUI

struct DietaryPreferencesView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                OnboardingProgressBar(currentStep: 4)
                    .padding(.top, 8)

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("What do you eat?")
                        .font(.largeTitle).fontWeight(.bold)
                    Text("Select everything that applies. We'll never suggest food that conflicts with your choices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

                // Other allergies
                VStack(alignment: .leading, spacing: 8) {
                    Label("Other allergies or restrictions", systemImage: "square.and.pencil")
                        .font(.subheadline).fontWeight(.medium)
                    TextField("e.g. sesame, mustard, sulfites...", text: $vm.otherAllergies)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)

                // Info note
                if vm.selectedPreferences.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("No restrictions selected — we'll include all food types.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(Color.brandPrimary)
                        Text("\(vm.selectedPreferences.count) restriction\(vm.selectedPreferences.count == 1 ? "" : "s") selected. We've got you covered.")
                            .font(.caption)
                            .foregroundStyle(Color.brandPrimary)
                    }
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                    .animation(.easeIn, value: vm.selectedPreferences.count)
                }

                // Continue — no minimum required, dietary prefs are optional
                NavigationLink(value: OnboardingStep.notifications) {
                    Label("Next", systemImage: "arrow.right")
                        .primaryButtonLabel()
                }
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
