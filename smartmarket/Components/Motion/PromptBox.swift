import SwiftUI

// MARK: - Prompt box
//
// Port of designbookmark.com/motion "Prompt Box" (prompt-box/prompt.js).
// The text box grows with the text on a spring (420 34, up to five lines), the
// Send button turns into a Stop button while a reply loads (520 30: the arrow
// shrinks and turns away as the stop square grows in), and a status line opens
// above the text (380 30) while it thinks, or to say it stopped. Return sends;
// a pasted line break stays. The button is dim until there is something to send.
// No autoplay: the original's demo typing is left out.
//
// With a `limit`, a `LetterLimitRing` sits by the button and anything past the
// limit falls out of the box as letters (see LetterLimitRing.swift).
//
// Accessibility: the real TextField stays the field (label = placeholder), the
// button is one element whose label follows its state. Reduce Motion: the
// springs are critically damped by the engine; the status dot does not pulse.

struct PromptBox: View {
    @Binding var text: String
    let placeholder: String
    var isLoading: Bool
    /// Whether the current text may be sent (e.g. not blank).
    var canSend: Bool
    var limit: Int? = nil
    var focused: FocusState<Bool>.Binding
    var sendIdentifier: String? = nil
    var thinkingLabel: String = "Thinking"
    var stoppedLabel: String = "Stopped"
    let onSend: () -> Void
    /// Cancels the reply in flight. Nil: the button shows progress and is disabled while loading.
    var onStop: (() -> Void)? = nil

    @State private var model = PromptBoxModel()
    @State private var limitModel = LetterLimitModel()
    @State private var boxSize: CGSize = .zero
    @ScaledMetric(relativeTo: .body) private var button: CGFloat = 32
    @ScaledMetric(relativeTo: .subheadline) private var statusHeight: CGFloat = 26

    private var ready: Bool { canSend || (isLoading && onStop != nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            status
            HStack(alignment: .bottom, spacing: 10) {
                field
                // The ring only appears as the limit gets close; at a few
                // characters of a long limit it is just a stray dot.
                if let limit, text.count * 5 >= limit * 4 {
                    LetterLimitRing(model: limitModel, count: text.count, limit: limit)
                        .padding(.bottom, (button - 20) / 2 + 6)
                        .transition(.opacity)
                }
                sendButton
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { boxSize = $0 }
        .overlay {
            if limit != nil {
                LetterLimitPile(model: limitModel,
                                origin: CGPoint(x: max(40, boxSize.width - button - 44), y: boxSize.height - 22))
            }
        }
        .onChange(of: text, initial: true) { old, new in
            // Return sends; it only adds a line break when pasted with other text.
            if new == old + "\n" {
                text = old
                if canSend && !isLoading { onSend() }
                return
            }
            if let limit {
                let kept = limitModel.enforce(new, limit: limit)
                if kept != new { text = kept }
            }
        }
        .onChange(of: isLoading, initial: true) { _, loading in model.loading(loading) }
        .onDisappear { model.stop(); limitModel.stop() }
    }

    // MARK: Parts

    private var status: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.stopped ? Color.labelTertiary : Color.brandPrimary)
                .frame(width: 8, height: 8)
            Text(model.stopped ? stoppedLabel : thinkingLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(1)
        }
        .frame(height: statusHeight * CGFloat(max(0, model.statusOpen)), alignment: .center)
        .opacity(motionClamp(model.statusOpen, 0, 1))
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityHidden(model.statusOpen < 0.5)
    }

