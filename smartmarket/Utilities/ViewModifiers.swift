import SwiftUI

// MARK: - Premium card

extension View {
    /// Flat, premium elevated surface with smooth continuous ("squircle") corners.
    /// No visible border — elevation comes from a soft shadow (light mode) and a
    /// lighter surface fill (dark mode), the way Spotify / modern iOS cards read.
    func premiumCard(radius: CGFloat = 22) -> some View {
        self
            .background(
                Color.surfaceElevated,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Glass surface

extension View {
    /// Ultra-thin material card — use for floating overlays and banners.
    func glassCard(radius: CGFloat = 20) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.45), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
