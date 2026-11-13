import SwiftUI
import UIKit

/// Conversational assistant sheet. Keystrokes are held in a purely local
/// `@State` buffer so background model tasks never disturb the text field.
struct AgentChatSheet: View {
    @Bindable var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var localInput: String = ""
    @State private var pendingOwnerMessage: String?
    @State private var showOwnerConsent = false
    @State private var showOnlineSetup = false
    @AppStorage("ownerAISharingConsent_v1") private var ownerAISharingConsent = false
    @AppStorage("aiSharingConsent_v1") private var onlineAISharingConsent = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                assistantHeader
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Spacing.md) {
                            if vm.chatMessages.isEmpty { emptyPrompt }
                            ForEach(vm.chatMessages) { msg in
                                ChatBubble(message: msg).id(msg.id.uuidString)
                                    .accessibilityIdentifier(msg.role == "assistant" ? "chat.assistantReply" : "chat.userMessage")
                            }
                            if vm.isChatLoading {
                                HStack(spacing: Spacing.sm) {
                                    MascotGuideView(mood: .thinking, size: 36)
                                    Text("Waiting for online AI…")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.labelSecondary)
                                    Spacer(minLength: 0)
                                }
                                    .padding(.horizontal, Spacing.lg)
                                    .id("typing")
                            }
                            if let notice = vm.chatNotice, !notice.isEmpty {
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    Label(notice, systemImage: "exclamationmark.bubble")
                                        .font(.subheadline)
                                        .accessibilityIdentifier("chat.notice")
                                    if needsOnlineSetup { onlineSetupButton }
                                }
                                .padding(Spacing.lg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.tile))
                                .padding(.horizontal, Spacing.lg)
                                .id("notice")
                            }
                        }
                        .padding(.vertical, Spacing.lg)
                    }
                    .onChange(of: vm.chatMessages.count) {
                        withAnimation(reduceMotion ? .none : .snappyValue) {
                            proxy.scrollTo(vm.chatMessages.last?.id.uuidString ?? "typing", anchor: .bottom)
                        }
                    }
                    .onChange(of: vm.isChatLoading) {
                        if vm.isChatLoading {
                            withAnimation(reduceMotion ? .none : .snappyValue) { proxy.scrollTo("typing", anchor: .bottom) }
                        }
                    }
                    .onChange(of: vm.chatNotice) { _, notice in
                        if notice != nil {
                            withAnimation(reduceMotion ? .none : .snappyValue) { proxy.scrollTo("notice", anchor: .bottom) }
                        }
                    }
                }

                Divider()
                inputBar
            }
            .navigationTitle("Nourlo chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.frame(minHeight: 44)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showOnlineSetup) { ChatAISetupView() }
        .alert("Use AI on your Mac?", isPresented: $showOwnerConsent) {
            Button("Allow and send") {
                ownerAISharingConsent = true
                if let message = pendingOwnerMessage { sendPrepared(message) }
                pendingOwnerMessage = nil
            }
            Button("Not now", role: .cancel) { pendingOwnerMessage = nil }
        } message: {
            Text("AI requests can include your message, nutrition goals, body measurements, food preferences, shopping items, owned food quantities and remaining daily targets. This private test sends them \(OwnerAITestConfiguration.current?.transportDescription ?? "to your Mac") to the model on your Mac. Keep the Mac awake. You can turn sharing off in Profile.")
        }
        .onChange(of: vm.chatNotice) { _, notice in
            if UIAccessibility.isVoiceOverRunning, let notice, !notice.isEmpty {
                UIAccessibility.post(notification: .announcement, argument: notice)
            }
        }
    }

    private var mood: MascotMood {
        if vm.isChatLoading { return .thinking }
        if vm.lastChatFailed { return .help }
        return vm.chatMessages.last?.role == "assistant" ? .celebrate : .idle
    }

    private var assistantHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                MascotGuideView(mood: mood, size: 36)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(vm.assistantModeLabel).font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("chat.assistantMode")
                    Text("Tap the bowl for local app help.")
                        .font(.footnote).foregroundStyle(Color.labelSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.surface)
    }

    private var emptyPrompt: some View {
        VStack(spacing: Spacing.md) {
            MascotGuideView(size: 108)
            Text("What would help today?")
                .font(.title2.weight(.semibold))
            Text("Your bowl has local tips. For online AI, choose a question below, edit it, then tap Send.")
                .font(.subheadline)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)

            if needsOnlineSetup { onlineSetupButton }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                prompt("Plan a simple meal", text: "Suggest a simple meal using the foods I have.")
                prompt("Build a grocery list", text: "Help me build a grocery list for my next few meals.")
                prompt("Understand food logging", text: "How can I estimate a portion before logging food?")
            }
        }
        .padding(.top, Spacing.lg)
        .padding(.horizontal, Spacing.xxl)
    }

    private var needsOnlineSetup: Bool {
        OwnerAITestConfiguration.current == nil && (!AIAccountService.shared.isSignedIn || !onlineAISharingConsent)
    }

    private var onlineSetupButton: some View {
        Button("Set up online AI") {
            inputFocused = false
            showOnlineSetup = true
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("chat.setup")
    }

    private func prompt(_ title: String, text: String) -> some View {
        Button {
            localInput = text
            inputFocused = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(title).font(.subheadline)
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.to.line").font(.caption)
            }
            .foregroundStyle(Color.labelPrimary)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.chip))
        }
        .buttonStyle(.plain)
        .disabled(vm.isChatLoading)
        .accessibilityHint("Fills the message field. Review it before sending to online AI.")
    }

    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Ask about meals or groceries…", text: $localInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                .focused($inputFocused)
                .frame(minHeight: 44)
                .submitLabel(.send)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.brandPrimary : Color.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Send message")
            .accessibilityIdentifier("chat.send")
            .disabled(!canSend)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private var canSend: Bool {
        !localInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isChatLoading
    }

    private func send() {
        let cleaned = localInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        if OwnerAITestConfiguration.current != nil && !ownerAISharingConsent {
            pendingOwnerMessage = cleaned
            showOwnerConsent = true
            return
        }
        // Keep the typed text when sign-in or consent is missing.
        if needsOnlineSetup {
            inputFocused = false
            showOnlineSetup = true
            return
        }
        sendPrepared(cleaned)
    }

    private func sendPrepared(_ cleaned: String) {
        vm.chatInput = cleaned
        localInput = ""
        Task { await vm.sendChatMessage() }
    }
}

