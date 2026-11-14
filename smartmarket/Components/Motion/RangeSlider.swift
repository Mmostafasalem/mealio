import SwiftUI

// MARK: - Range Slider
//
// Port of designbookmark.com/motion "Range Slider" (range-slider/range.js).
// Each thumb follows its value on a spring (260, 24) and its bubble tilts and
// stretches with the thumb's speed. When the thumbs come closer than a bubble's
// width, a merge spring (300, 26) slides the two bubbles to the middle and fades
// them into one centred bubble with the whole range ("€1.20–€3.40").
//
// The thumbs never overlap: each runs in its own lane, offset by `gap`, so equal
// values sit side by side instead of hiding one thumb under the other.
// Reduce Motion: no tilt or stretch, and the springs are critically damped.
// VoiceOver: each thumb is its own adjustable element.

struct RangeSlider: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let bounds: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String
    var lowerLabel: String
    var upperLabel: String

    @State private var engine = RangeSliderEngine()

    init(lower: Binding<Double>,
         upper: Binding<Double>,
         in bounds: ClosedRange<Double>,
         step: Double = 1,
         lowerLabel: String = "Minimum",
         upperLabel: String = "Maximum",
         format: @escaping (Double) -> String = { "\(Int($0))" }) {
        self._lower = lower
        self._upper = upper
        self.bounds = bounds
        self.step = step
        self.lowerLabel = lowerLabel
        self.upperLabel = upperLabel
        self.format = format
    }

    /// Room above the track for the bubbles (12 of air + a bubble + its lean).
    private static let headroom: CGFloat = 46

    var body: some View {
        let s = engine.snap
        let E = RangeSliderEngine.self
        ZStack(alignment: .topLeading) {
            // track + fill
            Capsule().fill(Color.progressTrack)
                .frame(height: 4)
                .offset(y: E.thumb / 2 - 2)
            Capsule().fill(Color.progress)
                .frame(width: max(0, s.xb - s.xa), height: 4)
                .offset(x: s.xa, y: E.thumb / 2 - 2)

            thumb(x: s.xa, label: lowerLabel, value: lower, isLower: true)
            thumb(x: s.xb, label: upperLabel, value: upper, isLower: false)

            // bubbles: separate ones slide to the middle as they fade into the merged one
            bubble(format(s.va), x: s.bubbleA, tilt: s.tiltA, stretch: s.stretchA,
                   opacity: 1 - s.merge, scale: 1 - 0.2 * s.merge) { engine.setBubbleWidth($0, at: 0) }
            bubble(format(s.vb), x: s.bubbleB, tilt: s.tiltB, stretch: s.stretchB,
                   opacity: 1 - s.merge, scale: 1 - 0.2 * s.merge) { engine.setBubbleWidth($0, at: 1) }
            bubble(format(s.va) + "–" + format(s.vb), x: (s.xa + s.xb) / 2, tilt: s.tiltM, stretch: 1,
                   opacity: s.merge, scale: 0.8 + 0.2 * s.merge) { _ in }
        }
        .frame(maxWidth: .infinity, minHeight: E.thumb, maxHeight: E.thumb, alignment: .topLeading)
        .transaction { $0.animation = nil }
        .contentShape(Rectangle().inset(by: -8))
        .gesture(drag)
        .padding(.top, Self.headroom)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { engine.setWidth($0) }
        .onAppear {
            engine.configure(bounds: bounds, step: step)
            engine.place(lower: lower, upper: upper)
        }
        .onChange(of: bounds) { _, b in
            engine.configure(bounds: b, step: step)
            engine.place(lower: lower, upper: upper)
        }
        .onChange(of: engine.emittedLower) { _, v in if let v, v != lower { lower = v } }
        .onChange(of: engine.emittedUpper) { _, v in if let v, v != upper { upper = v } }
        .onChange(of: lower) { _, v in if engine.emittedLower != v { engine.glide(lower: v, upper: upper) } }
        .onChange(of: upper) { _, v in if engine.emittedUpper != v { engine.glide(lower: lower, upper: v) } }
        .onDisappear { engine.stop() }
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    private func thumb(x: Double, label: String, value: Double, isLower: Bool) -> some View {
        let d = RangeSliderEngine.thumb
        return Circle()
            .fill(Color.brandPrimary)
            .overlay(Circle().strokeBorder(Color.surface, lineWidth: 2))
            .frame(width: d, height: d)
            .elevation(Elevation.low)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .offset(x: x - 22, y: d / 2 - 22)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(format(value))
            .accessibilityAdjustableAction { direction in
                let dir: Double = direction == .increment ? 1 : (direction == .decrement ? -1 : 0)
                guard dir != 0 else { return }
                if isLower {
                    lower = motionClamp(engine.snapToGrid(lower + dir * step), bounds.lowerBound, upper)
                } else {
                    upper = motionClamp(engine.snapToGrid(upper + dir * step), lower, bounds.upperBound)
                }
            }
    }

    private func bubble(_ text: String, x: Double, tilt: Double, stretch: Double,
                        opacity: Double, scale: Double, width: @escaping (Double) -> Void) -> some View {
        RangeBubbleLabel(text: text)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width($0) }
            // lean and stretch around the bubble's bottom edge, like transform-origin 50% 100%
            .scaleEffect(x: stretch * scale, y: scale / stretch, anchor: .bottom)
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .opacity(opacity)
            // zero-size box: the bubble's bottom centre sits on the point, and its
            // size never feeds back into the slider's layout
            .frame(width: 0, height: 0, alignment: .bottom)
            .offset(x: x, y: -12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in engine.drag(start: g.startLocation.x, to: g.location.x) }
            .onEnded { _ in engine.release() }
    }
}

