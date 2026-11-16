import SwiftUI

// MARK: - Command button
//
// Port of designbookmark.com/motion "Command button" (command-button.tsx).
// A quiet pill with a magnifier. Tap it and the pill stretches open into a
// search field. The Close chip, a tap outside, or leaving the field empty
// folds it back.
//
// Motion, from the original:
// - Press: spring stiffness 520, damping 34, mass 0.6, scale 0.97 while held.
//   The shared engine is unit-mass, so k = 520 / 0.6 and c = 34 / 0.6.
// - Open: layout spring stiffness 300, damping 34 - 20 * bounce/100, bounce 30.
// - Swap: 0.18 s cubic-bezier(.23, 1, .32, 1) with a 4 pt blur; the entering
//   side waits 0.06 s.

enum CommandButtonMotion {
    static let press = MotionTokens.Preset(k: 520 / 0.6, c: 34 / 0.6)
    static let bounce: Double = 30
    static var open: Animation {
        .interpolatingSpring(stiffness: 300, damping: 34 - (motionClamp(bounce, 0, 100) / 100) * 20)
    }
    static let swapCurve = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
    static let swapDelay: Double = 0.06
    static let swapBlur: CGFloat = 4
}

struct CommandButton: View {

    /// What the folded pill shows.
    enum Idle {
        /// A magnifier and the label.
        case label
        /// Only the magnifier, for narrow rows.
        case icon
    }

    @Binding var isOpen: Bool
    @Binding var query: String
    var label: String = "Search"
    var placeholder: String = "Find a screen or action"
    var idle: Idle = .label
    /// Accessibility identifiers for the folded button and the open field (UI tests).
    var buttonIdentifier: String? = nil
    var fieldIdentifier: String? = nil
    let onSubmit: () -> Void

    @State private var press = CommandPressModel()
    @State private var focusTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isOpen: Binding<Bool>,
         query: Binding<String>,
         label: String = "Search",
         placeholder: String = "Find a screen or action",
         idle: Idle = .label,
         buttonIdentifier: String? = nil,
         fieldIdentifier: String? = nil,
         onSubmit: @escaping () -> Void) {
        _isOpen = isOpen
        _query = query
        self.label = label
        self.placeholder = placeholder
        self.idle = idle
        self.buttonIdentifier = buttonIdentifier
        self.fieldIdentifier = fieldIdentifier
        self.onSubmit = onSubmit
    }

    var body: some View {
        StretchLayout(progress: isOpen ? 1 : 0) {
            idleContent.hidden().accessibilityHidden(true)
            ZStack {
                if isOpen {
                    field.transition(swap)
                } else {
                    button.transition(swap)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 44)
        .background(Color.surfaceElevated, in: Capsule(style: .continuous))
        .clipShape(Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
        .scaleEffect(press.scale)
        .foregroundStyle(Color.labelPrimary)
        .onChange(of: isOpen) { _, nowOpen in
            focusTask?.cancel()
            focusTask = nil
            if nowOpen { focusField() }
        }
        .onAppear { if isOpen { focusField() } }
        .onDisappear { focusTask?.cancel(); focusTask = nil }
    }

    // MARK: Parts

    private var button: some View {
        Button { open() } label: { idleContent }
            .buttonStyle(CommandPressStyle { down in press.press(down) })
            .accessibilityLabel(label)
            .accessibilityHint("Opens a search field.")
            .accessibilityIdentifier(buttonIdentifier ?? "commandButton.open")
    }

    private var idleContent: some View {
        HStack(spacing: idle == .icon ? 0 : 6) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.labelSecondary)
            if idle == .label {
                Text(label).font(.subheadline.weight(.medium)).lineLimit(1)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.leading, idle == .icon ? 0 : 14)
        .padding(.trailing, idle == .icon ? 0 : 16)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Capsule(style: .continuous))
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.labelSecondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $query)
                .font(.body)
                .foregroundStyle(Color.labelPrimary)
                .focused($fieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .onSubmit(onSubmit)
                .accessibilityLabel(placeholder)
                .accessibilityIdentifier(fieldIdentifier ?? "commandButton.field")
                .frame(minWidth: 0, maxWidth: .infinity)
            Button { close() } label: { CommandChip(label: "Close") }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Close search")
                .accessibilityIdentifier("commandButton.close")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .onChange(of: fieldFocused) { _, focused in
            // Leaving the field empty folds it back.
            if !focused && isOpen && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { close() }
        }
    }

    private var swap: AnyTransition {
        guard !reduceMotion else { return .opacity.animation(.easeOut(duration: 0.12)) }
        return .asymmetric(
            insertion: .modifier(active: BlurFade(radius: CommandButtonMotion.swapBlur, opacity: 0),
                                 identity: BlurFade(radius: 0, opacity: 1))
                .animation(CommandButtonMotion.swapCurve.delay(CommandButtonMotion.swapDelay)),
            removal: .modifier(active: BlurFade(radius: CommandButtonMotion.swapBlur, opacity: 0),
                               identity: BlurFade(radius: 0, opacity: 1))
                .animation(CommandButtonMotion.swapCurve))
    }

    // MARK: Actions

    private func open() {
        guard !isOpen else { return }
        withAnimation(reduceMotion ? nil : CommandButtonMotion.open) { isOpen = true }
    }

    private func close() {
        guard isOpen else { return }
        focusTask?.cancel()
        focusTask = nil
        // Same update as the fold, so the focus-lost handler already sees it closed.
        fieldFocused = false
        withAnimation(reduceMotion ? nil : CommandButtonMotion.open) {
            isOpen = false
            query = ""
        }
    }

    /// Focus as the field starts to appear (after the swap delay). Cancelled on
    /// close so a quick open-close can't refocus.
    private func focusField() {
        let delay = reduceMotion ? 0 : CommandButtonMotion.swapDelay
        focusTask = Task { @MainActor in
            do {
                if delay > 0 {
                    try await Task.sleep(for: .seconds(delay))
                } else {
                    // Let the field join the hierarchy before focusing it.
                    await Task.yield()
                }
                try Task.checkCancellation()
            } catch {
                return
            }
            guard isOpen else { return }
            fieldFocused = true
        }
    }
}

