import SwiftUI

/// 5-step progress indicator shown at the top of every onboarding screen.
struct OnboardingProgressBar: View {

    let currentStep: Int   // 1-indexed, 1...5
    let totalSteps = 5

    var body: some View {
        VStack(spacing: 10) {
            // Step dots + connecting lines
            HStack(spacing: 0) {
                ForEach(1...totalSteps, id: \.self) { step in
                    // Dot
                    ZStack {
                        Circle()
                            .fill(step < currentStep ? Color.dullPink : step == currentStep ? Color.dullPink : Color(.systemFill))
                            .frame(width: 28, height: 28)
                        if step < currentStep {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.onAccent)
                        } else {
                            Text("\(step)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(step == currentStep ? Color.onAccent : Color.labelSecondary)
                        }
                    }
                    .overlay(
                        Circle().strokeBorder(
                            step == currentStep ? Color.dullPink : Color.clear,
                            lineWidth: 2
                        )
                        .scaleEffect(1.3)
                        .opacity(step == currentStep ? 1 : 0)
                    )
                    .animation(.spring(duration: 0.4, bounce: 0.3), value: currentStep)

                    // Connector
                    if step < totalSteps {
                        Rectangle()
                            .fill(step < currentStep ? Color.dullPink : Color(.systemFill))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                            .animation(.spring(duration: 0.4), value: currentStep)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }
}

#Preview {
    VStack(spacing: 24) {
        ForEach(1...5, id: \.self) { step in
            OnboardingProgressBar(currentStep: step)
        }
    }
    .padding()
}
