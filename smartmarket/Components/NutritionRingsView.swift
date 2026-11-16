import SwiftUI

/// Stacked rings: calories outermost, then protein, carbs and fat. Each ring
/// fills clockwise from the top; a faint track of its own colour sits behind it.
struct NutritionRingsView: View {
    struct Ring: Identifiable {
        let id: String
        let fraction: Double
        let color: Color
    }

    let rings: [Ring]
    var size: CGFloat = 144
    var lineWidth: CGFloat = 12
    var gap: CGFloat = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let diameter = size - lineWidth - CGFloat(index) * 2 * (lineWidth + gap)
                let value = min(max(ring.fraction.isFinite ? ring.fraction : 0, 0), 1)
                Circle()
                    .stroke(ring.color.opacity(0.22), lineWidth: lineWidth)
                    .frame(width: diameter, height: diameter)
                Circle()
                    .trim(from: 0, to: shown ? value : 0)
                    .stroke(ring.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter, height: diameter)
                    // Nothing eaten yet: no dot at the top of an empty ring.
                    .opacity(value > 0 ? 1 : 0)
                    .animation(reduceMotion ? nil : .snappyValue, value: value)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(reduceMotion ? nil : .smoothCard) { shown = true }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    NutritionRingsView(rings: [
        .init(id: "kcal", fraction: 0.53, color: .ringCalories),
        .init(id: "protein", fraction: 0.13, color: .ringProtein),
        .init(id: "carbs", fraction: 0, color: .ringCarbs),
        .init(id: "fat", fraction: 0.71, color: .ringFat)
    ])
    .padding()
}
