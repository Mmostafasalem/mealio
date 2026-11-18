import SwiftUI

// MARK: - Goal

struct GoalSelectionView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(vm: vm, step: .goal, title: "What's your goal?",
                           subtitle: "Your body burns about \(vm.liveTDEE.formatted()) kcal a day.") {
            VStack(spacing: Spacing.md) {
                OnboardingOptionList {
                    ForEach(vm.availableGoals) { goal in
                        OnboardingOptionRow(symbol: goal.sfSymbol, title: goal.displayName,
                                            subtitle: goal.description,
                                            trailing: "\(calorieTarget(for: goal).formatted()) kcal",
                                            isSelected: vm.weightGoal == goal) { vm.weightGoal = goal }
                    }
                }
                if !vm.allowsWeightLoss { MinorGoalNote() }
                Spacer(minLength: 0)
                DailyTargetCard(calories: vm.liveDailyGoal)
            }
            .onAppear { vm.normalizeGoalForAge() }
        } footer: {
            OnboardingNextButton(vm: vm, next: vm.weightGoal == .lose ? .pace : .diet,
                                 identifier: "onboarding.goal.continue")
        }
    }

    private func calorieTarget(for goal: WeightGoal) -> Int {
        vm.liveTargets(goal: goal).dailyGoal
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
                        OnboardingOptionRow(symbol: PaceStyle.symbol(for: pace), title: pace.displayName,
                                            subtitle: vm.isCappedBySafetyFloor(pace) ? "Kept from going too low" : nil,
                                            trailing: PaceStyle.deficitText(vm.effectiveDeficit(for: pace)),
                                            isSelected: vm.lossPace == pace) { vm.lossPace = pace }
                    }
                }
                if vm.isBelowSafeFloor {
                    SafeFloorNote()
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
}

// MARK: - Shared pieces (also used by Profile's goal editor)

enum PaceStyle {
    static func symbol(for pace: LossPace) -> String {
        switch pace {
        case .slow:   return "tortoise.fill"
        case .medium: return "figure.walk"
        case .fast:   return "hare.fill"
        }
    }

    /// "−550 kcal", or "No deficit" when the floor leaves none.
    static func deficitText(_ deficit: Int) -> String {
        deficit > 0 ? "−\(deficit) kcal" : "No deficit"
    }
}

/// Shown when the selected pace would go below the minimum safe calories.
struct SafeFloorNote: View {
    var body: some View {
        NoteCard(symbol: "exclamationmark.triangle.fill", tint: .brandDanger,
                 text: "This pace would go below the minimum safe calories, so we've capped your daily target.")
    }
}

/// Shown instead of the weight-loss option to people under 18.
struct MinorGoalNote: View {
    var body: some View {
        NoteCard(symbol: "stethoscope", tint: .brandPrimary,
                 text: "Under 18, Nourlo doesn't set weight-loss targets. Talk to a doctor about any weight goals.")
    }
}

private struct NoteCard: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandLight, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .accessibilityElement(children: .combine)
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
