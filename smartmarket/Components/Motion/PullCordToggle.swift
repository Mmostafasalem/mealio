import SwiftUI

// MARK: - Pull Cord Toggle
//
// Port of designbookmark.com/motion "Pull Cord" (pull-cord/cord.js).
// The cord is a chain of points with weight, kept at length by soft links, so it
// hangs, swings and whips like a rope. Held, the bead follows the finger until the
// cord is tight; past that it stretches like rubber and tugs the lamp, which leans
// toward the pull on its wire. A pull past the click flips the switch: the light
// room opens as a circle from the bulb (and closes back into it), the bulb pops and
// the lamp bounces. Let go and the cord whips back while the lamp swings to rest.
// A tap pulls it once. Unlike the original it never pulls itself when idle.

struct PullCordToggle: View {
    @Binding var isOn: Bool

    @State private var engine = PullCordEngine()

    var body: some View {
        let s = engine.snap
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                PullCordRenderer.draw(s, in: &ctx, size: size)
            }
            .allowsHitTesting(false)

            // The one real control: a 44×52 grab area that sits on the bead and follows it.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: 44, height: 52)
                .position(x: s.bead.x, y: s.bead.y + s.shift + 14)
                .gesture(grab)
        }
        .coordinateSpace(.named(PullCordEngine.space))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { engine.setSize($0) }
        .onAppear {
            engine.onFlip = { on in isOn = on }
            engine.start(on: isOn)
        }
        .onChange(of: isOn) { _, new in engine.external(new) }
        .sensoryFeedback(.impact, trigger: engine.hapticTick)
        .accessibilityRepresentation {
            Toggle("Light appearance", isOn: $isOn)
        }
        .accessibilityLabel("Pull cord: light or dark appearance")
    }

    private var grab: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(PullCordEngine.space))
            .onChanged { g in
                engine.hold(start: g.startLocation, at: g.location)
            }
            .onEnded { _ in engine.letGo() }
    }
}

// MARK: - Engine

@MainActor
@Observable
final class PullCordEngine {
    static let space = "pullCord"

    struct Point: Equatable { var x: Double; var y: Double; var vx: Double = 0; var vy: Double = 0 }

    struct Snapshot: Equatable {
        var size: CGSize = .zero
        /// Scene is drawn shifted up by this much (≤ 0) so the lamp and bead fit a short card.
        var shift: Double = 0
        var theta: Double = 0
        var tug: Double = 0
        var bulbPop: Double = 1
        var rope: [CGPoint] = []
        var bead: CGPoint = .zero
        var beadAngle: Double = 0
        var lightCentre: CGPoint = .zero
        var lightRadius: Double = 0
        /// Reduce Motion: the light room is crossfaded in at this opacity instead of wiped.
        var lightOpacity: Double = 1
        var crossfade = false
    }

    // wire length; where the cord leaves the shade
    static let WIRE: Double = 122, SHADE: Double = 66, AX: Double = 34, AY: Double = SHADE - 3
    // links in the cord, and its length
    static let N = 12, SEG: Double = 9
    static let L = Double(N) * SEG
    // stretch that flips the switch; the most it gives
    static let CLICK: Double = 22, MAXS: Double = 54
    /// Lowest point of the resting bead in scene units (anchor + cord + bead).
    static let restBottom = WIRE + AY + L + 27
    /// The app-wide appearance change waits at least this long after the click…
    static let flipNotBefore: Double = 0.35
    /// …and until the light has (nearly) finished opening or closing, but no longer than this.
    static let flipNotAfter: Double = 0.8
    /// Reduce Motion crossfade between the rooms.
    static let crossfadeDuration: Double = 0.25

    private(set) var snap = Snapshot()
    private(set) var hapticTick = 0
    @ObservationIgnored var onFlip: ((Bool) -> Void)?

    @ObservationIgnored private var TH = MotionSpring(0, 46, 3)      // lamp angle
    @ObservationIgnored private var TUG = MotionSpring(0, 300, 13)   // lamp drop
    @ObservationIgnored private var R = MotionSpring(0, 120, 21)     // light radius
    @ObservationIgnored private var BP = MotionSpring(1, 420, 13)    // bulb pop
    @ObservationIgnored private var HX = MotionSpring(0, 210, 22)    // the scripted hand of a tap
    @ObservationIgnored private var HY = MotionSpring(0, 210, 22)
    // how far the cord is stretched: it eases back, so letting go is a bounce and not a whip
    @ObservationIgnored private var K = MotionSpring(1, 300, 17)

