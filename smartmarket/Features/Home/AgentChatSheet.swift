import SwiftUI

/// Conversational assistant sheet. Keystrokes are held in a purely local
/// `@State` buffer so background model tasks never disturb the text field.
struct AgentChatSheet: View {
    @Bindable var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    @State private var localInput: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Spacing.md) {
                            if vm.chatMessages.isEmpty { emptyPrompt }
                            ForEach(vm.chatMessages) { msg in
                                ChatBubble(message: msg).id(msg.id.uuidString)
                            }
                            if vm.isChatLoading {
                                HStack { TypingIndicator(); Spacer() }
                                    .padding(.horizontal, Spacing.lg)
                                    .id("typing")
                            }
                        }
                        .padding(.vertical, Spacing.lg)
                    }
                    .onChange(of: vm.chatMessages.count) {
                        withAnimation(.smoothCard) {
                            proxy.scrollTo(vm.chatMessages.last?.id.uuidString ?? "typing", anchor: .bottom)
                        }
                    }
                    .onChange(of: vm.isChatLoading) {
                        if vm.isChatLoading {
                            withAnimation(.smoothCard) { proxy.scrollTo("typing", anchor: .bottom) }
                        }
                    }
                }

                Divider()
                inputBar
            }
            .navigationTitle("Mealio Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var emptyPrompt: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44))
                .foregroundStyle(Color.brandPrimary)
            Text("Ask me anything about your meals, deals, or nutrition goals.")
                .font(.subheadline)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, Spacing.xxl)
    }

    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Ask about meals, deals, nutrition…", text: $localInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.brandPrimary : Color.secondary)
            }
            .accessibilityLabel("Send message")
            .disabled(!canSend)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private var canSend: Bool {
        !localInput.trimmingCharacters(in: .whitespaces).isEmpty && !vm.isChatLoading
    }

    private func send() {
        let cleaned = localInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        vm.chatInput = cleaned
        localInput = ""
        Task { await vm.sendChatMessage() }
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
        .accessibilityLabel(isUser ? "You: \(message.content)" : "Agent: \(message.content)")
    }
}

// MARK: - Typing indicator

private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.3 : 0.8)
                    .opacity(animating ? 1.0 : 0.4)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.18),
                               value: animating)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { animating = true }
        .accessibilityLabel("Agent is typing")
    }
}
