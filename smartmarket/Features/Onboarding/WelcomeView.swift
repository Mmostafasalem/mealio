import SwiftUI

struct WelcomeView: View {

    let onGetStarted: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var headerVisible   = false
    @State private var card1Visible    = false
    @State private var card2Visible    = false
    @State private var card3Visible    = false
    @State private var card4Visible    = false
    @State private var ctaVisible      = false

    private let features: [(String, String, String, Color)] = [
        ("brain.head.profile","AI Meal Plans",     "A weekly plan built around your goals",     Color.dullPink),
        ("chart.bar.fill",  "Calorie & Macro Tracking", "Log food and hit your targets",        Color.dullPink),
        ("basket.fill",     "Budget Grocery Lists", "Plan your shop with estimated prices",     Color.dullPink),
        ("fork.knife",      "Recipes On Tap",      "Turn any planned meal into a recipe",       Color.dullPink),
    ]

    var body: some View {
        ZStack {
            Color.rhino.ignoresSafeArea()

            // Content
            AdaptiveOnboardingPage {
            VStack(spacing: 0) {

                Spacer()

                // Logo + headline
                VStack(spacing: 16) {
                    MascotGuideView(size: 132)
                        .opacity(headerVisible ? 1 : 0)

                    VStack(spacing: 8) {
                        Text("Mealio")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Color.almond)
                        BalancedHeadline(text: "A little more balance. Every day.", color: .almond.opacity(0.75))
                            .frame(maxWidth: 300)
                    }
                    .opacity(headerVisible ? 1 : 0)
                    .offset(y: headerVisible || reduceMotion ? 0 : 12)
                    Text("Tap your bowl guide for a little help.")
                        .font(.footnote)
                        .foregroundStyle(Color.almond.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .opacity(headerVisible ? 1 : 0)
                }
                .padding(.bottom, 40)

                // Feature cards
                VStack(spacing: 12) {
                    ForEach(Array(features.enumerated()), id: \.offset) { idx, feature in
                        FeaturePill(
                            icon: feature.0,
                            title: feature.1,
                            subtitle: feature.2,
                            color: feature.3
                        )
                        .opacity(cardOpacity(idx))
                        .offset(x: cardOffset(idx))
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                // CTA
                VStack(spacing: 12) {
                    Button(action: onGetStarted) {
                        HStack(spacing: 10) {
                            Text("Get Started")
                                .font(.headline)
                            Image(systemName: "arrow.right")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.dullPink)
                        .foregroundStyle(Color.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    }
                    .scaleEffect(ctaVisible ? 1 : 0.9)
                    .opacity(ctaVisible ? 1 : 0)
                    .accessibilityIdentifier("onboarding.start")

                    Text("Free · No credit card required")
                        .font(.caption)
                        .foregroundStyle(Color.almond.opacity(0.45))
                        .opacity(ctaVisible ? 1 : 0)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            }
            }
        }
        .onAppear {
            animate()
        }
    }

    private func cardOpacity(_ idx: Int) -> Double {
        switch idx {
        case 0: return card1Visible ? 1 : 0
        case 1: return card2Visible ? 1 : 0
        case 2: return card3Visible ? 1 : 0
        default: return card4Visible ? 1 : 0
        }
    }

    private func cardOffset(_ idx: Int) -> CGFloat {
        let visible: Bool
        switch idx {
        case 0: visible = card1Visible
        case 1: visible = card2Visible
        case 2: visible = card3Visible
        default: visible = card4Visible
        }
        return visible || reduceMotion ? 0 : 40
    }

    private func animate() {
        guard !reduceMotion else {
            headerVisible = true; card1Visible = true; card2Visible = true
            card3Visible = true; card4Visible = true; ctaVisible = true
            return
        }
        withAnimation(.spring(duration: 0.6, bounce: 0.3)) { headerVisible = true }
        withAnimation(.spring(duration: 0.5, bounce: 0.2).delay(0.25)) { card1Visible = true }
        withAnimation(.spring(duration: 0.5, bounce: 0.2).delay(0.38)) { card2Visible = true }
        withAnimation(.spring(duration: 0.5, bounce: 0.2).delay(0.51)) { card3Visible = true }
        withAnimation(.spring(duration: 0.5, bounce: 0.2).delay(0.64)) { card4Visible = true }
        withAnimation(.spring(duration: 0.6, bounce: 0.1).delay(0.85)) { ctaVisible = true }
    }
}

private struct FeaturePill: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.2))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(Color.almond)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.almond.opacity(0.6))
            }

            Spacer()
        }
        .padding(14)
        .background(Color.almond.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.almond.opacity(0.12), lineWidth: 1)
        )
    }
}

#Preview { WelcomeView(onGetStarted: {}) }
