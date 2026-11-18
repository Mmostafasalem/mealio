import SwiftUI

/// Content-shaped placeholders remain static when animation would be disruptive.
private struct ShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    private var animates: Bool { active && !reduceMotion && !lowPower && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .overlay {
                if animates {
                    GeometryReader { geometry in
                        // A faint band on dark surfaces; almond at 45% there is a bright stripe.
                        LinearGradient(colors: [.clear, Color.almond.opacity(colorScheme == .dark ? 0.1 : 0.45), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width * 1.5)
                            .offset(x: phase * geometry.size.width * 1.5)
                    }
                    .allowsHitTesting(false)
                    .onAppear {
                        phase = -1
                        withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                            phase = 1.5
                        }
                    }
                    .onDisappear { phase = -1 }
                }
            }
            .clipped()
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}

extension View {
    func shimmer(active: Bool = true) -> some View { modifier(ShimmerModifier(active: active)) }
}
