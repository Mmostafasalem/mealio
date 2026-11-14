import SwiftUI

// MARK: - Goo Thinking Bubble
//
// Port of designbookmark.com/motion "Goo Thinking" (goo-thinking/think.js).
// Thinking: three dots hop one after another inside a pill. They sit in one goo
// layer (blur + alpha threshold), so each hopping dot is pulled out of its
// neighbours like a drop. Answered: the dots slide into one, the drop sinks away
// and the pill springs open into the reply bubble, sized to the reply content.
// Tapping while it merges skips straight to the open bubble. Under Reduce Motion
// the dots stay put and pulse their opacity in turn, so a pending answer never
// looks frozen.

struct GooThinkingBubble<Reply: View>: View {
    /// False while the answer is pending. Flip to true (or create with true) to merge and open.
    var isAnswered: Bool
    /// What VoiceOver reads once answered. While thinking it reads "Nourlo is thinking".
    var accessibilityText: String
    @ViewBuilder var reply: () -> Reply

    @State private var engine = GooThinkingEngine()
    @State private var onScreen = false
    @Environment(\.scenePhase) private var scenePhase

    init(isAnswered: Bool, accessibilityText: String = "", @ViewBuilder reply: @escaping () -> Reply) {
        self.isAnswered = isAnswered
        self.accessibilityText = accessibilityText
        self.reply = reply
    }

    var body: some View {
        let s = engine.snap
        GooFrameLayout(size: CGSize(width: s.w, height: s.h)) {
            reply()
                .opacity(motionClamp(s.reply, 0, 1))
                .offset(y: (1 - s.reply) * 8)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { engine.setContent($0) }
        }
        .background(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Color.surfaceElevated
                if s.dotScale > 0.01 {
                    Canvas { ctx, _ in draw(s, in: &ctx) }
                        .frame(width: GooThinkingEngine.pillW, height: GooThinkingEngine.pillH)
                        .allowsHitTesting(false)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: s.radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: s.radius, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded { if isAnswered { engine.skip() } })
        .onAppear {
            onScreen = true
            isAnswered ? engine.answer() : engine.think()
            if scenePhase != .active { engine.pause() }
        }
        .onDisappear { onScreen = false; engine.pause() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { engine.pause() } else if onScreen { engine.resume() }
        }
        .onChange(of: isAnswered) { _, answered in answered ? engine.answer() : engine.think() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isAnswered ? accessibilityText : String(localized: "Nourlo is thinking"))
    }

    private func draw(_ s: GooThinkingEngine.Snapshot, in ctx: inout GraphicsContext) {
        if let pulse = s.pulse {
            // Reduce Motion: crisp dots at rest, opacity pulsing in turn (the goo
            // threshold would flatten any opacity, so they are drawn outside it).
            let r = GooThinkingEngine.dotR
            for (i, p) in s.dots.enumerated() {
                let cx = p.x + r
                let cy = GooThinkingEngine.dotTop + p.y + r
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)),
                         with: .color(Color.labelSecondary.opacity(pulse[i])))
            }
            return
        }
        // goo: blur the dots, then cut the blur at the source's threshold (alpha·20 − 8 ⇒ 0.4)
        ctx.drawLayer { goo in
            goo.addFilter(.alphaThreshold(min: 0.4, color: .labelSecondary))
            goo.addFilter(.blur(radius: GooThinkingEngine.blur))
            goo.drawLayer { dots in
                let r = GooThinkingEngine.dotR * s.dotScale
                for p in s.dots {
                    // dot boxes are 9×9 and scale about their centre, as in the CSS
                    let cx = p.x + GooThinkingEngine.dotR
                    let cy = GooThinkingEngine.dotTop + p.y + GooThinkingEngine.dotR
                    dots.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)),
                              with: .color(.black))
                }
            }
        }
    }
}

extension GooThinkingBubble where Reply == EmptyView {
    /// Thinking dots only, for a pending answer.
    init() {
        self.init(isAnswered: false) { EmptyView() }
    }
}

// MARK: - Layout: reports the spring size, lets the reply lay out at its natural size (clipped by the bubble)

private struct GooFrameLayout: Layout {
    var size: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { size }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = proposal.width ?? bounds.width
        for sub in subviews {
            sub.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: width, height: nil))
        }
    }
}

// MARK: - Engine

@MainActor
@Observable
final class GooThinkingEngine {
    struct Snapshot: Equatable {
        var w: Double = GooThinkingEngine.pillW
        var h: Double = GooThinkingEngine.pillH
        var dots: [CGPoint] = (0..<3).map { CGPoint(x: GooThinkingEngine.restX($0), y: 0) }
        var dotScale: Double = 1
        var reply: Double = 0
        /// Reduce Motion while thinking: each dot's opacity. nil draws the goo dots.
        var pulse: [Double]? = nil