// MARK: - Chip

/// The small rounded "Close" chip inside the open field.
struct CommandChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.labelSecondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Press spring (shared engine)

@MainActor @Observable
final class CommandPressModel {
    private(set) var scale: Double = 1
    @ObservationIgnored private var spring = MotionSpring(1, CommandButtonMotion.press)
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.spring.step(dt) }
        clock.render = { [weak self] in
            guard let self else { return }
            if spring.isSettled {
                spring.snap(spring.t)
                clock.stop()
            }
            scale = spring.x
        }
    }

    func press(_ down: Bool) {
        spring.t = down && !MotionSettings.reduceMotion ? 0.97 : 1
        clock.start()
    }
}

private struct CommandPressStyle: ButtonStyle {
    let onPress: (Bool) -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, down in onPress(down) }
    }
}

// MARK: - Swap transition

private struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}

// MARK: - Stretch layout
//
// Two children: a hidden copy of the folded pill (its ideal size is the idle
// width) and the live content. `progress` animates with the open spring, so the
// pill stretches from its idle width to the full proposed width.

private struct StretchLayout: Layout {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let idle = subviews.first?.sizeThatFits(.unspecified) ?? CGSize(width: 44, height: 44)
        let available = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idle.width
        let target = max(idle.width, available)
        let width = idle.width + (target - idle.width) * CGFloat(progress)
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? idle.height
        return CGSize(width: min(width, max(available, idle.width)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}

// MARK: - Previews

#Preview("Command button") {
    struct Demo: View {
        @State private var open = false
        @State private var query = ""
        var body: some View {
            VStack(spacing: Spacing.lg) {
                HStack {
                    Spacer(minLength: 0)
                    CommandButton(isOpen: $open, query: $query) { open = false; query = "" }
                        .layoutPriority(1)
                }
                HStack {
                    Spacer(minLength: 0)
                    CommandButton(isOpen: .constant(false), query: .constant(""), idle: .icon) {}
                }
                Text(open ? "Open: \(query)" : "Folded").font(.footnote).foregroundStyle(Color.labelSecondary)
            }
            .padding(Spacing.lg)
            .frame(maxHeight: .infinity)
            .background(Color.surfaceGrouped)
        }
    }
    return Demo()
}
