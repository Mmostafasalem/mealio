import SwiftUI

extension View {
    /// A lightly grained brand wash underneath an opaque, readable card.
    func premiumCard(radius: CGFloat = Radius.card, surface: GrainyGradient.Surface = .card) -> some View {
        self.background {
            GrainyGradient(surface: surface)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.hairline.opacity(0.6), lineWidth: 0.5))
            .elevation(Elevation.card)
    }

    /// Floating controls use the same opaque, accessible surface language.
    func glassCard(radius: CGFloat = Radius.card) -> some View {
        self.background(Color.surfaceElevated,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.hairline.opacity(0.6), lineWidth: 0.5))
            .elevation(Elevation.card)
    }
}

// MARK: - Press scale

extension View {
    /// Subtle scale-down on press — makes interactive cards feel tactile.
    func pressable() -> some View {
        buttonStyle(PressableButtonStyle())
    }
}

private struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(reduceMotion ? .none : .snappyValue, value: configuration.isPressed)
    }
}
