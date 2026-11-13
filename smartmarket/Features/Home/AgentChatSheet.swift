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
    /// Message count when the pending request started; only a reply past it animates in.
    @State private var liveReplyFloor: Int?
    /// Live reply height at the last auto-scroll; we follow it a line (≥ 12 pt) at a time.
    @State private var lastFollowHeight: CGFloat = 0
    /// Set when the person drags the conversation back; auto-scroll stops until they send again.
    @State private var userScrolledUp = false
    /// The send in flight, so the composer's Stop button can cancel it.
    @State private var chatTask: Task<Void, Never>?
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
                                let live = msg.id == liveReplyID
                                ChatBubble(message: msg, isLive: live,
                                           onFinished: {
                                               liveReplyFloor = nil
                                               // catch the last few points the per-line follow skipped
                                               if !userScrolledUp { proxy.scrollTo(msg.id.uuidString, anchor: .bottom) }
                                           },
                                           onHeightChange: { height in
                                               guard live, !userScrolledUp,
                                                     height - lastFollowHeight >= 12 else { return }
                                               lastFollowHeight = height
                                               proxy.scrollTo(msg.id.uuidString, anchor: .bottom)
                                           })
                                    .id(msg.id.uuidString)
                                    .accessibilityIdentifier(msg.role == "assistant" ? "chat.assistantReply" : "chat.userMessage")
                            }
                            if vm.isChatLoading {
                                // Same place as the reply bubble, which picks up from these dots.
                                GooThinkingBubble()
                                    .padding(.trailing, 60)
                                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    // iOS 17 has no onScrollGeometryChange: a finger pulling the content
                    // down means the person is reading back, so stop following the reply.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 12).onChanged { drag in
                            if drag.translation.height > 0 && !userScrolledUp { userScrolledUp = true }
                        }
                    )
                    .onChange(of: vm.chatMessages.count) {
                        guard !userScrolledUp else { return }
                        withAnimation(reduceMotion ? .none : .snappyValue) {
                            proxy.scrollTo(vm.chatMessages.last?.id.uuidString ?? "typing", anchor: .bottom)
                        }
                    }
                    .onChange(of: vm.isChatLoading) {
                        if vm.isChatLoading {
                            // The next assistant message after this point is the one that animates.
                            liveReplyFloor = vm.chatMessages.count
                            lastFollowHeight = 0
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
            // One surface for the whole sheet: header, conversation and composer.
            .background(Color.surfaceGrouped.ignoresSafeArea())
            .navigationTitle("Nourlo chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surfaceGrouped, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.frame(minHeight: 44)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.surfaceGrouped)
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

    /// The newest assistant message, while it is still streaming in. History renders statically.
    private var liveReplyID: UUID? {
        guard let floor = liveReplyFloor, let last = vm.chatMessages.last,
              last.role == "assistant", vm.chatMessages.count > floor else { return nil }
        return last.id
    }

    private var mood: MascotMood {
        if vm.isChatLoading { return .thinking }
        if vm.lastChatFailed { return .help }
        return vm.chatMessages.last?.role == "assistant" ? .celebrate : .idle
    }

    private var assistantHeader: some View {
        HStack(spacing: Spacing.sm) {
            // The small bowl only joins once a conversation is under way; the
            // empty state already shows a large one.
            if !vm.chatMessages.isEmpty || vm.isChatLoading {
                MascotGuideView(mood: mood, size: 32)
            }
            Text(vm.assistantModeLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.labelSecondary)
                .accessibilityIdentifier("chat.assistantMode")
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Spacing.lg)
    }

    private var emptyPrompt: some View {
        VStack(spacing: Spacing.md) {
            MascotGuideView(size: 108)
            Text("What would help today?")
                .font(.title2.weight(.semibold))
            Text(needsOnlineSetup
                 ? "Online AI needs a quick setup before it can answer. You can still write your question first."
                 : "Pick a question below or type your own, then send.")
                .font(.subheadline)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if needsOnlineSetup { onlineSetupButton }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                prompt("Plan a simple meal", text: "Suggest a simple meal using the foods I have.")
                prompt("Build a grocery list", text: "Help me build a grocery list for my next few meals.")
                prompt("Understand food logging", text: "How can I estimate a portion before logging food?")
            }
        }
        .padding(.top, Spacing.lg)
        .padding(.horizontal, Spacing.xl)
    }

    private var needsOnlineSetup: Bool {
        OwnerAITestConfiguration.current == nil && (!AIAccountService.shared.isSignedIn || !onlineAISharingConsent)
    }

    private var onlineSetupButton: some View {
        // A bordered-prominent button took the brand tint as its fill and drew
        // white text on it, which is invisible in dark mode.
        Button {
            inputFocused = false
            showOnlineSetup = true
        } label: {
            Label("Set up online AI", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.onAccent)
                .padding(.horizontal, Spacing.xl)
                .frame(minHeight: 44)
                .background(Color.dullPink, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(ScalePressStyle())
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
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(Color.labelTertiary)
            }
            .foregroundStyle(Color.labelPrimary)
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(vm.isChatLoading)
        .accessibilityHint("Fills the message field. Review it before sending to online AI.")
    }

    /// The backend clamps a chat message to 2,000 characters (`handle_agent_chat`).
    static let messageLimit = 2000

    private var inputBar: some View {
        PromptBox(
            text: $localInput,
            placeholder: "Ask about meals or groceries…",
            isLoading: vm.isChatLoading,
            canSend: canSend,
            limit: Self.messageLimit,
            focused: $inputFocused,
            sendIdentifier: "chat.send",
            onSend: send,
            onStop: stopReply
        )
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    /// Cancels the request in flight: the model's task sees the cancellation and
    /// drops the reply, and `isChatLoading` turns off when it returns.
    private func stopReply() {
        chatTask?.cancel()
        chatTask = nil
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
        userScrolledUp = false   // sending means they are back at the conversation's end
        chatTask = Task { await vm.sendChatMessage() }
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
    /// The newest reply: it opens out of the thinking dots and streams in.
    var isLive = false
    var onFinished: () -> Void = {}
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var isUser: Bool { message.role == "user" }

    var body: some View {
        Group {
            if isLive && !isUser {
                GooThinkingBubble(isAnswered: true, accessibilityText: message.content) {
                    StreamingReplyText(text: message.content, delay: 0.6, onFinished: onFinished)
                        .modifier(BubbleText(isUser: false))
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
            } else {
                Text(message.content)
                    .modifier(BubbleText(isUser: isUser))
                    .background(
                        isUser ? Color.dullPink : Color.surfaceElevated,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
        }
        .padding(isUser ? .leading : .trailing, 60)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.horizontal, Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "You: \(message.content)" : "Online assistant: \(message.content)")
    }
}

private struct BubbleText: ViewModifier {
    let isUser: Bool
    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .foregroundStyle(isUser ? Color.onAccent : Color.labelPrimary)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
    }
}
