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

    private var ringColor: Color {
        switch rawFraction {
        case ..<0.8:    return .brandPrimary
        case 0.8...1.0: return .brandAmber
        default:        return .brandDanger
        }
    }

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color(.systemGray5), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .frame(width: size - 18, height: size - 18)

            // Soft glow (blurred, wider copy of the arc)
            if animatedProgress > 0.02 {
                ProgressArc(progress: animatedProgress)
                    .stroke(ringColor.opacity(0.28), style: StrokeStyle(lineWidth: 28, lineCap: .round))
                    .frame(width: size - 18, height: size - 18)
                    .blur(radius: 10)
                    .allowsHitTesting(false)
            }

            // Main arc
            ProgressArc(progress: animatedProgress)
                .stroke(
                    LinearGradient(
                        colors: [ringColor, ringColor.opacity(0.75)],
                        startPoint: .top, endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .frame(width: size - 18, height: size - 18)
                .shadow(color: ringColor.opacity(0.35), radius: 5, x: 0, y: 2)

            // Center text
            VStack(spacing: 2) {
                Text("\(consumed)")
                    .font(.system(size: size * 0.21, weight: .bold, design: .rounded))
                    .foregroundStyle(ringColor)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("/ \(goal) kcal")
                    .font(.system(size: size * 0.085, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(duration: 1.4, bounce: 0.2)) {
                animatedProgress = rawFraction
            }
        }
        .onChange(of: consumed) { _, _ in
            withAnimation(.spring(duration: 0.55, bounce: 0.1)) { animatedProgress = rawFraction }
        }
        .onChange(of: goal) { _, _ in
            withAnimation(.spring(duration: 0.55, bounce: 0.1)) { animatedProgress = rawFraction }
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
