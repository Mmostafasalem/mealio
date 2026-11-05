import SwiftUI

/// The dashboard hero: calorie ring + today's total + macro breakdown.
struct CalorieSummaryCard: View {
    let vm: HomeViewModel
    var onLog: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showCalorieDetail = false

    var body: some View {
        VStack(spacing: 0) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xl))
                : AnyLayout(HStackLayout(spacing: Spacing.xl))
            layout {
                CalorieRingView(consumed: vm.consumed, goal: vm.goal, size: 144)
                    .frame(width: 144, height: 144)
                    .onTapGesture { showCalorieDetail.toggle() }
                    .popover(isPresented: $showCalorieDetail, attachmentAnchor: .point(.center), arrowEdge: .trailing) {
                        CalorieDetailPopover(vm: vm)
                    }
                    .accessibilityLabel("Calories: \(vm.consumed) of \(vm.goal) kilocalories")
                    .accessibilityHint("Tap for calorie breakdown")

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TODAY’S ENERGY")
                            .font(.caption).fontWeight(.medium)
                            .foregroundStyle(Color.labelSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(vm.consumed)")
                                .font(.statValue)
                                .foregroundStyle(Color.labelPrimary)
                                .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                                .contentTransition(.numericText())
                            Text("/ \(vm.goal)")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.labelSecondary).minimumScaleFactor(0.7).lineLimit(1)
                            Text("kcal").font(.caption2).foregroundStyle(Color.labelSecondary)
                        }
                    }

                    Button(action: onLog) {
                        Label("Log Food", systemImage: "plus.circle.fill")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(Color.onAccent)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .frame(minHeight: 44)
                            .background(Color.dullPink, in: Capsule())
                    }
                    .buttonStyle(ScalePressStyle())
                    .accessibilityLabel("Log food")
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.lg)
            .animation(.snappyValue, value: vm.consumed)

            Divider().padding(.horizontal, Spacing.lg)

            HStack(spacing: 0) {
                macroTile(label: "Protein", symbol: "bolt.fill",
                          current: vm.proteinCurrent, goal: vm.proteinGoal, color: .proteinAccent,
                          tooltip: "Protein builds and repairs muscle. Your target is \(Int(vm.proteinGoal))g/day based on your weight and goal.")
                macroSeparator
                macroTile(label: "Carbs", symbol: "leaf.fill",
                          current: vm.carbsCurrent, goal: vm.carbsGoal, color: .carbsAccent,
                          tooltip: "Carbohydrates are your body's primary fuel. Choose complex sources like oats, rice, and legumes.")
                macroSeparator
                macroTile(label: "Fat", symbol: "drop.fill",
                          current: vm.fatCurrent, goal: vm.fatGoal, color: .fatAccent,
                          tooltip: "Healthy fats support hormones and brain function. Include olive oil, nuts, and fatty fish.")
            }
            .padding(.vertical, Spacing.md)
            .animation(.snappyValue, value: vm.proteinCurrent + vm.carbsCurrent + vm.fatCurrent)
        }
        .premiumCard()
    }

    private func macroTile(label: String, symbol: String,
                           current: Double, goal: Double, color: Color, tooltip: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12), in: Circle())
                    // The larger hit target must not enlarge the icon layout.
                    .overlay(alignment: .topTrailing) {
                        InfoTooltip(text: tooltip).offset(x: 26, y: -24)
                    }
            .frame(width: 38, height: 36)
            Text("\(Int(current))g")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.labelPrimary).monospacedDigit()
                .contentTransition(.numericText())
            Text("of \(Int(goal))g").font(.caption2).foregroundStyle(Color.labelSecondary)
            Text(label).font(.caption2).fontWeight(.semibold).foregroundStyle(color)
            ProgressView(value: min(max(current, 0), goal), total: max(goal, 1))
                .tint(color).frame(width: 44).padding(.top, 1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Int(current)) of \(Int(goal)) grams")
    }

    private var macroSeparator: some View {
        Rectangle().fill(Color(.separator).opacity(0.4)).frame(width: 0.5, height: 64)
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