    private struct Held { var x: Double; var y: Double; var ox: Double; var oy: Double; var moved: Double; var sx: Double; var sy: Double; var flipped: Bool }

    @ObservationIgnored private var on = false
    @ObservationIgnored private var armed = true
    @ObservationIgnored private var held: Held?
    @ObservationIgnored private var ignoringTouch = false
    @ObservationIgnored private var ghost = false
    @ObservationIgnored private var stretch: Double = 0
    @ObservationIgnored private var lean: Double = 0
    @ObservationIgnored private var side: Double = 1
    @ObservationIgnored private var W: Double = 0
    @ObservationIgnored private var H: Double = 0
    @ObservationIgnored private var shift: Double = 0
    @ObservationIgnored private var pts: [Point] = []
    @ObservationIgnored private var pendingTimers = 0
    @ObservationIgnored private var started = false
    /// Reduce Motion: opacity of the light room (0 dark … 1 light).
    @ObservationIgnored private var fade: Double = 0
    /// A flip the app hasn't been told about yet, and the time since the click.
    @ObservationIgnored private var pendingFlip: Bool?
    @ObservationIgnored private var sinceFlip: Double = 0
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    // MARK: Geometry

    private func anchor() -> (Double, Double) {
        let c = cos(TH.x), s = sin(TH.x), y = Self.WIRE + TUG.x + Self.AY
        return (W / 2 + Self.AX * c - y * s, Self.AX * s + y * c)
    }

    private func bulbAt() -> (Double, Double) {
        let c = cos(TH.x), s = sin(TH.x), y = Self.WIRE + TUG.x + 63
        return (W / 2 - y * s, y * c)
    }

