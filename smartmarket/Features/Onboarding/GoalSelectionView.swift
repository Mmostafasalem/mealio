import SwiftUI

// MARK: - Goal

struct GoalSelectionView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(vm: vm, step: .goal, title: "What's your goal?",
                           subtitle: "Your body burns about \(vm.liveTDEE.formatted()) kcal a day.") {
            VStack(spacing: Spacing.md) {
                OnboardingOptionList {
                    ForEach(WeightGoal.allCases) { goal in
                        OnboardingOptionRow(symbol: goal.sfSymbol, title: goal.displayName,
                                            subtitle: goal.description,
                                            trailing: "\(calorieTarget(for: goal).formatted()) kcal",
                                            isSelected: vm.weightGoal == goal) { vm.weightGoal = goal }
                    }
                }
                Spacer(minLength: 0)
                DailyTargetCard(calories: vm.liveDailyGoal)
            }
        } footer: {
            OnboardingNextButton(vm: vm, next: vm.weightGoal == .lose ? .pace : .diet,
                                 identifier: "onboarding.goal.continue")
        }
    }

    private func calorieTarget(for goal: WeightGoal) -> Int {
        let tdee = Double(vm.liveTDEE)
        switch goal {
        case .maintain: return vm.liveTDEE
        case .lose, .gain:
            return BMRCalculator.dailyGoal(tdee: tdee, goal: goal, pace: vm.lossPace, gender: vm.gender)
        }
    }
}

// MARK: - Pace (only when losing weight)

struct PaceSelectionView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(vm: vm, step: .pace, title: "How fast do you want to lose?") {
            VStack(spacing: Spacing.md) {
                OnboardingOptionList {
                    ForEach(LossPace.allCases) { pace in
                        OnboardingOptionRow(symbol: symbol(for: pace), title: pace.displayName,
                                            trailing: "−\(pace.dailyDeficit) kcal",
                                            isSelected: vm.lossPace == pace) { vm.lossPace = pace }
                    }
                }
                if vm.isBelowSafeFloor {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.brandDanger)
                        Text("This target is near the minimum safe calories. We've capped it for your safety.")
                            .font(.footnote)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.brandLight, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .transition(.opacity)
                }
                Spacer(minLength: 0)
                DailyTargetCard(calories: vm.liveDailyGoal)
            }
            .animation(.snappyValue, value: vm.isBelowSafeFloor)
        } footer: {
            OnboardingNextButton(vm: vm, next: .diet, identifier: "onboarding.pace.continue")
        }
    }

    private func symbol(for pace: LossPace) -> String {
        switch pace {
        case .slow:   return "tortoise.fill"
        case .medium: return "figure.walk"
        case .fast:   return "hare.fill"
        }
    }
}

// MARK: - Daily target

private struct DailyTargetCard: View {
    let calories: Int

    var body: some View {
        HStack {
            Text("Your daily target")
                .font(.subheadline)
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            Text("\(calories.formatted()) kcal")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.labelPrimary)
                .contentTransition(.numericText())
                .animation(.snappyValue, value: calories)
        }
        .padding(Spacing.lg)
        .background(Color.brandLight, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Goal") { NavigationStack { GoalSelectionView(vm: OnboardingViewModel()) } }
#Preview("Pace") { NavigationStack { PaceSelectionView(vm: OnboardingViewModel()) } }
