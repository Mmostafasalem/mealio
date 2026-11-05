import SwiftUI
import AuthenticationServices

struct AIAccountSection: View {
    @State private var account = AIAccountService.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            if account.isSignedIn {
                Label("Signed in with Apple", systemImage: "checkmark.seal")
                if let usage = account.allowance {
                    LabeledContent("AI credits remaining", value: "\(usage.remaining) of \(usage.limit)")
                        .accessibilityIdentifier("profile.aiRemaining")
                    if let reset = usage.resetDate {
                        Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote).foregroundStyle(Color.labelSecondary)
                    }
                    Text("Meal plan: \(usage.mealPlanCost) credits. Chat, recipes and other suggestions: \(usage.shortRequestCost) credit each. Automatic online plan updates also count.")
                        .font(.footnote).foregroundStyle(Color.labelSecondary)
                }
                Button("Refresh allowance") { Task { try? await account.refreshAllowance() } }
                Button("Sign out") { Task { await account.signOut() } }
                    .accessibilityIdentifier("profile.aiSignOut")
            } else {
                if account.hasAccount {
                    Text("Your online account is retained after sign-out. Sign in again to use its allowance or delete it with Delete All Data.")
                        .font(.footnote).foregroundStyle(Color.labelSecondary)
                }
                Text("Sign in to keep the same daily AI allowance across your devices.")
                    .font(.subheadline)
                SignInWithAppleButton(.signIn) { request in
                    account.configure(request)
                } onCompletion: { result in
                    Task { await account.complete(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .disabled(!account.canStartSignIn)
                .accessibilityIdentifier("profile.appleSignIn")
            }
            if account.isWorking { ProgressView("Checking AI account…") }
            if let message = account.message {
                Text(message).font(.footnote).foregroundStyle(Color.labelSecondary)
                if !account.isSignedIn {
                    Button("Retry sign-in setup") { Task { await account.prepare() } }
                }
            }
        } header: {
            Text("AI allowance")
        } footer: {
            Text("Your allowance resets daily at midnight UTC; the time above is shown in your time zone. Signing in does not enable AI sharing. Local tracking works without an account. Personal allowances share Mealio’s overall provider capacity, so temporary service limits can still occur. Use Delete All Data to delete your online account; sign-out alone keeps it.")
        }
        .task { await account.prepare() }
    }
}
