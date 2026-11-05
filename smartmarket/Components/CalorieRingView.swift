import SwiftUI

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

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.surfaceSecondary, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: size - 18, height: size - 18)

            ProgressArc(progress: animatedProgress)
                .stroke(Color.dullPink, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: size - 18, height: size - 18)

            // Center text
            VStack(spacing: 2) {
                Text("\(consumed)")
                    .font(.system(size: size * 0.21, weight: .bold, design: .default))
                    .foregroundStyle(Color.labelPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("/ \(goal) kcal")
                    .font(.system(size: size * 0.085, weight: .medium, design: .default))
                    .foregroundStyle(Color.labelSecondary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(reduceMotion ? .none : .smoothCard) {
                animatedProgress = rawFraction
            }
        }
        .onChange(of: consumed) { _, _ in
            withAnimation(reduceMotion ? .none : .snappyValue) { animatedProgress = rawFraction }
        }
        .onChange(of: goal) { _, _ in
            withAnimation(reduceMotion ? .none : .snappyValue) { animatedProgress = rawFraction }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Consumed \(consumed) of \(goal) calories")
        .accessibilityValue("\(Int(rawFraction * 100)) percent")
    }
}

// MARK: - Animatable arc shape

private struct ProgressArc: Shape {

    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center:     CGPoint(x: rect.midX, y: rect.midY),
            radius:     rect.width / 2,
            startAngle: .degrees(-90),
            endAngle:   .degrees(-90 + 360 * min(max(progress, 0), 1.0)),
            clockwise:  false
        )
        return path
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