private struct ChatAISetupView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("aiSharingConsent_v1") private var sharingConsent = false

    var body: some View {
        NavigationStack {
            Form {
                AIAccountSection()
                Section {
                    Toggle("Allow online AI suggestions", isOn: $sharingConsent)
                        .accessibilityIdentifier("chat.aiConsent")
                    NavigationLink("Privacy Policy") { LegalDocumentView(resource: "Privacy", title: "Privacy Policy") }
                } header: {
                    Text("AI sharing")
                } footer: {
                    Text("When enabled, online AI requests send relevant body measurements, goals, dietary preferences, shopping items, owned food quantities, remaining daily targets and messages through Nourlo's backend to Groq. Account access and sharing are separate choices. Turning sharing off stops future AI requests. Read the Privacy Policy before enabling.")
                }
            }
            .navigationTitle("Online AI")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.accessibilityIdentifier("chat.setupDone")
            } }
        }
    }
}
// MARK: - Chat bubble

private struct ChatBubble: View {
    let message: ChatMessage
    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            Text(message.content)
                .font(.subheadline)
                .foregroundStyle(isUser ? Color.onAccent : Color.labelPrimary)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(
                    isUser ? Color.dullPink : Color.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "You: \(message.content)" : "Online assistant: \(message.content)")
    }
}
