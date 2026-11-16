import SwiftUI

// MARK: - Expand Card
//
// Port of designbookmark.com/motion "Expand Card" (expand-card/expand.js).
// One progress spring per row (240, 21) drives the card's height and its title
// position; the details fade and slide in on their own spring (260, 28) 160 ms
// later. The chosen row comes forward while every other row in the group sinks
// a little (scale 300/26) and dims (opacity 300/30). Tap it again to fold it,
// tap another to switch. No autoplay.
// In the source the chosen row also slides to the top of a fixed-height list;
// inside a scrolling stack that would overlap its neighbours, so the card opens
// in place and "rides up" as a lift (shadow and scale) over the dimmed rows.
// Reduce Motion: springs are critically damped (height still follows, no
// overshoot) and the decorative sink/lift scale is skipped.
//
// Accessibility: the header is a button with the expanded state as its value
// and a named action ("Show ingredients" / "Hide ingredients"); the details
// are reachable only while open.

/// Shared state for a group of expand cards: at most one is open.
@MainActor
@Observable
final class ExpandCardGroup {
    struct Values: Equatable {
        /// Open progress 0…1 (overshoots slightly).
        var progress: Double = 0
        /// Details reveal 0…1.
        var detail: Double = 0
        var opacity: Double = 1
        var scale: Double = 1
    }

    private(set) var openID: String?
    private(set) var values: [String: Values] = [:]

    @ObservationIgnored private var rows: [String: Springs] = [:]
    /// Views showing each row; an old and a new copy can overlap during a transition.
    @ObservationIgnored private var refs: [String: Int] = [:]
    @ObservationIgnored private var detailTimer: Int?
    @ObservationIgnored private let clock = MotionClock()

    private struct Springs {
        var p = MotionSpring(0, 240, 21)
        var a = MotionSpring(0, 260, 28)
        var o = MotionSpring(1, 300, 30)
        var s = MotionSpring(1, 300, 26)
        var all: [MotionSpring] { [p, a, o, s] }
    }

    /// How far the other rows dim and sink while one is open.
    static let dimOpacity = 0.45
    static let dimScale = 0.97

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func values(for id: String) -> Values { values[id] ?? Values() }
    func isOpen(_ id: String) -> Bool { openID == id }

    func register(_ id: String) {
        refs[id, default: 0] += 1
        guard rows[id] == nil else { return }
        var s = Springs()
        if openID != nil { s.o.snap(Self.dimOpacity); s.s.snap(MotionSettings.reduceMotion ? 1 : Self.dimScale) }
        rows[id] = s
        values[id] = Self.publish(s)
    }

    /// A row that left the screen. If it was the open one, the others brighten again.
    func unregister(_ id: String) {
        guard rows[id] != nil else { return }
        refs[id, default: 1] -= 1
        guard refs[id, default: 0] <= 0 else { return }
        refs[id] = nil
        if openID == id { show(nil) }
        rows[id] = nil
        values[id] = nil
    }

    func toggle(_ id: String) { show(openID == id ? nil : id) }

    /// Opens `id` (nil folds everything). `animated: false` jumps.
    func show(_ id: String?, animated: Bool = true) {
        openID = id
        if let detailTimer { clock.cancel(detailTimer) }
        detailTimer = nil
        let sink = MotionSettings.reduceMotion ? 1 : Self.dimScale
        for key in rows.keys {
            var r = rows[key]!
            if id == nil {
                r.p.t = 0; r.a.t = 0; r.o.t = 1; r.s.t = 1
            } else if key == id {
                r.p.t = 1; r.o.t = 1; r.s.t = 1
            } else {
                r.p.t = 0; r.a.t = 0; r.o.t = Self.dimOpacity; r.s.t = sink
            }
            if !animated { r.p.snap(r.p.t); r.o.snap(r.o.t); r.s.snap(r.s.t); r.a.snap(key == id ? 1 : 0) }
            rows[key] = r
        }
        guard animated else { render(); return }
        if let id {
            detailTimer = clock.after(0.16) { [weak self] in
                guard let self, self.openID == id else { return }
                self.rows[id]?.a.t = 1
            }
        }
        clock.start()
    }

    func stop() {
        for key in rows.keys {
            var r = rows[key]!
            r.p.snap(r.p.t); r.o.snap(r.o.t); r.s.snap(r.s.t)
            r.a.snap(key == openID ? 1 : 0)
            rows[key] = r
        }
        render()
        clock.stop()
    }

    private func frame(_ dt: Double) {
        for key in rows.keys {
            rows[key]!.p.step(dt); rows[key]!.a.step(dt); rows[key]!.o.step(dt); rows[key]!.s.step(dt)
        }
    }