/// The price in a bubble. Laid out again only when its text changes.
private struct RangeBubbleLabel: View, Equatable {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color.surface)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

// MARK: - Engine

@MainActor
@Observable
final class RangeSliderEngine {
    struct Snapshot: Equatable {
        var xa: Double = 0
        var xb: Double = 0
        var va: Double = 0
        var vb: Double = 0
        var bubbleA: Double = 0
        var bubbleB: Double = 0
        var tiltA: Double = 0
        var tiltB: Double = 0
        var tiltM: Double = 0
        var stretchA: Double = 1
        var stretchB: Double = 1
        var merge: Double = 0
    }

    /// Thumb diameter, from range.css.
    static let thumb: Double = 28
    /// Lane offset between the thumbs so equal values never stack.
    static let gap: Double = 30
    /// Thumb spring from range.js.
    static let thumbSpring = MotionTokens.Preset(k: 260, c: 24)
    /// Merge spring from range.js.
    static let mergeSpring = MotionTokens.Preset(k: 300, c: 26)

    private(set) var snap = Snapshot()
    private(set) var emittedLower: Double?
    private(set) var emittedUpper: Double?

    @ObservationIgnored private var lo: Double = 0
    @ObservationIgnored private var hi: Double = 1
    @ObservationIgnored private var stepSize: Double = 1
    @ObservationIgnored private var width: Double = 0
    @ObservationIgnored private var ra: Double = 0
    @ObservationIgnored private var rb: Double = 1
    @ObservationIgnored private var bubbleW: [Double] = [52, 52]
    @ObservationIgnored private var dragging: Int?   // 0 lower, 1 upper
    @ObservationIgnored private var grab: Double = 0
    @ObservationIgnored private var A = MotionSpring(0, RangeSliderEngine.thumbSpring)
    @ObservationIgnored private var B = MotionSpring(0, RangeSliderEngine.thumbSpring)
    @ObservationIgnored private var M = MotionSpring(0, RangeSliderEngine.mergeSpring)
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    // MARK: Mapping. The lower thumb runs from R to w-R-gap, the upper from R+gap to w-R.

    private static var R: Double { thumb / 2 }
    private var lane: Double { max(width - 2 * Self.R - Self.gap, 1) }
    private func xA(_ r: Double) -> Double { Self.R + r * lane }
    private func xB(_ r: Double) -> Double { Self.R + Self.gap + r * lane }
    private func rA(_ x: Double) -> Double { motionClamp((x - Self.R) / lane, 0, 1) }
    private func rB(_ x: Double) -> Double { motionClamp((x - Self.R - Self.gap) / lane, 0, 1) }
    private func ratio(of v: Double) -> Double { motionClamp((v - lo) / max(hi - lo, .ulpOfOne), 0, 1) }
    private func value(_ r: Double) -> Double { snapToGrid(lo + r * (hi - lo)) }

    /// Nearest value on the step grid, inside the bounds.
    func snapToGrid(_ v: Double) -> Double {
        guard stepSize > 0 else { return motionClamp(v, lo, hi) }
        let n = ((v - lo) / stepSize).rounded()
        // round away float noise (0.30000000004)
        let snapped = ((lo + n * stepSize) * 1e6).rounded() / 1e6
        return motionClamp(snapped, lo, hi)
    }

    // MARK: Inputs

    func configure(bounds: ClosedRange<Double>, step: Double) {
        lo = bounds.lowerBound
        hi = bounds.upperBound
        stepSize = step
    }

