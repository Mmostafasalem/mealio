import SwiftUI

/// Shown when a widget, Siri, Shortcuts, Spotlight, a reminder or a voice
/// command asks for a feature the person turned off. Offers to turn it back
/// on (and then goes where they were heading) instead of a blank screen.
struct FeatureOffPrompt: View {
    let feature: AppFeature
    let turnOn: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: feature.symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.labelPrimary)
                .frame(width: 64, height: 64)
                .background(Color.brandLight, in: Circle())
                .accessibilityHidden(true)
                .padding(.top, Spacing.xl)

            VStack(spacing: Spacing.sm) {
                Text("\(feature.name) is turned off")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("featureOff.title")
                Text("You chose not to use this part of Nourlo. Turn it on to open it. You can turn it off again in Profile › Features.")
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(spacing: Spacing.sm) {
                Button(action: turnOn) {
                    Text("Turn on \(feature.name)").primaryButtonLabel()
                }
                .buttonStyle(ScalePressStyle())
                .accessibilityIdentifier("featureOff.turnOn")
                Button("Not now", action: close)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("featureOff.notNow")
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview { Text("").sheet(isPresented: .constant(true)) { FeatureOffPrompt(feature: .workouts, turnOn: {}, close: {}) } }