    func setSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard size.width != W || size.height != H else { return }
        let dx = size.width / 2 - W / 2
        W = size.width; H = size.height
        // The original sits in a tall card; in a short one the wire runs up past the top edge.
        shift = min(0, H - 14 - Self.restBottom)
        if pts.isEmpty {
            let (ax, ay) = anchor()
            pts = (0...Self.N).map { Point(x: ax, y: ay + Double($0) * Self.SEG) }
        } else {
            for i in pts.indices { pts[i].x += dx }
        }
        render()
    }

    // MARK: Inputs

    func start(on value: Bool) {
        guard !started else { return }
        started = true
        on = value
        if on { R.snap(1) }
        fade = on ? 1 : 0
        render()
    }

    /// The binding changed from outside (system appearance, the reset button): the lamp follows.
    func external(_ value: Bool) {
        guard value != on else { return }
        flip(to: value, fromUser: false)
    }

    private func flip(to: Bool, fromUser: Bool) {
        guard to != on else { return }
        on = to
        if !MotionSettings.reduceMotion {
            BP.x = on ? 1.35 : 0.8
            TUG.v += 150
        }
        clock.start()
        guard fromUser else { pendingFlip = nil; return }
        hapticTick += 1
        // Tell the app once the light has finished opening, so the whole UI re-rendering
        // for the new appearance doesn't hitch the wipe mid-way (see `render`).
        pendingFlip = on
        sinceFlip = 0
    }

    /// Light (or crossfade) is close enough to its target that the app can change underneath.
    private var lightLanded: Bool {
        MotionSettings.reduceMotion ? abs(fade - (on ? 1 : 0)) < 0.02 : abs(R.x - R.t) < 0.05
    }

    private func later(_ seconds: Double, _ fn: @escaping () -> Void) {
        pendingTimers += 1
        clock.after(seconds) { [weak self] in
            self?.pendingTimers -= 1
            fn()
        }
    }

    /// What holds the bead: the finger, or the scripted hand of a tap.
    private func pin() -> (Double, Double)? {
        if let held { return (held.x, held.y) }
        if ghost { return (HX.x, HY.x) }
        return nil
    }

    /// One scripted pull (a tap, or the accessibility default action).
    func pull() {
        guard !ghost, held == nil, !pts.isEmpty else { return }
        let b = pts[Self.N]
        ghost = true; armed = true; side = -side
        HX.x = b.x; HY.x = b.y; HX.v = b.vx; HY.v = b.vy
        let (ax, ay) = anchor()
        HX.t = ax + side * 26; HY.t = ay + Self.L + 64
        later(1.1) { [weak self] in self?.ghost = false }   // let go even if it never clicked
        clock.start()
    }

    /// Touch in card coordinates; the scene is shifted, so convert.
    func hold(start: CGPoint, at location: CGPoint) {
        guard !pts.isEmpty, !ignoringTouch else { return }
        let x = location.x, y = location.y - shift
        if held == nil {
            clock.maxFramesPerSecond = 120
            let sx = start.x, sy = start.y - shift
            let b = pts[Self.N]
            // hit area 44×52 around the bead (22 either side, 12 above, 40 below)
            guard sx >= b.x - 22, sx <= b.x + 22, sy >= b.y - 12, sy <= b.y + 40 else {
                ignoringTouch = true
                clock.maxFramesPerSecond = 60
                return
            }
            held = Held(x: b.x, y: b.y, ox: b.x - sx, oy: b.y - sy, moved: 0, sx: sx, sy: sy, flipped: false)
            ghost = false; armed = true
        }
        guard var h = held else { return }
        h.x = x + h.ox; h.y = y + h.oy
        h.moved = max(h.moved, hypot(x - h.sx, y - h.sy))
        held = h
        clock.start()
    }

    func letGo() {
        defer { ignoringTouch = false }
        clock.maxFramesPerSecond = 60
        guard let h = held else { return }
        let tap = h.moved < 5 && !h.flipped
        held = nil
        clock.start()
        if tap { pull() }
    }

    // MARK: Simulation

    private func frame(_ dt: Double) {
        if pendingFlip != nil { sinceFlip += dt }
        let fadeTarget: Double = on ? 1 : 0
        if fade != fadeTarget {
            let stepBy = dt / Self.crossfadeDuration
            fade = fade < fadeTarget ? min(fadeTarget, fade + stepBy) : max(fadeTarget, fade - stepBy)
        }
        TH.step(dt); TUG.step(dt); R.step(dt); BP.step(dt); HX.step(dt); HY.step(dt); K.step(dt)
        guard dt > 0, pts.count == Self.N + 1 else { return }
        let N = Self.N, L = Self.L
        let (ax, ay) = anchor()
        let p = pin()

        // the held end: free inside the cord's reach, rubber past it
        var px = 0.0, py = 0.0
        stretch = 0; lean = 0
        if let p {
            let dx = p.0 - ax, dy = p.1 - ay
            let d = max(hypot(dx, dy), 1)
            let over = max(0, d - L), give = Self.MAXS * (1 - exp(-over / 70)), r = min(d, L) + give
            px = ax + dx / d * r; py = ay + dy / d * r
            stretch = give; lean = over > 0 ? dx / d : 0
            if over > 0 { K.x = r / L; K.t = r / L; K.v = 0 }
            if armed && give > Self.CLICK {
                armed = false
                flip(to: !on, fromUser: true)
                if held != nil { held?.flipped = true } else { later(0.12) { [weak self] in self?.ghost = false } }
            }
        }
        if p == nil || stretch == 0 { K.t = 1 }
        let seg = Self.SEG * max(1, K.x)
        TUG.t = stretch * 0.22
        TH.t = motionClamp(-lean * stretch / Self.MAXS * 0.5, -0.3, 0.3)

        // the rope: gravity, then links pulled back to length a few times
        let reduce = MotionSettings.reduceMotion
        let prev = pts
        for i in 1...N {
            // Reduce Motion: much heavier air, so the rope settles without swinging
            let damp = reduce ? 9.0 : (i == N ? 1.1 : 2.4)
            let k = exp(-damp * dt)
            var q = pts[i]
            q.vy += 2600 * dt; q.vx *= k; q.vy *= k
            let sp = hypot(q.vx, q.vy)
            if sp > 2600 { q.vx *= 2600 / sp; q.vy *= 2600 / sp }
            q.x += q.vx * dt; q.y += q.vy * dt
            pts[i] = q
        }
        for _ in 0..<8 {
            pts[0].x = ax; pts[0].y = ay
            if p != nil { pts[N].x = px; pts[N].y = py }
            for i in 0..<N {
                let a = pts[i], c = pts[i + 1]
                let dx = c.x - a.x, dy = c.y - a.y
                let d = max(hypot(dx, dy), 1e-6)
                let f = (d - seg) / d * 0.5
                // the bead is heavy
                let wa: Double = i == 0 ? 0 : 1
                let wc: Double = i + 1 == N ? (p != nil ? 0 : 0.3) : 1
                let sum = (wa + wc) == 0 ? 1 : wa + wc
                pts[i].x += dx * f * wa / sum * 2; pts[i].y += dy * f * wa / sum * 2
                pts[i + 1].x -= dx * f * wc / sum * 2; pts[i + 1].y -= dy * f * wc / sum * 2
            }
        }
        pts[0].x = ax; pts[0].y = ay
        if p != nil { pts[N].x = px; pts[N].y = py }
        for i in 1...N {
            pts[i].vx = (pts[i].x - prev[i].x) / dt
            pts[i].vy = (pts[i].y - prev[i].y) / dt
        }
        R.t = on ? 1 : 0
        if on { R.tune(120, 21) } else { R.tune(170, 27) }   // it opens wide and closes a little faster
    }

    private func render() {
        guard pts.count == Self.N + 1, W > 0 else { return }
        var s = Snapshot()
        s.size = CGSize(width: W, height: H)
        s.shift = shift
        s.theta = TH.x
        s.tug = TUG.x
        s.bulbPop = BP.x
        s.rope = pts.map { CGPoint(x: $0.x, y: $0.y) }
        let b = pts[Self.N], e = pts[Self.N - 1]
        s.bead = CGPoint(x: b.x, y: b.y)
        s.beadAngle = atan2(e.x - b.x, b.y - e.y)
        // light: a circle from the bulb, big enough to pass the far corner of the card
        let (bx, by) = bulbAt()
        let byCard = by + shift
        let far = hypot(max(bx, W - bx), max(byCard, H - byCard)) + 24
        s.lightCentre = CGPoint(x: bx, y: by)
        if MotionSettings.reduceMotion {
            // No wipe: the light room covers the card and crossfades in.
            s.crossfade = true
            s.lightRadius = fade > 0 ? far : 0
            s.lightOpacity = fade
        } else {
            s.lightRadius = max(0, R.x) * far
        }
        if s != snap { snap = s }

        if let flipped = pendingFlip,
           sinceFlip >= Self.flipNotBefore && (lightLanded || sinceFlip >= Self.flipNotAfter) {
            pendingFlip = nil
            if flipped == on { onFlip?(flipped) }
        }

        // pause when nothing moves: the lamp's slow swing ends well before 0.001 rad
        let springs = TH.isSettled(within: 0.002) && TUG.isSettled(within: MotionSpring.points)
            && R.isSettled && BP.isSettled && K.isSettled
        let still = pts.allSatisfy { abs($0.vx) < 2 && abs($0.vy) < 2 }
        let crossfading = fade != (on ? 1 : 0)
        if held == nil && !ghost && pendingTimers == 0 && pendingFlip == nil && !crossfading
            && springs && still && clock.isRunning {
            clock.stop()
        }
    }
}