        /// A full pill while small, the chat bubble's 18 once open.
        var radius: Double { min(h / 2, max(18, 20 - (h - 40) * 0.5)) }
    }

    enum Phase { case idle, think, merge, open }

    // Geometry from think.css: a 64×40 pill, 9 pt dots 13 apart, 15.5 from the top.
    static let pillW: Double = 64
    static let pillH: Double = 40
    static let dotR: Double = 4.5
    static let dotTop: Double = 15.5
    static let blur: Double = 3.2
    nonisolated static func restX(_ i: Int) -> Double { 19 + Double(i) * 13 }
    static let mergedX: Double = 32 - 4.5

    // Spring tunings from think.js; `think()` restores them after an open.
    static let sizeTune = MotionTokens.Preset(k: 240, c: 24)
    static let dotXTune = MotionTokens.Preset(k: 300, c: 22)
    /// Dot hop. think.js uses 420/14 (ratio ≈ 0.34); 22 (≈ 0.54) keeps the hop but drops the wobble.
    static let dotYTune = MotionTokens.Preset(k: 420, c: 22)

    // Reduce Motion pulse: 0.35 → 1 → 0.35 over 0.9 s, each dot 0.15 s after the last.
    static let pulseCycle: Double = 0.9
    static let pulseStagger: Double = 0.15
    static let pulseLow: Double = 0.35

    private(set) var snap = Snapshot()

    @ObservationIgnored private var phase: Phase = .idle
    @ObservationIgnored private var content: CGSize = .zero
    @ObservationIgnored private var hop: Double = 0.3
    @ObservationIgnored private var k = 0
    @ObservationIgnored private var timers: [Int] = []
    /// Thinking under Reduce Motion: dots pulse instead of hopping.
    @ObservationIgnored private var pulsing = false
    @ObservationIgnored private var pulseTime: Double = 0

    // Exact values from think.js.
    @ObservationIgnored private var W = MotionSpring(GooThinkingEngine.pillW, GooThinkingEngine.sizeTune)
    @ObservationIgnored private var H = MotionSpring(GooThinkingEngine.pillH, GooThinkingEngine.sizeTune)
    @ObservationIgnored private var drop = MotionSpring(1, 300, 26)
    @ObservationIgnored private var A = MotionSpring(0, 260, 28)
    @ObservationIgnored private var big = MotionSpring(1, 300, 24)
    @ObservationIgnored private var dx: [MotionSpring] = (0..<3).map { MotionSpring(GooThinkingEngine.restX($0), GooThinkingEngine.dotXTune) }
    @ObservationIgnored private var dy: [MotionSpring] = (0..<3).map { _ in MotionSpring(0, GooThinkingEngine.dotYTune) }
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    // MARK: Inputs

    func think() {
        guard phase != .think else { resume(); return }
        clearTimers()
        phase = .think
        // open() retunes the size springs for growing with the reply; thinking uses think.js's.
        W.tune(Self.sizeTune); H.tune(Self.sizeTune)
        for i in 0..<3 { dx[i].tune(Self.dotXTune); dy[i].tune(Self.dotYTune) }
        A.t = 0
        W.t = Self.pillW; H.t = Self.pillH
        for i in 0..<3 { dx[i].t = Self.restX(i); dy[i].t = 0 }
        drop.t = 1; big.t = 1
        hop = 0.3; k = 0
        if MotionSettings.reduceMotion {
            // dots at rest, pulsing
            A.snap(0); W.snap(Self.pillW); H.snap(Self.pillH); drop.snap(1); big.snap(1)
            startPulse()
            render()
        } else {
            stopPulse()
        }
        clock.start()
    }

    func answer() {
        guard phase == .idle || phase == .think else { resume(); return }
        stopPulse()
        if MotionSettings.reduceMotion { skip(); return }
        phase = .merge
        for i in 0..<3 { dx[i].t = Self.mergedX; dy[i].t = 0 }   // run together in the middle
        big.t = 1.45
        later(0.45) { [weak self] in self?.drop.t = 0 }          // the drop sinks away
        later(0.6) { [weak self] in self?.open() }
        clock.start()
    }

    /// Straight to the open bubble (tap, or Reduce Motion).
    func skip() {
        guard phase != .open || A.t < 1 else { return }
        clearTimers()
        stopPulse()
        for i in 0..<3 { dx[i].snap(Self.mergedX); dy[i].snap(0) }
        drop.snap(0)
        phase = .open
        sizeToContent()
        A.t = 1
        if MotionSettings.reduceMotion {
            A.snap(1)
            if content != .zero { W.snap(content.width); H.snap(content.height) }
            render()
            return
        }
        clock.start()
    }

