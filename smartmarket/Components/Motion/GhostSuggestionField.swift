import SwiftUI
import UIKit

// MARK: - Ghost suggestion field
//
// Port of designbookmark.com/motion "Ghost Suggestion" (ghost-suggestion/ghost.js),
// built on `SpringyTextField` so one field does both. When the typed text is the
// start of a suggestion, the rest is drawn after it in labelTertiary with an
// "Accept" chip beside it. The chip, or the Return key while a suggestion shows,
// accepts it: each suggested letter turns ink with a small hop, left to right, the
// caret travels to the end, and the chip goes down and away (ghost.js tab spring
// 520 24, kicked with -9). No autoplay: nothing is typed or accepted by itself.
//
// Accessibility: the chip is a real button ("Accept suggestion, <name>"); the
// ghost letters are part of the hidden mirror. Reduce Motion: no hop, the letters
// just change colour.

struct GhostSuggestionField: View {
    let placeholder: String
    @Binding var text: String
    /// A full candidate (e.g. a catalog food name). Shown only if `text` is its start.
    var suggestion: String?
    var accessibilityIdentifier: String? = nil
    var returnKey: UIReturnKeyType = .search
    var acceptIdentifier: String? = nil
    /// Return key with no suggestion showing. Return true to hide the keyboard.
    var onSubmit: () -> Bool = { true }

    @State private var field = SpringyFieldModel()
    @State private var chip = GhostChipModel()

    /// The part of the suggestion still to type, keeping the person's own letters.
    static func remainder(of suggestion: String?, after typed: String) -> String? {
        guard let suggestion, !typed.isEmpty,
              let r = suggestion.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive, .anchored]),
              r.upperBound < suggestion.endIndex else { return nil }
        return String(suggestion[r.upperBound...])
    }

    private var rest: String? { Self.remainder(of: suggestion, after: text) }
    private var canAccept: Bool { rest != nil && field.ghostShown }

    var body: some View {
        HStack(spacing: 6) {
            SpringyTextField(
                placeholder: placeholder,
                text: $text,
                ghost: rest,
                accessibilityIdentifier: accessibilityIdentifier,
                returnKey: returnKey,
                model: field,
                onReturn: {
                    if canAccept { accept(); return false }
                    return onSubmit()
                }
            )
            if chip.visible, let suggestion {
                Button(action: accept) {
                    HStack(spacing: 3) {
                        Text("Accept")
                        Image(systemName: "arrow.right")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.labelSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .scaleEffect(0.6 + 0.4 * motionClamp(chip.value, 0, 1.2))
                    .opacity(motionClamp(chip.value, 0, 1))
                    .frame(minWidth: 44, minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canAccept)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .accessibilityLabel("Accept suggestion")
                .accessibilityValue(suggestion)
                .accessibilityIdentifier(acceptIdentifier ?? "ghostSuggestion.accept")
            }
        }
        .onChange(of: canAccept, initial: true) { _, can in chip.show(can) }
        .onDisappear { chip.stop() }
    }

    private func accept() {
        guard let rest, canAccept else { return }
        chip.dismiss()
        field.prepareAccept(rest)
        text += rest
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Chip spring

@MainActor @Observable
final class GhostChipModel {
    private(set) var value: Double = 0
    private(set) var visible = false
    @ObservationIgnored private var s = MotionSpring(0, 520, 24)
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.s.step(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func show(_ on: Bool) {
        let target: Double = on ? 1 : 0
        guard s.t != target else { return }
        s.t = target
        if on { visible = true }
        clock.start()
    }

    /// Accepted: the key goes down and away (ghost.js).
    func dismiss() {
        if !MotionSettings.reduceMotion { s.v = -9 }
        s.t = 0
        clock.start()
    }

    func stop() {
        s.snap(s.t)
        render()
        clock.stop()
    }

    private func render() {
        value = s.x
        if s.isSettled {
            s.snap(s.t)
            value = s.t
            if s.t == 0 { visible = false }
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Ghost suggestion") {
    @Previewable @State var query = "Chick"
    let foods = ["Chicken breast, roasted", "Chickpeas, cooked", "Cheddar cheese"]
    let match = foods.first { GhostSuggestionField.remainder(of: $0, after: query) != nil }
    VStack(alignment: .leading, spacing: Spacing.md) {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.labelSecondary)
            GhostSuggestionField(placeholder: "Search foods", text: $query, suggestion: match)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        Text("Tap the field, then Accept or Return to take the suggestion.")
            .font(.footnote).foregroundStyle(Color.labelSecondary)
    }
    .padding(Spacing.lg)
    .frame(maxHeight: .infinity)
    .background(Color.surfaceGrouped)
}
