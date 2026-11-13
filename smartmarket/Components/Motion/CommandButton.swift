import SwiftUI

// MARK: - Command button
//
// Port of designbookmark.com/motion "Command button" (command-button.tsx).
// A quiet pill that carries its own shortcut keys. Tap it (or press the keys)
// and the pill stretches open into a search field. The Close chip, a tap
// outside, or leaving the field empty folds it back.
//
// Motion, from the original:
// - Press: spring stiffness 520, damping 34, mass 0.6, scale 0.97 while held.
//   The shared engine is unit-mass, so k = 520 / 0.6 and c = 34 / 0.6.
// - Open: layout spring stiffness 300, damping 34 - 20 * bounce/100, bounce 30.
// - Swap: 0.18 s cubic-bezier(.23, 1, .32, 1) with a 4 pt blur; the entering
//   side waits 0.06 s.
// - Keyboard (⌘K to open, Esc to close): no motion at all. Someone driving the
//   app from the keyboard wants the field now, not a flourish; taps keep the spring.

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
        /// The label and the shortcut keys, like the original.
        case label
        /// A magnifier and the shortcut keys.
        case keys
        /// Only the magnifier, for narrow rows.
        case icon
    }

    @Binding var isOpen: Bool
    @Binding var query: String
    var label: String = "Search"
    var shortcut: String = "⌘K"
    var placeholder: String = "Find a screen or action"
    var idle: Idle = .label
    /// Accessibility identifiers for the folded button and the open field (UI tests).
    var buttonIdentifier: String? = nil
    var fieldIdentifier: String? = nil
    /// Optional shared storage for "the last open/close came from the keyboard", so
    /// a container can drop its own transitions in step (see `MotionKeyboard`).
    var keyboardChange: Binding<Bool>? = nil
    let onSubmit: () -> Void

    @State private var press = CommandPressModel()
    @State private var keysLit = false
    @State private var localKeyboardChange = false
    @State private var focusTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isOpen: Binding<Bool>,
         query: Binding<String>,
         label: String = "Search",
         shortcut: String = "⌘K",
         placeholder: String = "Find a screen or action",
         idle: Idle = .label,
         buttonIdentifier: String? = nil,
         fieldIdentifier: String? = nil,
         keyboardChange: Binding<Bool>? = nil,
         onSubmit: @escaping () -> Void) {
        _isOpen = isOpen
        _query = query
        self.label = label
        self.shortcut = shortcut
        self.placeholder = placeholder
        self.idle = idle
        self.buttonIdentifier = buttonIdentifier
        self.fieldIdentifier = fieldIdentifier
        self.keyboardChange = keyboardChange
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
        .background {
            // ⌘K lives on its own hidden button so the keyboard path can open without motion.
            if !isOpen {
                MotionKeyboard.shortcut(label, KeyEquivalent(shortcutKey), modifiers: shortcutModifiers) {
                    open(fromKeyboard: true)
                }
            }
        }
        .onChange(of: isOpen) { _, nowOpen in
            focusTask?.cancel()
            focusTask = nil
            if nowOpen { focusField() }
        }
        .onAppear { if isOpen { focusField() } }
        .onDisappear { focusTask?.cancel(); focusTask = nil }
    }

    private var fromKeyboard: Bool {
        get { keyboardChange?.wrappedValue ?? localKeyboardChange }
        nonmutating set {
            if let keyboardChange { keyboardChange.wrappedValue = newValue } else { localKeyboardChange = newValue }
        }
    }

    // MARK: Parts

    private var button: some View {
        Button { open(fromKeyboard: false) } label: { idleContent }
            .buttonStyle(CommandPressStyle { down in
                press.press(down)
                if down { keysLit = true } else if !isOpen { keysLit = false }
            })
            .accessibilityLabel(label)
            .accessibilityHint("Opens a search field. Keyboard shortcut \(spokenShortcut).")
            .accessibilityIdentifier(buttonIdentifier ?? "commandButton.open")
    }

    private var idleContent: some View {
        HStack(spacing: idle == .icon ? 0 : 6) {
            switch idle {
            case .label:
                Text(label).font(.subheadline.weight(.medium)).lineLimit(1)
                    .padding(.trailing, 4)
            case .keys, .icon:
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.labelSecondary)
            }
            if idle != .icon {
                HStack(spacing: 3) {
                    ForEach(Array(shortcutCaps.enumerated()), id: \.offset) { _, cap in
                        CommandKeyCap(label: cap, lit: keysLit)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.leading, idle == .icon ? 0 : (idle == .label ? 16 : 12))
        .padding(.trailing, idle == .icon ? 0 : 8)
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
            Button { close(fromKeyboard: false) } label: { CommandKeyCap(label: "Close", lit: false) }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Close search")
                .accessibilityIdentifier("commandButton.close")
                .background {
                    // Esc closes without motion; a tap on Close keeps the spring.
                    MotionKeyboard.shortcut("Close search", .escape, modifiers: []) { close(fromKeyboard: true) }
                }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .onChange(of: fieldFocused) { _, focused in
            // Leaving the field empty folds it back.
            if !focused && isOpen && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { close(fromKeyboard: false) }
        }
    }

    private var swap: AnyTransition {
        guard !fromKeyboard else { return .identity }
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

    private func open(fromKeyboard keyboard: Bool) {
        guard !isOpen else { return }
        MotionKeyboard.change(keyboard, flag: Binding(get: { fromKeyboard }, set: { fromKeyboard = $0 })) {
            guard !isOpen else { return }
            if keyboard {
                MotionKeyboard.withoutMotion { isOpen = true }
            } else {
                keysLit = true
                withAnimation(reduceMotion ? nil : CommandButtonMotion.open) { isOpen = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.18))
                    keysLit = false
                }
            }
        }
    }

    private func close(fromKeyboard keyboard: Bool) {
        guard isOpen else { return }
        focusTask?.cancel()
        focusTask = nil
        MotionKeyboard.change(keyboard, flag: Binding(get: { fromKeyboard }, set: { fromKeyboard = $0 })) {
            guard isOpen else { return }
            // Same update as the fold, so the focus-lost handler already sees it closed.
            fieldFocused = false
            let fold = {
                isOpen = false
                query = ""
            }
            if keyboard { MotionKeyboard.withoutMotion(fold) }
            else { withAnimation(reduceMotion ? nil : CommandButtonMotion.open, fold) }
        }
    }

    /// Focus as the field starts to appear (after the swap delay on a tap, at once
    /// from the keyboard). Cancelled on close so a quick open-close can't refocus.
    private func focusField() {
        let delay = fromKeyboard || reduceMotion ? 0 : CommandButtonMotion.swapDelay
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

    // MARK: Shortcut parsing ("⌘K", "⌘⇧P", ...)

    private static let modifierGlyphs: [Character: EventModifiers] = ["⌘": .command, "⇧": .shift, "⌥": .option, "⌃": .control]

    private var shortcutKey: Character {
        shortcut.last(where: { Self.modifierGlyphs[$0] == nil }).map { Character($0.lowercased()) } ?? "k"
    }

    private var shortcutModifiers: EventModifiers {
        shortcut.reduce(into: EventModifiers()) { result, ch in
            if let m = Self.modifierGlyphs[ch] { result.insert(m) }
        }
    }

    private var shortcutCaps: [String] { shortcut.map { String($0).uppercased() } }

    private var spokenShortcut: String {
        let names: [Character: String] = ["⌘": "Command", "⇧": "Shift", "⌥": "Option", "⌃": "Control"]
        return shortcut.map { names[$0] ?? String($0).uppercased() }.joined(separator: " ")
    }
}

// MARK: - Keyboard path

/// Shared helpers for controls that open, close or switch from a keyboard shortcut
/// with no motion while taps keep their animation.
enum MotionKeyboard {
    /// Runs `body` with every animation off: no implicit animations, no withAnimation.
    static func withoutMotion(_ body: () -> Void) {
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t, body)
    }

    /// Records where a change came from, then applies it. Transitions are picked
    /// from that flag; when it flips, the change waits one main-queue turn so the
    /// view tree (and the transition on a view being removed) already carries the
    /// new choice when the change lands.
    @MainActor
    static func change(_ fromKeyboard: Bool, flag: Binding<Bool>, _ apply: @escaping () -> Void) {
        guard flag.wrappedValue != fromKeyboard else { apply(); return }
        flag.wrappedValue = fromKeyboard
        DispatchQueue.main.async { MainActor.assumeIsolated(apply) }
    }

    /// An invisible button that only carries a keyboard shortcut, so the visible
    /// button's tap and the shortcut can take different paths.
    static func shortcut(_ title: String, _ key: KeyEquivalent, modifiers: EventModifiers = .command,
                         action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

// MARK: - Key cap

struct CommandKeyCap: View {
    let label: String
    var lit: Bool = false

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(lit ? Color.labelPrimary : Color.labelSecondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(lit ? Color.brandLight : Color.surfaceSecondary,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .animation(.easeOut(duration: lit ? 0.075 : 0.15), value: lit)
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
                    CommandButton(isOpen: .constant(false), query: .constant(""), idle: .keys) {}
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
