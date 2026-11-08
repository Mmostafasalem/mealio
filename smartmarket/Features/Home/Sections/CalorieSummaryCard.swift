import SwiftUI

/// The dashboard hero: calorie ring + today's total + macro breakdown.
struct CalorieSummaryCard: View {
    let vm: HomeViewModel
    var onLog: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showCalorieDetail = false

    var body: some View {
        VStack(spacing: 0) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xl))
                : AnyLayout(HStackLayout(spacing: Spacing.xl))
            layout {
                Button { showCalorieDetail.toggle() } label: {
                    CalorieRingView(consumed: vm.consumed, goal: vm.goal, size: 128)
                        .frame(width: 128, height: 128)
                }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.calorieDetails")
                    .popover(isPresented: $showCalorieDetail, attachmentAnchor: .point(.center), arrowEdge: .trailing) {
                        CalorieDetailPopover(vm: vm)
                    }
                    .accessibilityLabel("Calories: \(vm.consumed) of \(vm.goal) kilocalories")
                    .accessibilityHint("Tap for calorie breakdown")

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(vm.consumed > vm.goal ? "Above daily goal" : "Remaining today")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.labelSecondary)
                    Text("\(abs(vm.goal - vm.consumed))")
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(.captionText)
                        .foregroundStyle(Color.labelSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.lg)
            .animation(reduceMotion ? nil : .snappyValue, value: vm.consumed)

            Divider().padding(.horizontal, Spacing.lg)

            VStack(spacing: Spacing.xs) {
                macroRow(label: "Protein", symbol: "bolt.fill",
                         current: vm.proteinCurrent, goal: vm.proteinGoal,
                         tooltip: "Protein builds and repairs muscle. Your target is \(Int(vm.proteinGoal))g/day based on your weight and goal.")
                macroRow(label: "Carbs", symbol: "leaf.fill",
                         current: vm.carbsCurrent, goal: vm.carbsGoal,
                         tooltip: "Carbohydrates are your body's primary fuel. Choose complex sources like oats, rice, and legumes.")
                macroRow(label: "Fat", symbol: "drop.fill",
                         current: vm.fatCurrent, goal: vm.fatGoal,
                         tooltip: "Healthy fats support hormones and brain function. Include olive oil, nuts, and fatty fish.")
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)

            PrimaryButton(title: "Log food", systemImage: "plus", action: onLog)
                .accessibilityIdentifier("home.logFood")
                .padding([.horizontal, .bottom], Spacing.lg)
        }
        .premiumCard(surface: .hero)
    }

    private func macroRow(label: String, symbol: String,
                          current: Double, goal: Double, tooltip: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            let rowLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(spacing: Spacing.sm))
            rowLayout {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: symbol).frame(width: 18)
                        .accessibilityHidden(true)
                    Text(label).font(.subheadline.weight(.semibold))
                    InfoTooltip(text: tooltip)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text("\(Int(current)) / \(Int(goal)) g")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.labelSecondary)
                    .accessibilityLabel("\(label): \(Int(current)) of \(Int(goal)) grams")
            }
            ProgressView(value: min(max(current, 0), goal), total: max(goal, 1))
                .tint(Color.brandPrimary)
                .accessibilityHidden(true)
        }
    }
}

/// Calorie breakdown shown in the ring's popover.
private struct CalorieDetailPopover: View {
    let vm: HomeViewModel

    var body: some View {
        let remaining = max(vm.goal - vm.consumed, 0)
        let over = max(vm.consumed - vm.goal, 0)
        let pct = vm.goal > 0 ? min(Int(Double(vm.consumed) / Double(vm.goal) * 100), 100) : 0
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Calorie Summary").font(.headline)
            Divider()
            row("Consumed", value: "\(vm.consumed) kcal", color: .primary)
            row("Daily Goal", value: "\(vm.goal) kcal", color: .secondary)
            row(over > 0 ? "Over by" : "Remaining",
                value: "\(over > 0 ? over : remaining) kcal",
                color: over > 0 ? .brandDanger : .brandPrimary)
            Divider()
            Text("\(pct)% of daily goal").font(.caption).foregroundStyle(Color.labelSecondary)
        }
        .font(.subheadline)
        .padding(Spacing.lg)
        .frame(minWidth: 210)
        .presentationCompactAdaptation(.popover)
    }

    private func row(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.labelSecondary)
            Spacer()
            Text(value).bold().foregroundStyle(color)
        }
    }
}
