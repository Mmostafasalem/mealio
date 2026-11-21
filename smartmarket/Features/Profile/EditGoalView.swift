import SwiftUI

/// Change the weight goal (and the loss pace) after onboarding. Each choice
/// saves at once and recomputes the daily targets the same way onboarding does.
struct EditGoalView: View {

    @Bindable var vm: ProfileViewModel

    var body: some View {
        List {
            Section {
                ForEach(vm.availableGoals) { goal in
                    choiceRow(symbol: goal.sfSymbol, title: goal.displayName, subtitle: goal.description,
                              trailing: "\(vm.targets(goal: goal).dailyGoal.formatted(.number.grouping(.never))) kcal",
                              isSelected: vm.profile.weightGoal == goal) { vm.setGoal(goal) }
                }
            } header: {
                Text("Goal")
            } footer: {
                if !vm.allowsWeightLoss { MinorGoalNote().padding(.top, Spacing.sm) }
            }

            if vm.profile.weightGoal == .lose {
                Section {
                    ForEach(LossPace.allCases) { pace in
                        choiceRow(symbol: PaceStyle.symbol(for: pace), title: pace.displayName,
                                  subtitle: vm.isCappedBySafetyFloor(pace) ? "Kept from going too low" : nil,
                                  trailing: PaceStyle.deficitText(vm.effectiveDeficit(for: pace)),
                                  isSelected: vm.profile.lossPace == pace) { vm.setPace(pace) }
                    }
                } header: {
                    Text("Pace")
                } footer: {
                    if vm.isCappedBySafetyFloor(vm.profile.lossPace) { SafeFloorNote().padding(.top, Spacing.sm) }
                }
            }

            Section {
                HStack {
                    Text("Your daily target")
                    Spacer()
                    Text("\(vm.profile.dailyCalorieGoal.formatted(.number.grouping(.never))) kcal" as String)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(Color.brandPrimary)
                        .contentTransition(.numericText())
                        .animation(.snappyValue, value: vm.profile.dailyCalorieGoal)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Goal")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappyValue, value: vm.profile.weightGoal)
    }

    private func choiceRow(symbol: String, title: String, subtitle: String?, trailing: String,
                           isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color.labelPrimary)
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(Color.labelSecondary)
                    }
                }
                Spacer(minLength: Spacing.sm)
                Text(trailing)
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.labelSecondary)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.dullPink : Color(.tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack { EditGoalView(vm: ProfileViewModel()) }
}
