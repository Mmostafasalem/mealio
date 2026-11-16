import SwiftUI
import MessageUI

// MARK: - Morph Popover
//
// Port of Kokonut UI "Morph Popover" (kokonutui.com, MIT, @dorianbaffier).
// A pill button grows into the small form it opens and shrinks into a
// confirmation pill once sent. Its icon and label travel with the shape and
// become the panel's title. Timing matches the original: the shell morphs on a
// spring of 0.42 s with 0.14 bounce; contents fade in over 0.2 s on
// cubic-bezier(0.23, 1, 0.32, 1) and out in 0.1 s; the form body rises 4 pt out
// of a 4 pt blur 80 ms later; the sent pill fades in from a blur after 100 ms,
// its check draws in 0.3 s after 200 ms, and it folds back after 1.6 s.
// Reduce Motion: no spring, blur or slide, only cross-fades.
//
// Nourlo uses it for support feedback: Send hands the message to Mail, prefilled
// to the support address, so nothing leaves the phone without the person
// sending it themselves.

struct MorphPopover: View {
    var label: String = "Send feedback"
    var systemImage: String = "bubble.left"
    var placeholder: String = "What could be better? Tell us about a bug or an idea."
    var sentLabel: String = "Thanks for writing"
    /// Shown under the field.
    var footnote: String? = nil
    /// Hand off the text. Return true when it was sent (shows the thank-you pill),
    /// false to keep the panel open.
    let onSubmit: (String) async -> Bool

    enum Phase { case idle, open, sending, sent }

    @State private var phase: Phase = .idle
    @State private var text = ""
    @State private var checkDrawn = false
    @FocusState private var fieldFocused: Bool
    @Namespace private var morph
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var pillHeight: CGFloat = 36

    private var expanded: Bool { phase == .open || phase == .sending }

    private var morphAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.42, bounce: 0.14)
    }
    private static let fadeIn = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
    private static let fadeOut = Animation.easeOut(duration: 0.1)

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch phase {
            case .idle: idlePill.transition(contentTransition(delay: 0))
            case .open, .sending: panel.transition(contentTransition(delay: 0))
            case .sent: sentPill.transition(contentTransition(delay: 0.1, blur: true))
            }
        }
        .background(Color.surfaceElevated, in: shell)
        .overlay(shell.strokeBorder(Color.hairline, lineWidth: 0.7))
        .clipShape(shell)
        .shadow(color: .black.opacity(expanded ? 0.1 : 0.04), radius: expanded ? 18 : 2, y: expanded ? 8 : 1)
        .animation(morphAnimation, value: phase)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: phase) {
            switch phase {
            case .open:
                fieldFocused = true
            case .sent:
                checkDrawn = false
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.3)) { checkDrawn = true }
                try? await Task.sleep(for: .milliseconds(1400))
                guard !Task.isCancelled else { return }
                phase = .idle
            case .idle, .sending:
                break
            }
        }
    }

    private var shell: RoundedRectangle {
        RoundedRectangle(cornerRadius: expanded ? Radius.tile : pillHeight / 2, style: .continuous)
    }

    private func contentTransition(delay: Double, blur: Bool = false) -> AnyTransition {
        if reduceMotion { return .opacity }
        let insertion: AnyTransition = blur
            ? .modifier(active: BlurFade(radius: 4, opacity: 0), identity: BlurFade(radius: 0, opacity: 1))
            : .opacity
        return .asymmetric(insertion: insertion.animation(Self.fadeIn.delay(delay)),
                           removal: .opacity.animation(Self.fadeOut))
    }

    // MARK: Shapes

    private var title: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.labelSecondary)
                .matchedGeometryEffect(id: "icon", in: morph)
            Text(label)
                .foregroundStyle(Color.labelPrimary)
                .matchedGeometryEffect(id: "label", in: morph)
        }
        .font(.subheadline.weight(.medium))
    }

    private var idlePill: some View {
        Button {
            phase = .open
        } label: {
            title
                .padding(.horizontal, 14)
                .frame(height: pillHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityHint("Opens a short form. Send hands your message to Mail.")
        .accessibilityIdentifier("support.feedback")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            PanelBody(
                text: $text, placeholder: placeholder, footnote: footnote,
                sending: phase == .sending, focused: $fieldFocused,
                reduceMotion: reduceMotion,
                cancel: { phase = .idle },
                send: submit
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sentPill: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle().fill(Color.progress.opacity(0.18))
                CheckShape()
                    .trim(from: 0, to: checkDrawn || reduceMotion ? 1 : 0)
                    .stroke(Color.labelPrimary, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 16, height: 16)
            Text(sentLabel).foregroundStyle(Color.labelPrimary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .frame(height: pillHeight)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func submit() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, phase == .open else { return }
        phase = .sending
        Task { @MainActor in
            if await onSubmit(message) {
                text = ""
                phase = .sent
                AccessibilityNotification.Announcement(sentLabel).post()
            } else {
                phase = .open
            }
        }
    }
}

/// The form under the title: it rises out of a soft blur 80 ms after the shell opens.
private struct PanelBody: View {
    @Binding var text: String
    let placeholder: String
    let footnote: String?
    let sending: Bool
    var focused: FocusState<Bool>.Binding
    let reduceMotion: Bool
    let cancel: () -> Void
    let send: () -> Void

    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(4...6)
                .font(.subheadline)
                .foregroundStyle(Color.labelPrimary)
                .focused(focused)
                .disabled(sending)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityIdentifier("support.feedback.text")
            Divider().overlay(Color.hairline)
            HStack(spacing: Spacing.md) {
                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(minHeight: 44)
                    .disabled(sending)
                Button(action: send) {
                    HStack(spacing: 6) {
                        if sending { ProgressView().controlSize(.mini).tint(Color.surfaceElevated) }
                        Text(sending ? "Sending" : "Send")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.surfaceElevated)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .background(Color.brandPrimary.opacity(canSend ? 1 : 0.35),
                                in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityIdentifier("support.feedback.send")
            }
            .padding(.horizontal, 12)
            .background(Color.surfaceSecondary.opacity(0.5))
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 4)
        .blur(radius: shown || reduceMotion ? 0 : 4)
        .onAppear {
            withAnimation(Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2).delay(0.08)) { shown = true }
        }
    }

    private var canSend: Bool {
        !sending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.blur(radius: radius).opacity(opacity) }
}

/// The original's check, M4.75 8.25 7 10.5l4.25-4.75 on a 16-point grid.
private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 16
        var p = Path()
        p.move(to: CGPoint(x: 4.75 * s, y: 8.25 * s))
        p.addLine(to: CGPoint(x: 7 * s, y: 10.5 * s))
        p.addLine(to: CGPoint(x: 11.25 * s, y: 5.75 * s))
        return p
    }
}

