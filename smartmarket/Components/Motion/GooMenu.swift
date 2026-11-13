import SwiftUI

// MARK: - Goo Menu
//
// Port of designbookmark.com/motion "Goo Menu" (goo-menu/goo.js).
// A + button that pours out liquid bubbles. Bubbles are springs; one goo layer
// (blur + alpha threshold) fuses them while they are close, so they peel off the
// button like drops, with a short stagger (45 ms). Tapping a bubble gives it a
// pop, pulls everything back in, then runs its action. A tap anywhere outside
// closes it. The + turns into a × while open.
//
// Used often, so the outgoing spring is calmer than the original (230/19 vs 230/15).
// No idle "breathing" (the original's decorative autoplay) and no keyboard shortcuts.
//
// Layout: the view is just the 44 pt button; the bubbles fan out in an arc from
// `startAngle` to `endAngle` (degrees, y down) and draw outside its frame, so give
// the container a zIndex above its later siblings.
//
// Reduce Motion: bubbles don't travel; they fade in and out at their places.

struct GooMenuItem: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
}

struct GooMenu: View {
    let items: [GooMenuItem]
    var accessibilityLabel: String = "Add food"
    /// Arc of the bubbles, degrees clockwise from +x (screen coordinates, y down).
    var startAngle: Double = 180
    var endAngle: Double = 90
    let onSelect: (GooMenuItem) -> Void

    @State private var engine = GooMenuEngine()

    private static let canvasSide: Double = 2 * (GooMenuEngine.radius + GooMenuEngine.bubbleSize + 24)

