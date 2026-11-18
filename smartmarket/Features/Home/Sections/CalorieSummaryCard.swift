import SwiftUI
import TipKit

/// The dashboard hero: calorie ring + today's total + macro breakdown.
struct CalorieSummaryCard: View {
    let vm: HomeViewModel
    var onLog: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showCalorieDetail = false
    private let logFoodTip = LogFoodTip()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                HomeCardTitle(title: "Calories", symbol: "flame.fill")
                Spacer(minLength: Spacing.sm)
                Text("\(abs(vm.goal - vm.consumed)) kcal \(vm.consumed > vm.goal ? "over" : "left")")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.labelSecondary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Button { showCalorieDetail.toggle() } label: {
                NutritionRingsView(rings: [
                    .init(id: "kcal", fraction: Self.fraction(Double(vm.consumed), Double(vm.goal)), color: .ringCalories),
                    .init(id: "protein", fraction: Self.fraction(vm.proteinCurrent, vm.proteinGoal), color: .ringProtein),
                    .init(id: "carbs", fraction: Self.fraction(vm.carbsCurrent, vm.carbsGoal), color: .ringCarbs),
                    .init(id: "fat", fraction: Self.fraction(vm.fatCurrent, vm.fatGoal), color: .ringFat)
                ])
            }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("home.calorieDetails")
                .popover(isPresented: $showCalorieDetail, attachmentAnchor: .point(.center), arrowEdge: .top) {
                    CalorieDetailPopover(vm: vm)
                }
                .accessibilityLabel("Calories: \(vm.consumed) of \(vm.goal) kilocalories")
                .accessibilityHint("Tap for calorie breakdown")

            // Two columns of figures, each marked with its ring's colour; one column when text is very large.
            let columns = dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible(), alignment: .leading)]
                : [GridItem(.flexible(), spacing: Spacing.lg, alignment: .leading), GridItem(.flexible(), alignment: .leading)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.md) {
                figure(label: "Calories", value: "\(vm.consumed)/\(vm.goal)", unit: "kcal", color: .ringCalories,
                       spoken: "Calories: \(vm.consumed) of \(vm.goal) kilocalories", tooltip: nil)
                macroFigure(label: "Protein", current: vm.proteinCurrent, goal: vm.proteinGoal, color: .ringProtein,
                            tooltip: "Protein builds and repairs muscle. Your target is \(Self.grams(vm.proteinGoal)) g a day: 30% of your daily calories (25% on a keto diet).")
                macroFigure(label: "Carbs", current: vm.carbsCurrent, goal: vm.carbsGoal, color: .ringCarbs,
                            tooltip: "Carbohydrates are your body's primary fuel. Choose complex sources like oats, rice, and legumes.")
                macroFigure(label: "Fat", current: vm.fatCurrent, goal: vm.fatGoal, color: .ringFat,
                            tooltip: "Healthy fats support hormones and brain function. Include olive oil, nuts, and fatty fish.")
            }
            .animation(reduceMotion ? nil : .snappyValue, value: vm.consumed)

            // Inline, so it never covers the figures; gone once food is logged.
            TipView(logFoodTip, arrowEdge: .bottom)

            PrimaryButton(title: "Log food", systemImage: "plus", action: onLog)
                .accessibilityIdentifier("home.logFood")
        }
        .padding(Spacing.lg)
        // The three macro "i" buttons share one travelling tooltip bubble.
        .morphTooltipHost()
        .premiumCard(surface: .hero)
    }

    static func fraction(_ current: Double, _ goal: Double) -> Double {
        goal > 0 && current.isFinite ? current / goal : 0
    }

    /// Whole grams, rounded to nearest (29.9 g reads 30 g, not 29 g).
    static func grams(_ value: Double) -> Int {
        value.isFinite ? Int(value.rounded()) : 0
    }

    static func macroText(current: Double, goal: Double) -> String {
        "\(grams(current)) / \(grams(goal)) g"
    }

    static func macroAccessibilityText(label: String, current: Double, goal: Double) -> String {
        "\(label): \(grams(current)) of \(grams(goal)) grams"
    }

    private func macroFigure(label: String, current: Double, goal: Double, color: Color, tooltip: String) -> some View {
        figure(label: label, value: "\(Self.grams(current))/\(Self.grams(goal))", unit: "g", color: color,
               spoken: Self.macroAccessibilityText(label: label, current: current, goal: goal), tooltip: tooltip)
    }

    /// A name over its "eaten/goal" figure; the ring's colour is only a dot beside the name.
    private func figure(label: String, value: String, unit: String, color: Color,
                        spoken: String, tooltip: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Circle().fill(color)
                    .frame(width: 8, height: 8)
                    .padding(.trailing, 6)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.labelPrimary)
                    .accessibilityHidden(true)
                if let tooltip {
                    // Keeps its 44pt tap target without stretching the row.
                    InfoTooltip(text: tooltip)
                        .padding(.leading, -8)
                        .frame(height: 20)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.labelPrimary)
                    .contentTransition(.numericText())
                Text(unit.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.labelSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
        }
    }
}

/// Calorie breakdown shown in the ring's popover.
private struct CalorieDetailPopover: View {
    let vm: HomeViewModel

    var body: some View {
        let remaining = max(vm.goal - vm.consumed, 0)
        let over = max(vm.consumed - vm.goal, 0)
        // Not capped: over the goal reads 115%, matching "kcal over" on the card.
        let pct = vm.goal > 0 ? Int((Double(vm.consumed) / Double(vm.goal) * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Calorie summary").font(.headline)
            Divider()
            row("Consumed", value: "\(vm.consumed) kcal", color: .primary)
            row("Daily goal", value: "\(vm.goal) kcal", color: .secondary)
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
