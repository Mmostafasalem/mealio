import SwiftUI

struct EditDietaryPrefsView: View {

    @Bindable var vm: ProfileViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select everything that applies. We'll never suggest food that conflicts with your choices.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

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
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle("Dietary Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.save() }
    }
}

#Preview {
    NavigationStack { EditDietaryPrefsView(vm: ProfileViewModel()) }
}
