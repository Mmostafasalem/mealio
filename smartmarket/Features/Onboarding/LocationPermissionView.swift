import SwiftUI
import CoreLocation

struct LocationPermissionView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {

            OnboardingProgressBar(currentStep: 2)
                .padding(.top, 8)
                .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.brandPrimary)

                VStack(spacing: 8) {
                    Text("Find deals near you")
                        .font(.largeTitle).fontWeight(.bold)
                    Text("Mealio checks nearby stores for discounts on your favourite foods.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 12) {
                    FeatureRow(symbol: "map.fill",    text: "Only shows deals at stores you can reach")
                    FeatureRow(symbol: "battery.100", text: "Uses one-shot location — no background drain")
                    FeatureRow(symbol: "lock.shield", text: "Location never leaves your device")
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    LocationService.shared.requestPermission()
                    // Navigate after the system dialog — status update arrives
                    // via the CLLocationManagerDelegate on the next run-loop tick.
                    Task {
                        // Yield once so the delegate has a chance to fire before
                        // we push the next screen.
                        await Task.yield()
                        vm.path.append(OnboardingStep.goal)
                    }
                } label: {
                    Label("Allow Location", systemImage: "location.fill")
                        .primaryButtonLabel()
                }
                .buttonStyle(ScalePressStyle())

                Button {
                    vm.path.append(OnboardingStep.goal)
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
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
                .foregroundStyle(Color.brandPrimary)
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
        LocationPermissionView(vm: OnboardingViewModel())
    }
}
