import SwiftUI

struct NotificationPermissionView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {
        AdaptiveOnboardingPage {
        VStack(spacing: 0) {

            OnboardingProgressBar(currentStep: 4)
                .padding(.top, 8)
                .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.brandAmber)

                VStack(spacing: 8) {
                    Text("No retail alerts")
                        .font(.largeTitle).fontWeight(.bold)
                    Text("Catalog prices are estimates. Mealio does not send discount, nearby stock or expiry alerts from them.")
                        .font(.subheadline)
                        .foregroundStyle(Color.labelSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 12) {
                    FeatureRow(symbol: "tag", text: "Check current prices and availability with the store")
                    FeatureRow(symbol: "bell.slash", text: "Meal and logging reminders are not available yet")
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    vm.path.append(OnboardingStep.favorites)
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .foregroundStyle(Color.onAccent)
                        .background(Color.dullPink,
                                    in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                }
                .buttonStyle(ScalePressStyle())
                .accessibilityIdentifier("onboarding.notifications.skip")
                .frame(minHeight: 44)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
        }
        .navigationBarHidden(true)
        .background(Color.surfaceGrouped.ignoresSafeArea())
    }
}

private struct FeatureRow: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.brandAmber)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.labelSecondary)
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        NotificationPermissionView(vm: OnboardingViewModel())
    }
}
