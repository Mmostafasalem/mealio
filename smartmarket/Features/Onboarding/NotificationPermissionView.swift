import SwiftUI

struct NotificationPermissionView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(vm: vm, step: .notifications, title: "No retail alerts",
                           subtitle: "Catalog prices are estimates. Nourlo does not send discount, stock or expiry alerts from them.") {
            OnboardingInfoPanel(symbol: "bell.slash.fill", rows: [
                ("tag", "Check current prices where you shop"),
                ("bell.slash", "Meal and logging reminders are not available yet"),
            ])
        } footer: {
            OnboardingNextButton(vm: vm, next: .favorites, title: "Continue",
                                 identifier: "onboarding.notifications.skip")
        }
    }
}

/// Icon badge plus a short list of plain facts.
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
    NavigationStack { NotificationPermissionView(vm: OnboardingViewModel()) }
}