    private var field: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(.body)
            .foregroundStyle(Color.labelPrimary)
            .lineLimit(1...5)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled()
            .submitLabel(.send)
            .onSubmit { if canSend { onSend() } }
            .focused(focused)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.fit($0) }
            .frame(height: model.height > 0 ? model.height : nil, alignment: .top)
            .clipped()
            .padding(.vertical, (button - 22) / 2 + 2)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var sendButton: some View {
        Button {
            if isLoading { model.markStopped(); onStop?() } else { onSend() }
        } label: {
            let m = motionClamp(model.morph, 0, 1.2)
            ZStack {
                Circle().fill(ready ? Color.brandPrimary : Color.labelTertiary.opacity(0.25))
                Image(systemName: "arrow.up")
                    .font(.system(size: button * 0.5, weight: .bold))
                    .scaleEffect(max(0, 1 - m))
                    .rotationEffect(.degrees(m * 90))
                RoundedRectangle(cornerRadius: button * 0.08, style: .continuous)
                    .frame(width: button * 0.32, height: button * 0.32)
                    .scaleEffect(max(0, m))
                if isLoading && onStop == nil {
                    ProgressView().tint(Color.surface)
                }
            }
            .foregroundStyle(ready ? Color.surface : Color.labelSecondary)
            .frame(width: button, height: button)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.2), value: ready)
        }
        .buttonStyle(ScalePressStyle())
        .disabled(!ready)
        .accessibilityLabel(isLoading ? "Stop reply" : "Send message")
        .accessibilityIdentifier(sendIdentifier ?? "promptBox.send")
    }
}

// MARK: - Model (prompt.js)

@MainActor @Observable
final class PromptBoxModel {
    private(set) var height: CGFloat = 0
    private(set) var statusOpen: Double = 0
    private(set) var morph: Double = 0
    private(set) var stopped = false

    @ObservationIgnored private var H = MotionSpring(0, 420, 34)
    @ObservationIgnored private var SH = MotionSpring(0, 380, 30)
    @ObservationIgnored private var M = MotionSpring(0, 520, 30)
    @ObservationIgnored private var measured = false
    @ObservationIgnored private var closeTimer: Int?
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in
            guard let self else { return }
            H.step(dt); SH.step(dt); M.step(dt)
        }
        clock.render = { [weak self] in self?.render() }
    }

    /// The field's natural height changed.
    func fit(_ h: CGFloat) {
        guard h > 0 else { return }
        if !measured { measured = true; H.snap(Double(h)); render(); return }
        guard abs(H.t - Double(h)) > 0.5 else { return }
        H.t = Double(h)
        clock.start()
    }

    func loading(_ on: Bool) {
        if let closeTimer { clock.cancel(closeTimer); self.closeTimer = nil }
        if on {
            stopped = false
            M.t = 1; SH.t = 1
        } else {
            M.t = 0
            // A stop says so for a moment; a reply closes the line at once (the reply is in the thread).
            if stopped {
                closeTimer = clock.after(1.6) { [weak self] in
                    self?.closeTimer = nil
                    self?.SH.t = 0
                }
            } else {
                SH.t = 0
            }
        }
        clock.start()
    }

    func markStopped() { stopped = true }

    func stop() {
        clock.cancelAllTimers()
        closeTimer = nil
        H.snap(H.t); SH.snap(SH.t); M.snap(M.t)
        render()
        clock.stop()
    }

    private func render() {
        height = CGFloat(H.x)
        statusOpen = SH.x
        morph = M.x
        if clock.isRunning, closeTimer == nil, H.isSettled(within: MotionSpring.points), SH.isSettled, M.isSettled {
            H.snap(H.t); SH.snap(SH.t); M.snap(M.t)
            height = CGFloat(H.x); statusOpen = SH.x; morph = M.x
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Prompt box") {
    struct Demo: View {
        @State private var text = ""
        @State private var loading = false
        @FocusState private var focused: Bool
        var body: some View {
            VStack {
                Spacer()
                Text(loading ? "Waiting for a reply…" : "Type, then send. Tap the stop square to cancel.")
                    .font(.footnote).foregroundStyle(Color.labelSecondary)
                PromptBox(text: $text, placeholder: "Ask about meals or groceries…", isLoading: loading,
                          canSend: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !loading,
                          limit: 120, focused: $focused,
                          onSend: {
                              text = ""
                              loading = true
                              Task { try? await Task.sleep(for: .seconds(2)); loading = false }
                          },
                          onStop: { loading = false })
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.md)
            }
            .background(Color.surface)
        }
    }
    return Demo()
}