// MARK: - Drawing

private enum PullCordRenderer {
    struct Palette {
        let background: Color, shade: Color, cap: Color, bulb: Color, rope: Color, bead: Color
    }

    private static func fixed(_ c: Color, _ style: UIUserInterfaceStyle) -> Color {
        Color(uiColor: UIColor(c).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
    }

    /// The same room twice, once in each theme, with tokens resolved for that theme
    /// so neither room changes when the app's appearance flips underneath it.
    static let dark = Palette(
        background: .rhino,
        shade: fixed(.surfaceSecondary, .dark),
        cap: fixed(.labelTertiary, .dark),
        bulb: fixed(.surfaceSecondary, .dark).opacity(0.9),
        rope: fixed(.labelTertiary, .dark),
        bead: fixed(.brandPrimary, .dark))

    static let light = Palette(
        background: fixed(.surface, .light),
        shade: fixed(.surfaceSecondary, .light),
        cap: fixed(.labelTertiary, .light),
        bulb: Color(hex: "#FFD23F"),   // lit: the colour stays on the bulb, never a halo behind it
        rope: fixed(.labelTertiary, .light),
        bead: fixed(.brandPrimary, .light))

    static func draw(_ s: PullCordEngine.Snapshot, in ctx: inout GraphicsContext, size: CGSize) {
        guard s.rope.count > 1 else {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark.background))
            return
        }
        room(s, dark, in: ctx, size: size)
        let r = s.lightRadius
        if s.crossfade {
            if s.lightOpacity > 0 {
                var lit = ctx
                lit.opacity = s.lightOpacity
                room(s, light, in: lit, size: size)
            }
        } else if r >= 4 {
            var lit = ctx
            let c = CGPoint(x: s.lightCentre.x, y: s.lightCentre.y + s.shift)
            lit.clip(to: Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)))
            room(s, light, in: lit, size: size)
        }
    }

    private static func room(_ s: PullCordEngine.Snapshot, _ pal: Palette, in base: GraphicsContext, size: CGSize) {
        base.fill(Path(CGRect(origin: .zero, size: size)), with: .color(pal.background))
        var ctx = base
        ctx.translateBy(x: 0, y: s.shift)
        let W = Double(s.size.width)
        let th = s.theta, tug = s.tug
        let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

        // wire, from the top of the scene to the lamp
        let wl = PullCordEngine.WIRE + tug - 4
        var wire = Path()
        wire.move(to: CGPoint(x: W / 2, y: -4))
        wire.addLine(to: CGPoint(x: W / 2 - sin(th) * wl, y: cos(th) * wl))
        ctx.stroke(wire, with: .color(pal.rope), style: stroke)

        // lamp: rotated about the top anchor, the head hangs at the end of the wire
        var lamp = ctx
        lamp.translateBy(x: W / 2, y: 0)
        lamp.rotate(by: .radians(th))
        lamp.translateBy(x: 0, y: PullCordEngine.WIRE + tug)
        // bulb (under the shade), popped about its centre
        var bulb = lamp
        bulb.translateBy(x: 0, y: 63)
        bulb.scaleBy(x: s.bulbPop, y: s.bulbPop)
        bulb.fill(Path(ellipseIn: CGRect(x: -19, y: -19, width: 38, height: 38)), with: .color(pal.bulb))
        // shade: big rounded top (62/58), small rounded bottom (12)
        lamp.fill(shadePath(), with: .color(pal.shade))
        // cap
        lamp.fill(Path(roundedRect: CGRect(x: -9, y: -10, width: 18, height: 14),
                       cornerRadii: RectangleCornerRadii(topLeading: 5, bottomLeading: 0, bottomTrailing: 0, topTrailing: 5)),
                  with: .color(pal.cap))

        // the cord, smoothed with quadratic curves through the link midpoints
        let p = s.rope
        var rope = Path()
        rope.move(to: p[0])
        for i in 1..<(p.count - 1) {
            rope.addQuadCurve(to: CGPoint(x: (p[i].x + p[i + 1].x) / 2, y: (p[i].y + p[i + 1].y) / 2), control: p[i])
        }
        rope.addLine(to: s.bead)
        ctx.stroke(rope, with: .color(pal.rope), style: stroke)

        // bead: a pill turned to the cord's direction, pivoting 3 pt below its top
        var bead = ctx
        bead.translateBy(x: s.bead.x, y: s.bead.y)
        bead.rotate(by: .radians(s.beadAngle))
        bead.fill(Path(roundedRect: CGRect(x: -8, y: -3, width: 16, height: 30), cornerRadius: 8), with: .color(pal.bead))
    }

    /// 124×66 with CSS radii `62px 62px 12px 12px / 58px 58px 12px 12px`, left edge at -62.
    /// The vertical radii add up to 70 on a 66 side, so CSS scales every radius by 66/70.
    private static func shadePath() -> Path {
        let w: Double = 124, h: Double = 66
        let f = min(1, w / (62 + 62), h / (58 + 12))
        let rx = 62 * f, ry = 58 * f, rb = 12 * f
        let x0 = -w / 2, x1 = w / 2
        let k = 0.5523   // quarter-ellipse bezier constant
        var p = Path()
        p.move(to: CGPoint(x: x0, y: ry))
        p.addCurve(to: CGPoint(x: x0 + rx, y: 0),
                   control1: CGPoint(x: x0, y: ry * (1 - k)), control2: CGPoint(x: x0 + rx * (1 - k), y: 0))
        p.addLine(to: CGPoint(x: x1 - rx, y: 0))
        p.addCurve(to: CGPoint(x: x1, y: ry),
                   control1: CGPoint(x: x1 - rx * (1 - k), y: 0), control2: CGPoint(x: x1, y: ry * (1 - k)))
        p.addLine(to: CGPoint(x: x1, y: h - rb))
        p.addCurve(to: CGPoint(x: x1 - rb, y: h),
                   control1: CGPoint(x: x1, y: h - rb * (1 - k)), control2: CGPoint(x: x1 - rb * (1 - k), y: h))
        p.addLine(to: CGPoint(x: x0 + rb, y: h))
        p.addCurve(to: CGPoint(x: x0, y: h - rb),
                   control1: CGPoint(x: x0 + rb * (1 - k), y: h), control2: CGPoint(x: x0, y: h - rb * (1 - k)))
        p.closeSubpath()
        return p
    }
}

// MARK: - Preview

#Preview("Pull Cord") {
    @Previewable @State var light = true
    VStack(spacing: 16) {
        PullCordToggle(isOn: $light)
            .frame(width: 280, height: 240)
            .premiumCard()
        Text(light ? "Light" : "Dark").font(.headline)
    }
    .padding()
    .preferredColorScheme(light ? .light : .dark)
}
