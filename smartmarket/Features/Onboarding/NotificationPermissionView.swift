import SwiftUI

struct NotificationPermissionView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {
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
                    Text("Never miss a deal")
                        .font(.largeTitle).fontWeight(.bold)
                    Text("We'll ping you the moment a discount appears on one of your favourite foods — with a one-tap option to add it to your grocery list.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 12) {
                    FeatureRow(symbol: "heart.fill",      text: "Only notifies for your favourite foods")
                    FeatureRow(symbol: "location.fill",   text: "Only from stores within 1 km")
                    FeatureRow(symbol: "cart.badge.plus", text: "Tap yes to add to grocery list instantly")
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        await NotificationService.shared.requestPermission()
                        vm.path.append(OnboardingStep.favorites)
                    }
                } label: {
                    Label("Enable notifications", systemImage: "bell.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandAmber)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    vm.path.append(OnboardingStep.favorites)
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
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
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        NotificationPermissionView(vm: OnboardingViewModel())
    }
}
