import SwiftUI
import CoreLocation

struct LocationPermissionView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(vm: vm, step: .location, title: "Find stores near you",
                           subtitle: "Nourlo shows grocery prices at stores near you to help plan your shop.") {
            OnboardingInfoPanel(symbol: "location.fill", rows: [
                ("map.fill", "Shows estimated prices around your location"),
                ("battery.100", "Uses one-shot location — no background drain"),
                ("lock.shield", "Your location is sent to our backend to find nearby stores"),
            ])
        } footer: {
            Button {
                LocationService.shared.requestPermission()
                // Navigate after the system dialog — status update arrives
                // via the CLLocationManagerDelegate on the next run-loop tick.
                Task {
                    await Task.yield()
                    vm.advance(to: .diet)
                }
            } label: {
                Text("Allow location").primaryButtonLabel()
            }
            .buttonStyle(ScalePressStyle())

            Button { vm.advance(to: .diet) } label: {
                Text("Skip for now")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("onboarding.location.skip")
        }
    }
}

/// Icon badge plus a short list of plain facts, used by the permission screens.
struct OnboardingInfoPanel: View {
    let symbol: String
    let rows: [(symbol: String, text: String)]

    var body: some View {
        // Scrolls only if it truly can't fit (small phone with enlarged text).
        ViewThatFits(in: .vertical) {
            panel
            ScrollView { panel }.scrollIndicators(.hidden)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.labelPrimary)
                .frame(width: 72, height: 72)
                .background(Color.brandLight, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: Spacing.md) {
                        Image(systemName: row.symbol)
                            .foregroundStyle(Color.labelPrimary)
                            .frame(width: 24)
                        Text(row.text)
                            .font(.subheadline)
                            .foregroundStyle(Color.labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Spacing.md)
                    if index < rows.count - 1 { Divider().overlay(Color.hairline) }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack { LocationPermissionView(vm: OnboardingViewModel()) }
}
