import SwiftUI

struct NotificationPermissionView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(vm: vm, step: .notifications, title: "No retail alerts",
                           subtitle: "Catalog prices are estimates. Nourlo does not send discount, nearby stock or expiry alerts from them.") {
            OnboardingInfoPanel(symbol: "bell.slash.fill", rows: [
                ("tag", "Check current prices and availability with the store"),
                ("bell.slash", "Meal and logging reminders are not available yet"),
            ])
        } footer: {
            OnboardingNextButton(vm: vm, next: .favorites, title: "Continue",
                                 identifier: "onboarding.notifications.skip")
        }
    }
}

#Preview {
    NavigationStack { NotificationPermissionView(vm: OnboardingViewModel()) }
}
