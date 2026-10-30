import SwiftUI

/// Keeps the normal full-height layout, while allowing large text to scroll
/// rather than pushing the primary/skip actions beyond the screen.
struct AdaptiveOnboardingPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
