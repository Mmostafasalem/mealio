import SwiftUI

/// Lightweight shimmer overlay for skeleton loaders.
private struct ShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        if active {
            content
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.45), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 1.5)
                        .offset(x: phase * geo.size.width * 1.5)
                        .blendMode(.plusLighter)
                    }
                    .allowsHitTesting(false)
                )
                .clipped()
                .onAppear {
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                        phase = 1.5
                    }
                }
                .onDisappear {
                    phase = -1
                }
        } else {
            content
        }
    }
}

extension View {
    func shimmer(active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}