    var body: some View {
        let s = engine.snap
        ZStack {
            if s.open {
                // Outside tap closes. Large and clear; only taps, so scrolling still works.
                Color.clear
                    .frame(width: 3000, height: 3000)
                    .contentShape(Rectangle())
                    .onTapGesture { engine.setOpen(false) }
                    .accessibilityHidden(true)
            }

            Canvas { ctx, size in draw(s, in: &ctx, size: size) }
                .frame(width: Self.canvasSide, height: Self.canvasSide)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            ForEach(Array(items.prefix(GooMenuEngine.maxItems).enumerated()), id: \.element.id) { i, item in
                bubble(item, index: i, s)
            }

            Button { engine.setOpen(!s.open) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .rotationEffect(.degrees(s.rotation))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(s.open ? "Meal choices shown" : "")
            .accessibilityHint(s.open ? "Closes the meal choices" : "Shows meal choices")
        }
        .frame(width: 44, height: 44)
        .sensoryFeedback(.selection, trigger: s.open)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { engine.setOpen(false) }
        .onAppear { engine.configure(count: min(items.count, GooMenuEngine.maxItems), from: startAngle, to: endAngle) }
        .onDisappear { engine.reset() }
    }

    private func bubble(_ item: GooMenuItem, index i: Int, _ s: GooMenuEngine.Snapshot) -> some View {
        let b = s.bubbles.indices.contains(i) ? s.bubbles[i] : .init()
        let home = engine.home(i)
        let len = max(hypot(home.x, home.y), 1)
        let labelDistance = GooMenuEngine.bubbleSize / 2 + 16
        return ZStack {
            Button {
                engine.select(i) { onSelect(item) }
            } label: {
                Image(systemName: item.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .frame(width: GooMenuEngine.bubbleSize, height: GooMenuEngine.bubbleSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .scaleEffect(b.scale)
            .accessibilityLabel(item.title)
            .accessibilityHint("Log food to \(item.title)")

            // The name sits outside the arc, so it never covers a neighbour.
            Text(item.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.labelSecondary)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .fixedSize()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
                .offset(x: home.x / len * labelDistance, y: home.y / len * labelDistance)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .offset(x: b.x, y: b.y)
        .opacity(b.opacity)
        .allowsHitTesting(s.open)
        .accessibilityHidden(!s.open)
    }

    private func draw(_ s: GooMenuEngine.Snapshot, in ctx: inout GraphicsContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let E = GooMenuEngine.self
        func circle(_ r: Double) -> Path { Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)) }

        if s.reduced {
            // No goo: plain circles fading in place.
            var m = ctx
            m.translateBy(x: c.x, y: c.y)
            m.fill(circle(E.mainSize / 2), with: .color(E.fill))
            for b in s.bubbles where b.opacity > 0.01 {
                var d = ctx
                d.opacity = b.opacity
                d.translateBy(x: c.x + b.x, y: c.y + b.y)
                d.fill(circle(E.bubbleSize / 2), with: .color(E.fill))
            }
            return
        }
        ctx.drawLayer { goo in
            goo.addFilter(.alphaThreshold(min: 0.5, color: E.fill))
            goo.addFilter(.blur(radius: E.blur))
            goo.drawLayer { layer in
                var m = layer
                m.translateBy(x: c.x, y: c.y)
                m.scaleBy(x: s.mainScale, y: s.mainScale)
                m.fill(circle(E.mainSize / 2 + 2), with: .color(.black))
                for b in s.bubbles {
                    // squash and stretch along the direction of travel
                    var d = layer
                    d.translateBy(x: c.x + b.x, y: c.y + b.y)
                    d.rotate(by: .radians(b.angle))
                    d.scaleBy(x: b.scale * b.stretch, y: b.scale / b.stretch)
                    d.fill(circle(E.bubbleSize / 2 + 2), with: .color(.black))
                }
            }
        }
    }
}

// MARK: - Engine

@MainActor
@Observable
final class GooMenuEngine {
    struct Bubble: Equatable {
        var x: Double = 0, y: Double = 0
        var scale: Double = 0.5
        var stretch: Double = 1
        var angle: Double = 0
        var opacity: Double = 0
    }

    struct Snapshot: Equatable {
        var open = false
        var bubbles: [Bubble] = []
        var mainScale: Double = 1
        var rotation: Double = 0
        var reduced = false
    }

    // tokens.css: --goo-out 230 15, --goo-in 520 34, --goo-radius 112, --goo-stagger 45, --goo-blur 10
    static let radius: Double = 112
    static let stagger: Double = MotionTokens.stagger
    static let blur: Double = 10
    static let bubbleSize: Double = 44
    static let mainSize: Double = 40
    static let maxItems = 6
    static let fill = Color.surfaceSecondary
    private static let out = (k: 230.0, c: 19.0)
    private static let back = (k: 520.0, c: 34.0)

    private(set) var snap = Snapshot()

    private struct B {
        var x = MotionSpring(0, 0, 0)
        var y = MotionSpring(0, 0, 0)
        var s = MotionSpring(0.5, 300, 21)
        var o = MotionSpring(0, MotionTokens.fade)   // Reduce Motion only
        var pending: (t: Double, x: Double, y: Double, k: Double, c: Double)?
    }

    @ObservationIgnored private var bubbles: [B] = []
    @ObservationIgnored private var homes: [CGPoint] = []
    @ObservationIgnored private var open = false
    @ObservationIgnored private var mainScale = MotionSpring(1, 520, 28)
    @ObservationIgnored private var rotation = MotionSpring(0, 320, 22)
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func configure(count: Int, from start: Double, to end: Double) {
        guard bubbles.count != count || homes.isEmpty else { return }
        homes = (0..<count).map { i in
            let f = count > 1 ? Double(i) / Double(count - 1) : 0.5
            let a = (start + (end - start) * f) * .pi / 180
            return CGPoint(x: cos(a) * Self.radius, y: sin(a) * Self.radius)
        }
        bubbles = (0..<count).map { _ in
            var b = B()
            b.x = MotionSpring(0, Self.out.k, Self.out.c)
            b.y = MotionSpring(0, Self.out.k, Self.out.c)
            return b
        }
        render()
    }

    func home(_ i: Int) -> CGPoint { homes.indices.contains(i) ? homes[i] : .zero }

    func setOpen(_ v: Bool) {
        guard v != open else { return }
        open = v
        let reduce = MotionSettings.reduceMotion
        rotation.t = v ? 135 : 0
        if reduce { rotation.snap(rotation.t) } else { mainScale.v -= v ? 3 : 1.6 }
        let n = bubbles.count
        for i in bubbles.indices {
            if reduce {
                bubbles[i].pending = nil
                bubbles[i].x.snap(v ? homes[i].x : 0)
                bubbles[i].y.snap(v ? homes[i].y : 0)
                bubbles[i].s.snap(1)
                bubbles[i].o.t = v ? 1 : 0
                continue
            }
            if v {
                bubbles[i].pending = (Double(i) * Self.stagger, Double(homes[i].x), Double(homes[i].y), Self.out.k, Self.out.c)
                bubbles[i].s.tune(300, 21); bubbles[i].s.t = 1
            } else {
                bubbles[i].pending = (Double(n - 1 - i) * Self.stagger * 0.66, 0, 0, Self.back.k, Self.back.c)
                bubbles[i].s.tune(420, 30); bubbles[i].s.t = 0.5
            }
        }
        render()
        clock.start()
    }

    /// Pop the bubble, pull everything back in, then run the action.
    func select(_ i: Int, then action: @escaping () -> Void) {
        guard open, bubbles.indices.contains(i) else { return }
        if !MotionSettings.reduceMotion { bubbles[i].s.v += 4 }
        clock.after(0.08) { [weak self] in self?.setOpen(false) }
        clock.after(0.3) { action() }
    }

    func reset() {
        clock.cancelAllTimers()
        open = false
        rotation.snap(0); mainScale.snap(1)
        for i in bubbles.indices {
            bubbles[i].pending = nil
            bubbles[i].x.snap(0); bubbles[i].y.snap(0); bubbles[i].s.snap(0.5); bubbles[i].o.snap(0)
        }
        render()
        clock.stop()
    }

    // MARK: Simulation

    private func frame(_ dt: Double) {
        for i in bubbles.indices {
            if var p = bubbles[i].pending {
                p.t -= dt
                if p.t <= 0 {
                    bubbles[i].pending = nil
                    bubbles[i].x.tune(p.k, p.c); bubbles[i].y.tune(p.k, p.c)
                    bubbles[i].x.t = p.x; bubbles[i].y.t = p.y
                } else {
                    bubbles[i].pending = p
                }
            }
            bubbles[i].x.step(dt); bubbles[i].y.step(dt); bubbles[i].s.step(dt); bubbles[i].o.step(dt)
        }
        mainScale.step(dt); rotation.step(dt)
    }

    private func render() {
        let reduce = MotionSettings.reduceMotion
        var s = Snapshot()
        s.open = open
        s.reduced = reduce
        s.mainScale = mainScale.x
        s.rotation = rotation.x
        s.bubbles = bubbles.map { b in
            var o = Bubble()
            o.x = b.x.x; o.y = b.y.x
            o.scale = b.s.x
            let speed = hypot(b.x.v, b.y.v)
            o.stretch = reduce ? 1 : 1 + min(speed / 2600, 0.32)
            o.angle = atan2(b.y.v, b.x.v)
            o.opacity = reduce
                ? motionClamp(b.o.x, 0, 1)
                : motionClamp((hypot(b.x.x, b.y.x) - 18) / 40, 0, 1)
            return o
        }
        if s != snap { snap = s }

        let pts = MotionSpring.points
        let settled = bubbles.allSatisfy {
            $0.pending == nil && $0.x.isSettled(within: pts) && $0.y.isSettled(within: pts) && $0.s.isSettled && $0.o.isSettled
        } && mainScale.isSettled && rotation.isSettled(within: MotionSpring.degrees)
        if settled && clock.isRunning { clock.stop() }
    }
}

// MARK: - Preview

#Preview("Goo Menu") {
    @Previewable @State var picked = "Nothing yet"
    VStack(alignment: .leading, spacing: Spacing.lg) {
        HStack {
            Label("Today's Log", systemImage: "list.bullet.clipboard.fill").font(.sectionTitle)
            Spacer()
            GooMenu(items: [
                GooMenuItem(id: "breakfast", title: "Breakfast", systemImage: "sunrise"),
                GooMenuItem(id: "lunch", title: "Lunch", systemImage: "sun.max"),
                GooMenuItem(id: "dinner", title: "Dinner", systemImage: "moon"),
                GooMenuItem(id: "snack", title: "Snack", systemImage: "sparkles"),
            ]) { picked = $0.title }
        }
        .zIndex(1)
        Text("Picked: \(picked)").foregroundStyle(Color.labelSecondary)
        Spacer().frame(height: 160)
    }
    .padding(Spacing.lg)
    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .padding(Spacing.lg)
    .background(Color.surfaceGrouped)
}
