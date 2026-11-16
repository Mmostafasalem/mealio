import SwiftUI

// MARK: - Jelly Slider
//
// Port of designbookmark.com/motion "Jelly Slider" (jelly-slider/slider.js).
// The thumb follows the finger through a spring and stretches with its speed.
// While dragging, a value drop rises out of the thumb; both sit in one goo layer
// (blur + alpha threshold), so the drop peels off like liquid and melts back in
// on release. Dragging past either end meets rubber resistance and snaps back.
// The thumb travels inside the track: its centre runs from R to width - R, so it
// sits flush with the track at both ends and the tick labels line up with it.

struct JellySlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { "\(Int($0))" }
    var tickLabels: [Double]? = nil

    @State private var engine = JellySliderEngine()

    init(value: Binding<Double>,
         in range: ClosedRange<Double>,
         step: Double = 1,
         format: @escaping (Double) -> String = { "\(Int($0))" },
         tickLabels: [Double]? = nil) {
        self._value = value
        self.range = range
        self.step = step
        self.format = format
        self.tickLabels = tickLabels
    }

    /// Room kept above the rail for the drop to rise into (rise 38 + radius 18 + blur).
    private static let headroom: CGFloat = 50

    var body: some View {
        let s = engine.snap
        VStack(spacing: 8) {
            rail(s)
            scale(s)
        }
        .contentShape(Rectangle())
        .gesture(drag)
        .padding(.top, Self.headroom)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { engine.setWidth($0) }
        .onAppear {
            engine.configure(range: range, step: step)
            engine.place(value)
        }
        .onChange(of: engine.emitted) { _, new in
            if let new, new != value { value = new }
        }
        .onChange(of: value) { _, new in
            // A typed value (or any outside change) glides the thumb there.
            if engine.emitted != new { engine.glide(to: new) }
        }
        .sensoryFeedback(.selection, trigger: engine.hapticTick)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: engine.nudge(+1)
            case .decrement: engine.nudge(-1)
            @unknown default: break
            }
        }
    }

    // MARK: Rail: track, fill, goo (thumb + drop) and the drop label

    private func rail(_ s: JellySliderEngine.Snapshot) -> some View {
        let E = JellySliderEngine.self
        // The goo layer only covers the blobs: a small box centred between thumb and drop,
        // so the blur + threshold pass costs the same at any slider width.
        let gooLeft = (s.x + s.dropX) / 2 - E.gooWidth / 2
        return Color.clear
            .frame(height: E.railHeight)
            .overlay { JellyTrack(fill: s.fill).allowsHitTesting(false) }
            .overlay(alignment: .topLeading) {
                Canvas { ctx, _ in drawGoo(s, left: gooLeft, in: &ctx) }
                    .frame(width: E.gooWidth, height: E.gooHeight)
                    .offset(x: gooLeft, y: -E.oy)
                    .allowsHitTesting(false)
            }
            .overlay {
                if s.reduced {
                    // Reduce Motion: the bubble waits in place above the thumb and fades.
                    Circle()
                        .fill(Color.brandPrimary)
                        .frame(width: 2 * E.dropR, height: 2 * E.dropR)
                        .position(x: s.dropX, y: s.dropY)
                        .opacity(s.labelOpacity)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if s.labelOpacity > 0.01 {
                    JellyDropLabel(text: format(s.labelValue))
                        .scaleEffect(s.dropScale)
                        .rotationEffect(.degrees(s.tilt))
                        .opacity(s.labelOpacity)
                        .position(x: s.dropX, y: s.dropY)
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .allowsHitTesting(false)
                }
            }
    }

    private func drawGoo(_ s: JellySliderEngine.Snapshot, left: Double, in ctx: inout GraphicsContext) {
        let oy = JellySliderEngine.oy
        guard s.width > 0 else { return }
        // goo: blur the blobs, then cut the blur at half alpha, so they fuse into one liquid shape
        ctx.drawLayer { goo in
            goo.addFilter(.alphaThreshold(min: 0.5, color: .brandPrimary))
            goo.addFilter(.blur(radius: JellySliderEngine.blur))
            goo.drawLayer { blobs in
                if !s.reduced {
                    // drop: rises and leans the way it is being dragged from
                    var d = blobs
                    d.translateBy(x: s.dropX - left, y: oy + s.dropY)
                    d.rotate(by: .degrees(s.tilt))
                    d.scaleBy(x: s.dropScale, y: s.dropScale)
                    let D = JellySliderEngine.dropR
                    d.fill(Path(ellipseIn: CGRect(x: -D, y: -D, width: 2 * D, height: 2 * D)), with: .color(.black))
                }

                // thumb: stretched along the track with speed, area preserving
                var t = blobs
                t.translateBy(x: s.x - left, y: oy + JellySliderEngine.cy)
                t.scaleBy(x: s.thumbSX, y: s.thumbSY)
                let TR = JellySliderEngine.thumbDrawR
                t.fill(Path(ellipseIn: CGRect(x: -TR, y: -TR, width: 2 * TR, height: 2 * TR)), with: .color(.black))
            }
        }
    }

    // MARK: Scale under the track: a mark every 5 %, major every 25 %; passed ones light up

    private func scale(_ s: JellySliderEngine.Snapshot) -> some View {
        let R = JellySliderEngine.R
        let span = max(s.width - 2 * R, 1)
        let lo = range.lowerBound, hi = range.upperBound
        let current = value
        let labels = tickLabels ?? stride(from: 0.0, through: 1.0, by: 0.25).map { lo + $0 * (hi - lo) }
        return VStack(spacing: 6) {
            JellyTicks(litPercent: s.litPercent)
                .frame(height: 8)

            ZStack(alignment: .topLeading) {
                ForEach(labels, id: \.self) { v in
                    let p = (v - lo) / max(hi - lo, .ulpOfOne)
                    let on = v <= current && current > lo
                    Text(format(v))
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(on ? Color.labelSecondary : Color.labelTertiary)
                        .animation(.easeOut(duration: 0.2), value: on)
                        .fixedSize()
                        .position(x: R + motionClamp(p, 0, 1) * span, y: 7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 14, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }

    // MARK: Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in engine.drag(to: g.location.x) }
            .onEnded { _ in engine.release() }
    }
}

// MARK: - Pieces

/// Track and fill. Redraws only when the fill length changes.
private struct JellyTrack: View, Equatable {
    let fill: Double

    var body: some View {
        Canvas { ctx, size in
            // track (6 tall, 13 from the rail top) and fill, clipped to the track
            let track = Path(roundedRect: CGRect(x: 0, y: 13, width: size.width, height: 6), cornerRadius: 3)
            ctx.fill(track, with: .color(.surfaceSecondary))
            if fill > 0.5 {
                var clipped = ctx
                clipped.clip(to: track)
                clipped.fill(Path(roundedRect: CGRect(x: 0, y: 13, width: fill, height: 6), cornerRadius: 3),
                             with: .color(.brandPrimary))
            }
        }
        .frame(height: JellySliderEngine.railHeight)
    }
}

/// The marks under the track. Takes only the rounded lit percentage, so it redraws
/// when a mark lights up, not every frame.
private struct JellyTicks: View, Equatable {
    let litPercent: Double

    var body: some View {
        Canvas { ctx, size in
            let R = JellySliderEngine.R
            let span = max(size.width - 2 * R, 1)
            guard size.width > 0 else { return }
            for i in 0...20 {
                let p = Double(i) / 20
                let major = i % 5 == 0
                let on = p * 100 <= litPercent && litPercent > 0
                let x = R + p * span
                let h: CGFloat = major ? 8 : 4
                let color: Color = major
                    ? (on ? .labelPrimary : .labelTertiary)
                    : (on ? .labelSecondary : .surfaceSecondary)
                ctx.fill(Path(roundedRect: CGRect(x: x - 0.75, y: 0, width: 1.5, height: h), cornerRadius: 1),
                         with: .color(color))
            }
        }
    }
}

/// The value riding in the drop. Its text is laid out again only when the value changes;
/// the per-frame motion is transforms on top.
private struct JellyDropLabel: View, Equatable {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Color.jellyOnLiquid)
            .fixedSize()
    }
}

// MARK: - Engine

@MainActor
@Observable
final class JellySliderEngine {
    /// Everything the view needs for one frame.
    struct Snapshot: Equatable {
        var width: Double = 0
        var x: Double = 0
        var thumbSX: Double = 1
        var thumbSY: Double = 1
        var dropX: Double = 0
        var dropY: Double = 0
        var dropScale: Double = 0.5
        var tilt: Double = 0
        var labelOpacity: Double = 0
        var labelValue: Double = 0
        var fill: Double = 0
        var litPercent: Double = 0
        /// Reduce Motion: no goo drop, the bubble fades in place.
        var reduced = false
    }

    // R thumb radius, D drop radius, CY track centre inside the rail, OX/OY goo layer offset.
    // The goo trims about 2 pt off the edge, so the thumb is drawn at 14 to read as 12.
    static let R: Double = 12
    static let thumbDrawR: Double = 14
    static let dropR: Double = 18
    static let ox: Double = 40
    static let oy: Double = 80
    static let cy: Double = 16
    static let rise: Double = -38
    static let restDrop: Double = 0.5
    static let railHeight: Double = 32
    static let blur: Double = MotionTokens.sliderBlur
    /// The goo box around thumb and drop: wide enough for the drop's lag and the blur,
    /// tall enough for the risen drop (oy above the rail, 28 below it).
    static let gooWidth: Double = 120
    static let gooHeight: Double = 140

    private(set) var snap = Snapshot()
    /// Last value this slider wrote to the binding (or accepted from it).
    private(set) var emitted: Double?
    /// Bumped whenever the user moves the value onto a new step.
    private(set) var hapticTick = 0

    @ObservationIgnored private var lo: Double = 0
    @ObservationIgnored private var hi: Double = 100
    @ObservationIgnored private var stepSize: Double = 1
    @ObservationIgnored private var width: Double = 0
    @ObservationIgnored private var ratio: Double = 0.4
    @ObservationIgnored private var dragging = false
    @ObservationIgnored private var lifted = false
    @ObservationIgnored private var liftTimer: Int?

    @ObservationIgnored private var X = MotionSpring(0, MotionTokens.sliderFollow)   // thumb centre x
    @ObservationIgnored private var DX = MotionSpring(0, 260, 18)                     // drop x lags behind => it leans
    @ObservationIgnored private var DY = MotionSpring(JellySliderEngine.cy, MotionTokens.sliderBubble)   // drop centre y
    @ObservationIgnored private var DS = MotionSpring(JellySliderEngine.restDrop, MotionTokens.sliderBubble) // drop scale
    @ObservationIgnored private var PS = MotionSpring(1, 520, 16)                     // thumb press scale
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    // MARK: Mapping

    private var span: Double { max(width - 2 * Self.R, 1) }
    private func toX(_ r: Double) -> Double { Self.R + r * span }
    private func toRatio(_ x: Double) -> Double { motionClamp((x - Self.R) / span, 0, 1) }
    private func ratio(of v: Double) -> Double { motionClamp((v - lo) / max(hi - lo, .ulpOfOne), 0, 1) }
    /// Ratio => the nearest value on the step grid.
    private func stepped(_ r: Double) -> Double {
        let raw = lo + r * (hi - lo)
        guard stepSize > 0 else { return raw }
        return motionClamp(lo + ((raw - lo) / stepSize).rounded() * stepSize, lo, hi)
    }

    // MARK: Inputs

    func configure(range: ClosedRange<Double>, step: Double) {
        lo = range.lowerBound
        hi = range.upperBound
        stepSize = step
    }

    /// Put the thumb on a value with no motion.
    func place(_ v: Double) {
        ratio = ratio(of: v)
        emitted = v
        let x = toX(ratio)
        X.snap(x); DX.snap(x)
        render()
    }

    func setWidth(_ w: Double) {
        guard w > 0, w != width else { return }
        width = w
        let x = toX(ratio)
        X.snap(x); DX.snap(x)
        render()
    }

    /// Glide to a value without a jump: typed values, accessibility steps.
    func glide(to v: Double) {
        emitted = v
        X.tune(MotionTokens.sliderGlide)
        X.t = toX(ratio(of: v))
        clock.start()
    }

    /// One step up or down (VoiceOver adjustable action). The drop lifts briefly, like keyboard focus in the original.
    func nudge(_ dir: Double) {
        let current = emitted ?? stepped(toRatio(X.t))
        let next = motionClamp(current + dir * stepSize, lo, hi)
        guard next != current else { return }
        glide(to: next)
        hapticTick += 1
        lifted = true
        sync()
        if let liftTimer { clock.cancel(liftTimer) }
        liftTimer = clock.after(0.9) { [weak self] in
            self?.lifted = false
            self?.liftTimer = nil
            self?.sync()
        }
    }

    func drag(to localX: Double) {
        guard width > 0 else { return }
        if !dragging {
            dragging = true
            clock.maxFramesPerSecond = 120
            X.tune(MotionTokens.sliderFollow)
            sync()
        }
        X.t = motionRubber(localX, min: Self.R, max: width - Self.R)
        emit(stepped(toRatio(X.t)))
        clock.start()
    }

    func release() {
        guard dragging else { return }
        dragging = false
        clock.maxFramesPerSecond = 60
        X.tune(MotionTokens.sliderRelease)
        // The target is clamped back inside the track and lands on the step grid.
        let v = stepped(toRatio(motionClamp(X.t, Self.R, width - Self.R)))
        X.t = toX(ratio(of: v))
        emit(v)
        sync()
        clock.start()
    }

    private func emit(_ v: Double) {
        guard v != emitted else { return }
        emitted = v
        hapticTick += 1
    }

    private func sync() {
        let up = dragging || lifted
        if MotionSettings.reduceMotion {
            // No rise: the bubble already sits above the thumb; only its opacity moves.
            DY.snap(Self.cy + Self.rise)
            DS.t = up ? 1 : 0
        } else {
            DY.t = up ? Self.cy + Self.rise : Self.cy
            DS.t = up ? 1 : Self.restDrop
        }
        PS.t = dragging ? 1.16 : 1
    }

    // MARK: Simulation

    private func frame(_ dt: Double) {
        DX.t = X.x
        if MotionSettings.reduceMotion { DX.snap(X.x) }
        if width > 2 * Self.R { ratio = toRatio(X.t) }
        X.step(dt); DX.step(dt); DY.step(dt); DS.step(dt); PS.step(dt)
    }

    private func render() {
        let x = X.x
        let reduce = MotionSettings.reduceMotion
        // stretch along the track with speed, area preserving (none with Reduce Motion)
        let st = reduce ? 1 : 1 + min(abs(X.v) / 2400, 0.4)
        var s = Snapshot()
        s.reduced = reduce
        s.width = width
        s.x = x
        s.thumbSX = st * PS.x
        s.thumbSY = PS.x / st
        s.dropX = DX.x
        s.dropY = DY.x
        if reduce {
            s.dropX = X.x
            s.dropScale = 1
            s.tilt = 0
            s.labelOpacity = motionClamp(DS.x, 0, 1)
        } else {
            s.dropScale = DS.x
            s.tilt = motionClamp((DX.x - X.x) * 0.9, -28, 28)
            s.labelOpacity = motionClamp((DS.x - 0.7) / 0.25, 0, 1)
        }
        let r = toRatio(x)
        s.labelValue = stepped(r)
        // the fill ends under the thumb centre, and is gone by the time the thumb sits at 0
        s.fill = motionClamp(x, 0, max(width, 0)) * motionClamp((x - Self.R) / Self.R, 0, 1)
        s.litPercent = (r * 100).rounded()
        if s != snap { snap = s }

        let settled = X.isSettled(within: MotionSpring.points) && DX.isSettled(within: MotionSpring.points)
            && DY.isSettled(within: MotionSpring.points) && DS.isSettled && PS.isSettled
        if !dragging && liftTimer == nil && settled && clock.isRunning { clock.stop() }
    }
}

private extension Color {
    /// Text on the liquid: almond on rhino in light mode, rhino on almond in dark mode.
    static let jellyOnLiquid = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(Color.rhino) : UIColor(Color.almond)
    })
}

// MARK: - Preview

#Preview("Jelly Slider") {
    @Previewable @State var budget: Double = 60
    VStack(spacing: 24) {
        JellySlider(value: $budget, in: 10...300, step: 5,
                    format: { "€\(Int($0))" }, tickLabels: [10, 50, 100, 200, 300])
            .accessibilityLabel("Weekly budget")
        Text("€\(Int(budget))").font(.title2.weight(.semibold)).monospacedDigit()
        Button("Set to 150") { budget = 150 }
    }
    .padding(32)
    .background(Color.surface)
}
