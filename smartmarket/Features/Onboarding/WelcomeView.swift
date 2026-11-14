import SwiftUI

struct WelcomeView: View {

    let onGetStarted: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mascotVisible = false
    @State private var textVisible = false
    @State private var ctaVisible = false
    /// Each bump makes Nourlo hop and wave.
    @State private var greeting = 0

    var body: some View {
        ZStack {
            GrainyGradient(surface: .welcome).ignoresSafeArea()

            // One screen, nothing to scroll: Nourlo, one line about what it does, one button.
            GeometryReader { geo in
            // The bowl gives way first when the screen is short (landscape, small phones).
            let compact = geo.size.height < 520
            VStack(spacing: 0) {
                Spacer(minLength: compact ? 0 : Spacing.xl)

                // Nourlo is alive here: it hops and waves hello, then again every
                // few seconds, and whenever it is tapped.
                MascotGuideView(mood: .happy, size: min(220, max(72, geo.size.height * 0.34)), trigger: greeting, hint: "Says hello.")
                    .scaleEffect(mascotVisible || reduceMotion ? 1 : 0.6)
                    .opacity(mascotVisible ? 1 : 0)

                VStack(spacing: compact ? Spacing.xs : Spacing.md) {
                    Text("Nourlo")
                        .font(.system(size: compact ? 30 : 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.almond)
                    WordRoll(
                        lead: "Helps you",
                        words: ["plan meals", "track calories", "shop on budget", "train smarter"],
                        font: .title3.weight(.semibold),
                        leadColor: .almond.opacity(0.7),
                        wordColor: .almond,
                        accessibilityText: "Nourlo helps you plan meals, track calories, shop on budget and train smarter."
                    )
                }
                .padding(.top, compact ? 0 : Spacing.lg)
                .opacity(textVisible ? 1 : 0)
                .offset(y: textVisible || reduceMotion ? 0 : 12)

                Spacer(minLength: compact ? Spacing.sm : Spacing.xl)
                if !compact { Spacer(minLength: Spacing.xl) }

                Button(action: onGetStarted) {
                    Text("Get started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: compact ? 48 : 56)
                        .background(Color.dullPink, in: Capsule())
                        .foregroundStyle(Color.onAccent)
                        .contentShape(Capsule())
                }
                .buttonStyle(ScalePressStyle())
                .scaleEffect(ctaVisible || reduceMotion ? 1 : 0.92)
                .opacity(ctaVisible ? 1 : 0)
                .accessibilityIdentifier("onboarding.start")
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, compact ? 40 : 48)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .onAppear { animate() }
        .task {
            // A fresh hello every few seconds; the bowl rests in between.
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                greeting += 1
            }
        }
    }

    private func animate() {
        guard !reduceMotion else {
            mascotVisible = true; textVisible = true; ctaVisible = true
            return
        }
        withAnimation(.spring(duration: 0.7, bounce: 0.45)) { mascotVisible = true }
        withAnimation(.spring(duration: 0.5, bounce: 0.2).delay(0.25)) { textVisible = true }
        withAnimation(.spring(duration: 0.5, bounce: 0.15).delay(0.45)) { ctaVisible = true }
        // The first hello, once it has landed.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            greeting += 1
        }
    }
}

#Preview { WelcomeView(onGetStarted: {}) }