    func place(lower: Double, upper: Double) {
        ra = ratio(of: lower); rb = max(ra, ratio(of: upper))
        emittedLower = lower; emittedUpper = upper
        A.snap(xA(ra)); B.snap(xB(rb))
        M.snap(needsMerge() ? 1 : 0)
        render()
    }

    func setWidth(_ w: Double) {
        guard w > 0, w != width else { return }
        width = w
        A.snap(xA(ra)); B.snap(xB(rb))
        M.snap(needsMerge() ? 1 : 0)
        render()
    }

    func setBubbleWidth(_ w: Double, at i: Int) {
        guard w > 0, abs(bubbleW[i] - w) > 0.5 else { return }
        bubbleW[i] = w
        if !clock.isRunning { M.t = needsMerge() ? 1 : 0; if !M.isSettled { clock.start() } }
    }

    /// An outside change (accessibility step, "Clear filter") glides the thumbs there.
    func glide(lower: Double, upper: Double) {
        emittedLower = lower; emittedUpper = upper
        ra = ratio(of: lower); rb = max(ra, ratio(of: upper))
        A.t = xA(ra); B.t = xB(rb)
        clock.start()
    }

    func drag(start: Double, to x: Double) {
        guard width > 0 else { return }
        if dragging == nil {
            // the nearer thumb takes the touch; keep the grab offset so it doesn't jump
            let which = abs(start - A.x) <= abs(start - B.x) ? 0 : 1
            dragging = which
            grab = (which == 0 ? A.x : B.x) - start
            clock.maxFramesPerSecond = 120
        }
        let target = x + grab
        if dragging == 0 {
            ra = min(rA(target), rb)
            A.t = xA(ra)
            emit(lower: value(ra), upper: nil)
        } else {
            rb = max(rB(target), ra)
            B.t = xB(rb)
            emit(lower: nil, upper: value(rb))
        }
        clock.start()
    }

    func release() {
        guard dragging != nil else { return }
        dragging = nil
        clock.maxFramesPerSecond = 60
        // land on the step grid
        let a = value(ra), b = max(a, value(rb))
        ra = ratio(of: a); rb = ratio(of: b)
        A.t = xA(ra); B.t = xB(rb)
        emit(lower: a, upper: b)
        clock.start()
    }

    func stop() {
        clock.stop()
        dragging = nil
        A.snap(A.t); B.snap(B.t); M.snap(M.t)
        render()
    }

    private func emit(lower: Double?, upper: Double?) {
        if let lower, lower != emittedLower { emittedLower = lower }
        if let upper, upper != emittedUpper { emittedUpper = upper }
    }

    private func needsMerge() -> Bool {
        (B.x - A.x) < (bubbleW[0] + bubbleW[1]) / 2 + 8
    }

    // MARK: Simulation

    private func frame(_ dt: Double) {
        A.step(dt); B.step(dt); M.step(dt)
    }

    private func render() {
        let reduce = MotionSettings.reduceMotion
        M.t = needsMerge() ? 1 : 0
        let m = motionClamp(M.x, 0, 1)
        let tilt: (Double) -> Double = { v in reduce ? 0 : motionClamp(v * -0.02, -12, 12) }
        let stretch: (Double) -> Double = { v in reduce ? 1 : 1 + min(abs(v) / 2400, 0.15) }
        var s = Snapshot()
        s.xa = A.x
        s.xb = max(A.x, B.x)
        s.va = value(rA(A.x))
        s.vb = max(s.va, value(rB(B.x)))
        let mid = (s.xa + s.xb) / 2
        s.bubbleA = s.xa + (mid - s.xa) * m
        s.bubbleB = s.xb + (mid - s.xb) * m
        s.tiltA = tilt(A.v); s.tiltB = tilt(B.v); s.tiltM = tilt((A.v + B.v) / 2)
        s.stretchA = stretch(A.v); s.stretchB = stretch(B.v)
        s.merge = m
        if s != snap { snap = s }

        if dragging == nil, clock.isRunning,
           A.isSettled(within: MotionSpring.points), B.isSettled(within: MotionSpring.points), M.isSettled {
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Range Slider") {
    @Previewable @State var low: Double = 1.2
    @Previewable @State var high: Double = 3.4
    let euro: (Double) -> String = { String(format: "€%.2f", $0) }
    VStack(alignment: .leading, spacing: 16) {
        Text("Price").font(.headline)
        RangeSlider(lower: $low, upper: $high, in: 0.3...12, step: 0.1,
                    lowerLabel: "Minimum price", upperLabel: "Maximum price", format: euro)
        Text("\(euro(low)) – \(euro(high))").font(.subheadline).monospacedDigit()
        Button("Clear filter") { low = 0.3; high = 12 }
    }
    .padding(24)
    .background(Color.surface)
}