    func setContent(_ size: CGSize) {
        guard size != content else { return }
        content = size
        guard phase == .open else { return }
        if MotionSettings.reduceMotion {
            W.snap(size.width); H.snap(size.height)
            render()
        } else {
            sizeToContent()
            clock.start()
        }
    }

    /// Stop the clock (off screen, or the app is not active). Timers pause with it.
    func pause() { clock.stop() }

    func resume() {
        if phase != .idle { clock.start() }
    }

    private func startPulse() {
        pulsing = true
        pulseTime = 0
        for i in 0..<3 { dx[i].snap(Self.restX(i)); dy[i].snap(0) }
        clock.maxFramesPerSecond = 30   // a slow opacity pulse needs no more
    }

    private func stopPulse() {
        pulsing = false
        clock.maxFramesPerSecond = 60
    }

    private func open() {
        phase = .open
        sizeToContent()
        later(0.12) { [weak self] in
            guard let self else { return }
            self.A.t = 1
            // From here the bubble grows with the reply: Streaming Reply's size springs.
            self.W.tune(260, 26); self.H.tune(260, 26)
        }
    }

    private func sizeToContent() {
        guard content.width > 0, content.height > 0 else { return }
        W.t = content.width
        H.t = content.height
    }

    private func later(_ s: Double, _ fn: @escaping () -> Void) {
        var token = 0
        token = clock.after(s) { [weak self] in
            self?.timers.removeAll { $0 == token }
            fn()
        }
        timers.append(token)
    }

    private func clearTimers() {
        timers.forEach { clock.cancel($0) }
        timers.removeAll()
    }

    // MARK: Simulation

    private func frame(_ dt: Double) {
        // One dot hops at a time, left to right, then a short rest.
        // Reduce Motion is checked once per cycle, so turning it on (or off) mid-think
        // switches between hopping and pulsing at a clean boundary.
        if phase == .think && pulsing {
            pulseTime += dt
            if pulseTime >= Self.pulseCycle {
                pulseTime -= Self.pulseCycle
                if !MotionSettings.reduceMotion { stopPulse(); hop = 0; k = 0 }
            }
            return
        }
        if phase == .think {
            hop -= dt
            if hop <= 0 {
                if k % 3 == 0 && MotionSettings.reduceMotion {
                    startPulse()
                    return
                }
                dy[k % 3].v = -95
                k += 1
                hop = k % 3 != 0 ? 0.16 : 0.46
            }
        }
        W.step(dt); H.step(dt); drop.step(dt); A.step(dt); big.step(dt)
        for i in 0..<3 { dx[i].step(dt); dy[i].step(dt) }
    }

    private func render() {
        var s = Snapshot()
        s.w = max(W.x, 1)
        s.h = max(H.x, 1)
        s.dots = (0..<3).map { CGPoint(x: dx[$0].x, y: dy[$0].x) }
        // Merged, the three read as one bigger drop; then the drop sinks to nothing.
        s.dotScale = max(0, motionClamp(drop.x, 0, 1.2) * big.x)
        s.reply = A.x
        if phase == .think && pulsing {
            s.pulse = (0..<3).map { i in
                let t = (pulseTime - Double(i) * Self.pulseStagger) / Self.pulseCycle
                let wave = 0.5 - 0.5 * cos(2 * Double.pi * t)   // 0 → 1 → 0 per cycle
                return Self.pulseLow + (1 - Self.pulseLow) * wave
            }
        }
        if s != snap { snap = s }

        guard phase != .think, timers.isEmpty else { return }
        let pts = MotionSpring.points
        let settled = W.isSettled(within: pts) && H.isSettled(within: pts)
            && drop.isSettled && A.isSettled && big.isSettled
            && dx.allSatisfy { $0.isSettled(within: pts) } && dy.allSatisfy { $0.isSettled(within: pts) }
        if settled && clock.isRunning { clock.stop() }
    }
}

// MARK: - Preview

#Preview("Goo Thinking") {
    @Previewable @State var answered = false
    VStack(alignment: .leading, spacing: 24) {
        GooThinkingBubble(isAnswered: answered,
                          accessibilityText: "Try a lentil bowl with the spinach and feta you have.") {
            Text("Try a lentil bowl with the spinach and feta you have. It covers most of the protein you still need today.")
                .font(.subheadline)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
        }
        .id(answered)
        .padding(.trailing, 60)
        .frame(maxWidth: .infinity, alignment: .leading)

        Button(answered ? "Ask again" : "Answer") { answered.toggle() }
            .buttonStyle(.borderedProminent)
    }
    .padding(Spacing.lg)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Color.surfaceGrouped)
}
