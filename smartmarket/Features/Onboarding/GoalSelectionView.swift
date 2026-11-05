import SwiftUI

struct GoalSelectionView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                OnboardingProgressBar(currentStep: 3)
                    .padding(.top, 8)

                // Header with BMR result
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.brandPrimary.opacity(0.12)).frame(width: 40, height: 40)
                            Image(systemName: "flame.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.brandPrimary)
                        }
                        Text("Step 3 of 5")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(Color.brandPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.brandPrimary.opacity(0.1), in: Capsule())
                    }
                    Text("Your base burn")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("\(vm.liveBMR) kcal / day")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.brandPrimary)
                    Text("What's your goal?")
                        .font(.title2).fontWeight(.bold)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 24)

                // Goal cards
                VStack(spacing: 12) {
                    ForEach(WeightGoal.allCases) { goal in
                        GoalCard(
                            goal: goal,
                            isSelected: vm.weightGoal == goal,
                            calorieTarget: calorieTarget(for: goal)
                        ) {
                            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                                vm.weightGoal = goal
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Pace selector (only when Lose is selected)
                if vm.weightGoal == .lose {
                    PaceSelectorSection(pace: $vm.lossPace, tdee: vm.liveTDEE)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 24)
                }

                // Safety warning
                if vm.isBelowSafeFloor {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.brandAmber)
                        Text("This target is near the minimum safe calories. We've capped it for your safety.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.brandAmberLight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24)
                }

                // Daily goal summary
                GoalSummaryCard(
                    goal: vm.weightGoal,
                    dailyCalories: vm.liveDailyGoal,
                    tdee: vm.liveTDEE
                )
                .padding(.horizontal, 24)

                // Continue
                NavigationLink(value: OnboardingStep.diet) {
                    Label("Set My Goal", systemImage: "checkmark")
                        .primaryButtonLabel()
                }
                .accessibilityIdentifier("onboarding.goal.continue")
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .navigationBarHidden(true)
        .background(Color.surfaceGrouped.ignoresSafeArea())
    }

    private func calorieTarget(for goal: WeightGoal) -> Int {
        let tdee = Double(vm.liveTDEE)
        switch goal {
        case .maintain: return Int(tdee.rounded())
        case .lose:     return BMRCalculator.dailyGoal(tdee: tdee, goal: .lose, pace: vm.lossPace, gender: vm.gender)
        case .gain:     return Int((tdee + 300).rounded())
        }
    }
}

// MARK: - Goal card

private struct GoalCard: View {
    let goal: WeightGoal
    let isSelected: Bool
    let calorieTarget: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.coral : Color.brandPrimary.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: goal.sfSymbol)
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? Color.onAccent : Color.brandPrimary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.displayName)
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color.brandPrimary : .primary)
                    Text(goal.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(calorieTarget)")
                        .font(.title3).fontWeight(.bold)
                        .foregroundStyle(isSelected ? Color.brandPrimary : .primary)
                        .monospacedDigit()
                    Text("kcal/day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? Color.brandPrimary : Color(.separator),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pace selector

private struct PaceSelectorSection: View {
    @Binding var pace: LossPace
    let tdee: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How fast do you want to lose?")
                .font(.subheadline).fontWeight(.medium)

            VStack(spacing: 8) {
                ForEach(LossPace.allCases) { p in
                    PaceRow(pace: p, isSelected: pace == p, tdee: tdee) {
                        pace = p
                    }
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }
}

private struct PaceRow: View {
    let pace: LossPace
    let isSelected: Bool
    let tdee: Int
    let onTap: () -> Void

    var calorieTarget: Int {
        max(tdee - pace.dailyDeficit, Constants.Calories.minimumFemale)
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: isSelected ? "circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.brandPrimary : .secondary)
                    .font(.system(size: 16))

                Text(pace.displayName)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.brandPrimary : .primary)

                Spacer()

                Text("−\(pace.dailyDeficit) kcal deficit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Goal summary card

private struct GoalSummaryCard: View {
    let goal: WeightGoal
    let dailyCalories: Int
    let tdee: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your daily target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(dailyCalories) kcal")
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(Color.brandPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.4), value: dailyCalories)
            }
            Spacer()
            Image(systemName: goal.sfSymbol)
                .font(.system(size: 32))
                .foregroundStyle(Color.brandPrimary.opacity(0.3))
        }
        .padding(16)
        .background(Color.brandPrimary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        GoalSelectionView(vm: OnboardingViewModel())
    }
}
