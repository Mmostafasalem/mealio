import SwiftUI

// MARK: - Cart Button
//
// Port of Kokonut UI "Cart Button" (cart-button.tsx, MIT), as shown at
// designbookmark.com/motion "Cart button". "Add +" opens in place into a
// "− n +" stepper: the + never moves, so a second tap lands where the first
// did. At one, − turns into a bin. Holding + or − repeats, faster and faster
// (380 ms wait, then 150 ms down to 55 ms), and a hold on − stops at one
// rather than emptying the line. At the limit the number shakes and a small
// note appears for 1.6 s. The pill's width takes 0.32 s and everything else
// 0.2 s on the original's ease-out curve. Reduce Motion: no slide or shake.

struct CartButton: View {
    let quantity: Int
    var max: Int = 99
    /// Item name for VoiceOver.
    var name: String = "item"
    var label: String = "Add"
    let onAdd: () -> Void
    let onRemove: () -> Void

    @State private var limitHits = 0
    @State private var showLimit = false
    @State private var shake: CGFloat = 0
    @State private var hold: Task<Void, Never>?
    @State private var limitTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let widthClosed: CGFloat = 88
    private static let widthOpen: CGFloat = 124
    private static let side: CGFloat = 44
    private static let fade = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
    private static let resize = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.32)

    private var isOpen: Bool { quantity > 0 }

    var body: some View {
        ZStack(alignment: .trailing) {
            Capsule()
                .fill(isOpen ? Color.dullPink : Color.surface)
                .overlay(Capsule().strokeBorder(isOpen ? Color.clear : Color.hairline, lineWidth: 1))

            if isOpen {
                // − (a bin at one), then the count; they slide in from the right.
                HStack(spacing: 0) {
                    control(systemImage: quantity == 1 ? "trash" : "minus", delta: -1,
                            label: quantity == 1 ? "Remove \(name) from cart" : "Decrease quantity")
                    Text("\(quantity)")
                        .font(.system(.callout, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(quantity)))
                        .frame(maxWidth: .infinity)
                        .offset(x: shake)
                        .accessibilityLabel("\(quantity) \(name) in cart")
                    Color.clear.frame(width: Self.side)
                }
                .foregroundStyle(Color.onAccent)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 14)))
            } else {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: -6)))
                    .accessibilityHidden(true)
            }

            // The + stays put in both states.
            control(systemImage: "plus", delta: 1, label: isOpen ? "Increase quantity" : "Add to cart")
                .foregroundStyle(isOpen ? Color.onAccent.opacity(quantity >= max ? 0.4 : 1) : Color.labelPrimary)
        }
        .frame(width: isOpen ? Self.widthOpen : Self.widthClosed, height: Self.side)
        .clipShape(Capsule())
        .contentShape(Capsule())
        // Closed, the whole pill adds one.
        .onTapGesture { if !isOpen { step(1) } }
        .overlay(alignment: .topTrailing) {
            if showLimit {
                Text("Limit \(max)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.surface)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.labelPrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .fixedSize()
                    .offset(y: -30)
                    .transition(.opacity.combined(with: .offset(y: 4)))
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : Self.resize, value: isOpen)
        .animation(reduceMotion ? nil : Self.fade, value: quantity)
        .animation(Self.fade, value: showLimit)
        .sensoryFeedback(.impact(weight: .light), trigger: quantity)
        .sensoryFeedback(.warning, trigger: limitHits)
        .onDisappear { hold?.cancel(); limitTask?.cancel() }
    }

    /// A 44 pt control that steps once on a tap and repeats while held.
    private func control(systemImage: String, delta: Int, label: String) -> some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.bold))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: Self.side, height: Self.side)
            .contentShape(Rectangle())
            .onTapGesture { step(delta) }
            .onLongPressGesture(minimumDuration: 0.38, maximumDistance: 24) {
                startRepeating(delta)
            } onPressingChanged: { pressing in
                if !pressing { hold?.cancel() }
            }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { step(delta) }
    }

    /// One step; returns false when it can't happen.
    @discardableResult
    private func step(_ delta: Int) -> Bool {
        if delta > 0 {
            guard quantity < max else { hitLimit(); return false }
            onAdd()
        } else {
            guard quantity > 0 else { return false }
            onRemove()
        }
        return true
    }

    private func startRepeating(_ delta: Int) {
        hold?.cancel()
        hold = Task { @MainActor in
            var interval = 0.15
            while !Task.isCancelled {
                // A hold on − stops at one rather than emptying the line.
                if delta < 0 && quantity <= 1 { return }
                guard step(delta) else { return }
                try? await Task.sleep(for: .seconds(interval))
                interval = Swift.max(0.055, interval * 0.85)
            }
        }
    }

    private func hitLimit() {
        limitHits += 1
        showLimit = true
        limitTask?.cancel()
        limitTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            showLimit = false
        }
        guard !reduceMotion else { return }
        // x: 0 → -3 → 3 → -2 → 2 → 0 over 0.3 s.
        Task { @MainActor in
            for x in [-3.0, 3, -2, 2, 0] {
                withAnimation(.easeOut(duration: 0.06)) { shake = x }
                try? await Task.sleep(for: .seconds(0.06))
            }
        }
    }
}

#Preview {
    @Previewable @State var count = 0
    VStack(spacing: 24) {
        CartButton(quantity: count, max: 5, name: "Oats", onAdd: { count += 1 }, onRemove: { count -= 1 })
        Text("In cart: \(count)")
    }
    .padding(40)
}
