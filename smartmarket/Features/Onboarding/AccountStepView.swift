import SwiftUI
import AuthenticationServices

// MARK: - Online AI account (only while the backend offers online AI)

/// "Use online AI?": continue free as a guest, sign in with Apple (only when the
/// server offers it), or go on without an account. Everything else in Nourlo works
/// without one. Choosing an account also turns on AI sharing, which the screen says
/// plainly; "Not now" leaves both off. Both can be changed in Profile.
struct AccountStepView: View {

    @Bindable var vm: OnboardingViewModel
    @State private var account = AIAccountService.shared
    @AppStorage("aiSharingConsent_v1") private var sharingConsent = false
    @Environment(\.colorScheme) private var colorScheme
    /// Service messages are shown only after the person tried to sign in.
    @State private var tried = false

    var body: some View {
        OnboardingScaffold(vm: vm, step: .account, title: "Chat with Nourlo?",
                           subtitle: "Online AI answers questions and writes recipes. Everything else works without an account.") {
            OnboardingOptionList {
                if account.isSignedIn {
                    SetupCard {
                        Label(account.isGuest ? "Free guest account ready" : "Signed in with Apple", systemImage: "checkmark.seal.fill")
                            .font(.headline).foregroundStyle(Color.labelPrimary)
                        if let usage = account.allowance {
                            Text("\(usage.remaining) AI credits today. A chat message or an AI recipe costs \(usage.shortRequestCost)." as String)
                                .font(.subheadline).foregroundStyle(Color.labelSecondary)
                        }
                    }
                    .accessibilityIdentifier("onboarding.account.ready")
                } else {
                    if account.guestAvailable {
                        OnboardingOptionRow(symbol: "person.crop.circle.badge.checkmark", title: "Continue free as a guest",
                                            subtitle: "No sign-up, free daily AI credits",
                                            isSelected: false) {
                            Task {
                                tried = true
                                await account.continueAsGuest()
                                if account.isSignedIn { sharingConsent = true }
                            }
                        }
                        .disabled(account.isWorking)
                        .accessibilityIdentifier("onboarding.account.guest")
                    }
                    if account.appleAvailable {
                        SignInWithAppleButton(.signIn) { request in
                            account.configure(request)
                        } onCompletion: { result in
                            Task {
                                tried = true
                                await account.complete(result)
                                if account.isSignedIn { sharingConsent = true }
                            }
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .disabled(!account.canStartSignIn)
                        .accessibilityIdentifier("onboarding.account.apple")
                    }
                    if account.isWorking { ProgressView("Setting up…").frame(maxWidth: .infinity) }
                    if tried, let message = account.message {
                        Text(message).font(.footnote).foregroundStyle(Color.labelSecondary)
                    }
                }
                Text("With an account, your messages and the food and goal details a question needs go through Nourlo's server to Groq, an AI provider. Turn this off or delete the account any time in Profile.")
                    .font(.footnote).foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .task { if !account.isSignedIn { await account.prepare() } }
        } footer: {
            if account.isSignedIn {
                OnboardingNextButton(vm: vm, from: .account, identifier: "onboarding.account.next")
            } else {
                Button { vm.continueFrom(.account) } label: {
                    Text("Not now").font(.headline).foregroundStyle(Color.labelPrimary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(ScalePressStyle())
                .accessibilityIdentifier("onboarding.account.skip")
            }
        }
    }
}
