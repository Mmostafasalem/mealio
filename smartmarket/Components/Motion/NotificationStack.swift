import SwiftUI

// MARK: - Notification Stack
//
// Port of Kokonut UI "Notification Stack" (notification-stack.tsx, MIT), as
// shown at designbookmark.com/motion "Notification stack". Cards sit in a
// pile: the newest in front, up to two behind it peeking out 10 pt each and
// 5 % smaller per step. A tap fans the pile out into a list (8 pt apart);
// "Show less" folds it back. Swipe a card sideways to dismiss it: past 100 pt
// or a quick flick and it flies off, otherwise it snaps back on a critically
// damped spring (stiffness 520). Layout changes take 0.3 s on the original's
// ease-out curve. Reduce Motion: cards fade instead of sliding.

struct StackNotice: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: String
    let body: String
    /// Small text on the right, such as a time.
    var detail: String = ""
}

struct NotificationStack: View {
    let notices: [StackNotice]
    var title: String = "Notifications"
    /// Tapping a card when the stack is already fanned out (or holds one card).
    var onOpen: (StackNotice) -> Void = { _ in }
    var onDismiss: (StackNotice) -> Void
    var onClearAll: () -> Void

    @State private var expanded = false
    @State private var heights: [String: CGFloat] = [:]
    @State private var drag: (id: String, x: CGFloat)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let peek: CGFloat = 10
    private static let visibleBehind = 2
    private static let gap: CGFloat = 8
    private static let fallbackHeight: CGFloat = 76
    private static let dismissDistance: CGFloat = 100
    /// Points per second (the original's 0.11 px/ms).
    private static let dismissVelocity: CGFloat = 110
    static let layout = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.3)
    /// Critically damped: never wobbles past rest.
    private static let snapBack = Animation.interpolatingSpring(stiffness: 520, damping: 2 * 520.0.squareRoot())

    private func height(_ notice: StackNotice) -> CGFloat { heights[notice.id] ?? Self.fallbackHeight }

    var body: some View {
        let isOpen = expanded && notices.count > 1
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.labelPrimary)
                if notices.count > 1 {
                    Text("\(notices.count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.dullPink, in: Capsule())
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(notices.count) items")
                }
                Spacer(minLength: Spacing.sm)
                if isOpen {
                    Button("Show less") { withAnimation(Self.layout) { expanded = false } }
                    Button("Clear all") { withAnimation(Self.layout) { expanded = false; onClearAll() } }
                } else if notices.count > 1 {
                    Button("Show all") { withAnimation(Self.layout) { expanded = true } }
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.labelSecondary)
            .frame(minHeight: 32)
            .padding(.horizontal, Spacing.xs)

            ZStack(alignment: .top) {
                ForEach(Array(notices.enumerated()), id: \.element.id) { depth, notice in
                    card(notice, depth: depth, isOpen: isOpen)
                }
            }
            .frame(height: stackHeight(isOpen), alignment: .top)
            .padding(.bottom, Spacing.xs)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Self.layout, value: notices)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Self.layout, value: expanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func stackHeight(_ isOpen: Bool) -> CGFloat {
        guard let front = notices.first else { return 0 }
        if isOpen {
            return notices.reduce(0) { $0 + height($1) } + Self.gap * CGFloat(notices.count - 1)
        }
        return height(front) + CGFloat(min(notices.count - 1, Self.visibleBehind)) * Self.peek
    }

    private func card(_ notice: StackNotice, depth: Int, isOpen: Bool) -> some View {
        let scale: CGFloat = isOpen ? 1 : 1 - CGFloat(depth) * 0.05
        let front = notices.first.map(height) ?? Self.fallbackHeight
        // Fanned out: stacked one under another. Piled: bottom-aligned behind the
        // front card so a strip of each peeks out below it, whatever its height.
        let y: CGFloat = isOpen
            ? notices.prefix(depth).reduce(0) { $0 + height($1) + Self.gap }
            : front + CGFloat(depth) * Self.peek - height(notice) * scale
        let hidden = !isOpen && depth > Self.visibleBehind
        let dx = drag?.id == notice.id ? drag?.x ?? 0 : 0

        return NoticeCard(notice: notice)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[notice.id] = $0 }
            .scaleEffect(scale, anchor: .top)
            .offset(x: dx, y: y)
            .opacity(hidden ? 0 : 1 - min(abs(dx) / 260, 0.6))
            .zIndex(Double(notices.count - depth))
            .allowsHitTesting(!hidden && (isOpen || depth == 0))
            .onTapGesture {
                if notices.count > 1 && !isOpen { withAnimation(Self.layout) { expanded = true } }
                else { onOpen(notice) }
            }
            .gesture(swipe(notice))
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -12)))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(notices.count > 1 && !isOpen ? "Shows all \(notices.count)" : "Opens it")
            .accessibilityAction(named: "Dismiss") { onDismiss(notice) }
            .accessibilityHidden(hidden)
    }

    private func swipe(_ notice: StackNotice) -> some Gesture {
        // Horizontal only, so a list underneath still scrolls.
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                drag = (notice.id, value.translation.width)
            }
            .onEnded { value in
                guard drag?.id == notice.id else { return }
                let dx = value.translation.width
                let speed = value.velocity.width
                let flick = abs(speed) > Self.dismissVelocity && abs(dx) > 24 && speed * dx > 0
                if abs(dx) > Self.dismissDistance || flick {
                    // Fly off the side it was heading, then leave the stack.
                    withAnimation(.easeOut(duration: 0.2)) { drag = (notice.id, dx > 0 ? 600 : -600) }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.2))
                        drag = nil
                        onDismiss(notice)
                    }
                } else {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Self.snapBack) { drag = nil }
                }
            }
    }
}

private struct NoticeCard: View {
    let notice: StackNotice

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: notice.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.labelPrimary)
                .frame(width: 40, height: 40)
                .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(notice.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.sm)
                    Text(notice.detail)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Text(notice.body)
                    .font(.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
        .elevation(Elevation.card)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

#Preview {
    @Previewable @State var notices = [
        StackNotice(id: "dinner", symbol: "moon.fill", title: "Dinner", body: "Dinner time. Log it to close out your day.", detail: "19:00"),
        StackNotice(id: "workout", symbol: "figure.run", title: "Workout", body: "Time to move. Build a session in Train.", detail: "18:00"),
        StackNotice(id: "lunch", symbol: "sun.max.fill", title: "Lunch", body: "Lunch time. Your plan for today is in Meals.", detail: "13:00"),
        StackNotice(id: "breakfast", symbol: "sunrise.fill", title: "Breakfast", body: "Time for breakfast.", detail: "08:00"),
    ]
    NotificationStack(notices: notices, title: "Reminders",
                      onDismiss: { n in notices.removeAll { $0.id == n.id } },
                      onClearAll: { notices = [] })
        .padding(24)
}
