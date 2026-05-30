import SwiftUI

/// 5-step progress indicator shown at the top of every onboarding screen.
struct OnboardingProgressBar: View {

    let currentStep: Int   // 1-indexed, 1...5
    let totalSteps = 5

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.brandPrimary : Color(.systemFill))
                    .frame(height: 4)
                    .animation(.spring(duration: 0.4, bounce: 0.2), value: currentStep)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

#Preview {
    VStack(spacing: 16) {
        OnboardingProgressBar(currentStep: 1)
        OnboardingProgressBar(currentStep: 2)
        OnboardingProgressBar(currentStep: 3)
        OnboardingProgressBar(currentStep: 4)
    }
    .padding()
}