    private static func publish(_ r: Springs) -> Values {
        Values(progress: max(0, r.p.x), detail: motionClamp(r.a.x, 0, 1),
               opacity: motionClamp(r.o.x, 0, 1), scale: r.s.x)
    }

    private func render() {
        var next: [String: Values] = [:]
        for (key, r) in rows { next[key] = Self.publish(r) }
        if next != values { values = next }
        let settled = rows.values.allSatisfy { $0.all.allSatisfy(\.isSettled) }
        if clock.isRunning, settled, detailTimer == nil || openID.map({ rows[$0]?.a.t == 1 }) == true {
            for key in rows.keys {
                var r = rows[key]!
                r.p.snap(r.p.t); r.a.snap(r.a.t); r.o.snap(r.o.t); r.s.snap(r.s.t)
                rows[key] = r
                next[key] = Self.publish(r)
            }
            values = next
            detailTimer = nil
            clock.stop()
        }
    }
}

struct ExpandCard<Header: View, Detail: View>: View {
    let id: String
    let group: ExpandCardGroup
    /// What VoiceOver calls the card when it reads the header button.
    var accessibilityLabel: String
    var showActionName: String = "Show ingredients"
    var hideActionName: String = "Hide ingredients"
    var hint: String? = nil
    /// Header, given the open progress (0…1, may overshoot slightly).
    @ViewBuilder let header: (Double) -> Header
    @ViewBuilder let detail: () -> Detail

    @State private var detailHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let v = group.values(for: id)
        let open = group.isOpen(id)
        let q = motionClamp(v.progress, 0, 1)
        VStack(alignment: .leading, spacing: 0) {
            Button { group.toggle(id) } label: {
                header(v.progress)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            .accessibilityHint(hint ?? "")
            .accessibilityAction(named: open ? hideActionName : showActionName) { group.toggle(id) }

            detail()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { detailHeight = g.size.height }
                            .onChange(of: g.size.height) { _, h in detailHeight = h }
                    }
                }
                .opacity(v.detail)
                .offset(y: (1 - v.detail) * (reduceMotion ? 0 : 10))
                .frame(height: detailHeight * v.progress, alignment: .top)
                .clipped()
                .allowsHitTesting(open)
                .accessibilityHidden(!open)
        }
        .padding(.horizontal, Spacing.md * q)
        .padding(.vertical, Spacing.sm * q)
        .background {
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .fill(Color.surface)
                .shadow(color: .black.opacity(0.08 * q), radius: 10 * q, y: 4 * q)
                .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 0.5))
                .opacity(q)
        }
        .scaleEffect(reduceMotion ? 1 : v.scale)
        .opacity(v.opacity)
        .zIndex(open ? 1 : 0)
        .sensoryFeedback(.selection, trigger: open)
        .onAppear { group.register(id) }
        .onDisappear { group.unregister(id) }
    }
}

// MARK: - Preview

#Preview("Expand Card") {
    @Previewable @State var group = ExpandCardGroup()
    let meals: [(String, String, Int)] = [
        ("Oatmeal with berries", "250 g", 410),
        ("Buckwheat with chicken", "380 g", 620),
        ("Cottage cheese pancakes", "220 g", 480),
    ]
    ScrollView {
        VStack(spacing: Spacing.sm) {
            ForEach(meals, id: \.0) { meal in
                ExpandCard(id: meal.0, group: group, accessibilityLabel: "\(meal.0), \(meal.2) kcal") { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.0).font(.subheadline.weight(.medium)).foregroundStyle(Color.labelPrimary)
                            Text(meal.1).font(.caption).foregroundStyle(Color.labelSecondary)
                        }
                        Spacer()
                        Text("\(meal.2) kcal").font(.caption.weight(.semibold)).foregroundStyle(Color.labelSecondary)
                        Image(systemName: "chevron.right").font(.caption2)
                            .foregroundStyle(Color.labelTertiary)
                            .rotationEffect(.degrees(90 * p))
                    }
                    .padding(.vertical, Spacing.xs)
                } detail: {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Oats · 60 g").font(.caption)
                        Text("Blueberries · 80 g").font(.caption)
                        Text("Kefir · 110 ml").font(.caption)
                        Text("P 18 g · C 62 g · F 9 g").font(.caption2).foregroundStyle(Color.labelSecondary)
                    }
                    .foregroundStyle(Color.labelPrimary)
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
        .padding(Spacing.lg)
    }
    .background(Color.surfaceGrouped)
}
