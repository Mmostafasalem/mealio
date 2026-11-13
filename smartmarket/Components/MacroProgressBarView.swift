import SwiftUI

/// A single animated macro progress bar (protein / carbs / fat).
struct MacroProgressBarView: View {

    let label: String
    let sfSymbol: String
    let current: Double
    let goal: Double
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedValue: Double {
        guard goal > 0 else { return 0 }
        return min(max(current, 0), goal)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: sfSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(label)
                .font(.caption).fontWeight(.medium)
                .frame(width: 56, alignment: .leading)

            ProgressView(value: clampedValue, total: max(goal, 1))
                .tint(color)
                .animation(reduceMotion ? .none : .snappyValue, value: current)

            Text("\(Int(current))g / \(Int(goal))g")
                .font(.caption2).fontWeight(.medium)
                .foregroundStyle(Color.labelSecondary)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(Int(current)) of \(Int(goal)) grams")
    }
}

#Preview {
    VStack(spacing: 16) {
        MacroProgressBarView(label: "Protein", sfSymbol: "fish.fill", current: 80, goal: 150, color: .blue)
        MacroProgressBarView(label: "Carbs", sfSymbol: "leaf.fill", current: 180, goal: 200, color: .brandAmber)
        MacroProgressBarView(label: "Fat", sfSymbol: "drop.fill", current: 70, goal: 65, color: .brandPrimary)
    }
    .padding()
}
