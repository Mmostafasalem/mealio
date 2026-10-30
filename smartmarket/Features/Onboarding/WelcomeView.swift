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
    @State private var bgShift         = false

    private let features: [(String, String, String, Color)] = [
        ("brain.head.profile","AI Meal Plans",     "A weekly plan built around your goals",     Color(hex: "#6366F1")),
        ("chart.bar.fill",  "Calorie & Macro Tracking", "Log food and hit your targets",        Color(hex: "#0EA5E9")),
        ("basket.fill",     "Budget Grocery Lists", "Plan your shop with estimated prices",     Color.brandPrimary),
        ("fork.knife",      "Recipes On Tap",      "Turn any planned meal into a recipe",       Color(hex: "#D97706")),
    ]

    var body: some View {
        ZStack {
            // Animated background
            LinearGradient(
                colors: [Color.brandHeader, Color.brandHeaderMid, Color.brandDark],
                startPoint: bgShift ? .topLeading : .bottomLeading,
                endPoint:   bgShift ? .bottomTrailing : .topTrailing
            )
            .ignoresSafeArea()
            .animation(
                reduceMotion ? .none : .easeInOut(duration: 6).repeatForever(autoreverses: true),
                value: bgShift
            )

            // Soft bokeh blobs
            GeometryReader { geo in
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 320, height: 320)
                    .offset(x: geo.size.width * 0.55, y: -60)
                    .blur(radius: 60)
                Circle()
                    .fill(Color.brandPrimary.opacity(0.18))
                    .frame(width: 260, height: 260)
                    .offset(x: -40, y: geo.size.height * 0.55)
                    .blur(radius: 80)
            }
            .ignoresSafeArea()

            // Content
            AdaptiveOnboardingPage {
            VStack(spacing: 0) {

                Spacer()

                // Logo + headline
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 96, height: 96)
                        Image(systemName: "cart.badge.plus")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(headerVisible ? 1 : 0.5)
                    .opacity(headerVisible ? 1 : 0)

                    VStack(spacing: 8) {
                        Text("Mealio")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Eat well. Spend less.")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .opacity(headerVisible ? 1 : 0)
                    .offset(y: headerVisible ? 0 : 12)
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
                        .background(.white)
                        .foregroundStyle(Color.brandDark)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    }
                    .scaleEffect(ctaVisible ? 1 : 0.9)
                    .opacity(ctaVisible ? 1 : 0)
                    .accessibilityIdentifier("onboarding.start")

                    Text("Free · No credit card required")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .opacity(ctaVisible ? 1 : 0)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            }
            }
        }
        .onAppear {
            bgShift = true
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
        return visible ? 0 : 40
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.2))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

#Preview { WelcomeView(onGetStarted: {}) }