// MARK: - Mail hand-off

/// Presents Mail's composer prefilled with the support address and message, and
/// reports whether the person actually sent it.
@MainActor
enum SupportMail {
    static func send(_ message: String) async -> Bool {
        let body = message + "\n\n—\n" + deviceSummary
        guard MFMailComposeViewController.canSendMail(),
              let presenter = topViewController() else {
            // No Mail account: open the mail link instead; the person finishes there.
            var parts = URLComponents()
            parts.scheme = "mailto"
            parts.path = Constants.Support.email
            parts.queryItems = [URLQueryItem(name: "subject", value: "Nourlo feedback"),
                                URLQueryItem(name: "body", value: body)]
            guard let url = parts.url else { return false }
            return await UIApplication.shared.open(url)
        }
        return await withCheckedContinuation { continuation in
            let composer = MFMailComposeViewController()
            let delegate = Delegate { sent in continuation.resume(returning: sent) }
            composer.mailComposeDelegate = delegate
            composer.setToRecipients([Constants.Support.email])
            composer.setSubject("Nourlo feedback")
            composer.setMessageBody(body, isHTML: false)
            objc_setAssociatedObject(composer, &Delegate.key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            presenter.present(composer, animated: true)
        }
    }

    private static var deviceSummary: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Nourlo \(version) (\(build)) · iOS \(UIDevice.current.systemVersion)"
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    private final class Delegate: NSObject, MFMailComposeViewControllerDelegate {
        nonisolated(unsafe) static var key: UInt8 = 0
        let done: (Bool) -> Void
        init(done: @escaping (Bool) -> Void) { self.done = done }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
            done(result == .sent || result == .saved)
        }
    }
}

#Preview("Morph Popover") {
    Form {
        Section("Privacy & Help") {
            MorphPopover(footnote: "Opens Mail to \(Constants.Support.email)") { _ in
                try? await Task.sleep(for: .milliseconds(700))
                return true
            }
        }
    }
}
