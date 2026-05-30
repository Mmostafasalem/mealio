import SwiftUI

/// Canvas-drawn animated calorie ring (consumed / goal).
struct CalorieRingView: View {

    let consumed: Int
    let goal: Int
    var size: CGFloat = 160

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    private var rawFraction: Double {
        guard goal > 0 else { return 0 }
        return Double(consumed) / Double(goal)
    }

    private var ringColor: Color {
        switch rawFraction {
        case ..<0.8:   return .brandPrimary
        case 0.8...1.0: return .brandAmber
        default:       return .brandDanger
        }
    }

    var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                let lineWidth: CGFloat = 16
                let rect = CGRect(origin: .zero, size: canvasSize)
                    .insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let radius = rect.width / 2

                var background = Path()
                background.addEllipse(in: rect)
                context.stroke(
                    background,
                    with: .color(Color(.systemGray5)),
                    style: StrokeStyle(lineWidth: lineWidth)
                )

                guard animatedProgress > 0 else { return }
                var foreground = Path()
                foreground.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * min(animatedProgress, 1.0)),
                    clockwise: false
                )
                context.stroke(
                    foreground,
                    with: .color(ringColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
            .frame(width: size, height: size)
            .animation(reduceMotion ? .none : .spring(duration: 1.2, bounce: 0.2), value: animatedProgress)

            VStack(spacing: 2) {
                Text("\(consumed)")
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                    .foregroundStyle(ringColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("/ \(goal) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear { animatedProgress = rawFraction }
        .onChange(of: consumed) { _, _ in animatedProgress = rawFraction }
        .onChange(of: goal) { _, _ in animatedProgress = rawFraction }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Consumed \(consumed) of \(goal) calories")
        .accessibilityValue("\(Int(rawFraction * 100)) percent")
    }
}

#Preview {
    HStack(spacing: 24) {
        CalorieRingView(consumed: 1200, goal: 2000)
        CalorieRingView(consumed: 1850, goal: 2000)
        CalorieRingView(consumed: 2300, goal: 2000)
    }
    .padding()
}
