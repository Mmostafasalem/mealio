import SwiftUI
import QuartzCore

// MARK: - Spring physics
//
// A direct port of the tiny engine behind designbookmark.com/motion (shared/motion.js),
// so the components built from it move exactly like the originals. A spring is
// "stiffness damping" with unit mass:  a = -k·(x - target) - c·v.
// Token values live in `MotionTokens`; a component only adds its own when it truly
// needs a different feel.

struct MotionSpring {
    /// Current value.
    var x: Double
    /// Current velocity (units per second).
    var v: Double = 0
    /// Target the spring pulls toward.
    var t: Double
    var k: Double
    /// The designed damping. The damping actually applied is `c`, which follows
    /// Reduce Motion live (critically damped while it is on), so a spring created
    /// before the person toggles the setting still obeys it on the next frame.
    var damping: Double
    var c: Double {
        get { MotionSettings.reduceMotion ? 2 * k.squareRoot() : damping }
        set { damping = newValue }
    }

    init(_ x: Double, _ k: Double, _ c: Double) {
        self.x = x
        self.t = x
        self.k = k
        self.damping = c
    }

    init(_ x: Double, _ preset: MotionTokens.Preset) {
        self.init(x, preset.k, preset.c)
    }

    /// Change stiffness and damping. Reduce Motion makes every spring critically damped.
    mutating func tune(_ k: Double, _ c: Double) {
        self.k = k
        self.damping = c
    }

    mutating func tune(_ preset: MotionTokens.Preset) { tune(preset.k, preset.c) }

    /// Advance by `dt` seconds (semi-implicit Euler, same as the original).
    mutating func step(_ dt: Double) {
        let a = -k * (x - t) - c * v
        v += a * dt
        x += v * dt
    }

    /// Jump straight to a value with no motion.
    mutating func snap(_ value: Double) {
        x = value
        t = value
        v = 0
    }

    /// Settled for unit-scale values (opacity, 0…1 progress, scale).
    var isSettled: Bool { isSettled(within: 0.001) }

    /// Settled within `epsilon` of the target, in the spring's own units, with a
    /// velocity that can't visibly move it any more. Use `MotionSpring.points`
    /// for springs measured in points, `MotionSpring.degrees` for angles in degrees.
    func isSettled(within epsilon: Double) -> Bool {
        abs(x - t) < epsilon && abs(v) < epsilon * 4
    }

    /// Below a quarter point nothing visibly moves, even at 3× scale.
    static let points: Double = 0.25
    static let degrees: Double = 0.1
    /// Font weight on the 100…900 axis.
    static let fontWeight: Double = 1
}

// MARK: - Tokens (stiffness, damping) from tokens.css

enum MotionTokens {
    struct Preset {
        let k: Double
        let c: Double
    }
    /// Something held by the pointer: no overshoot, no lag.
    static let follow = Preset(k: 900, c: 50)
    /// Letting go, landing on a value: one small overshoot.
    static let settle = Preset(k: 280, c: 22)
    /// Large moves: panels, sheets, the whole component shifting.
    static let soft = Preset(k: 260, c: 24)
    /// Stretchy highlight: the edge facing the move.
    static let lead = Preset(k: 620, c: 36)
    /// Stretchy highlight: the edge that lags, this makes the stretch.
    static let trail = Preset(k: 190, c: 19)
    /// Icon or number pop on select.
    static let pop = Preset(k: 520, c: 16)
    /// Opacity and small slides.
    static let fade = Preset(k: 420, c: 32)
    /// Seconds between items entering one after another.
    static let stagger: Double = 0.045

    // Jelly Slider
    static let sliderFollow = Preset(k: 900, c: 50)
    static let sliderBubble = Preset(k: 420, c: 22)
    static let sliderRelease = Preset(k: 300, c: 14)
    static let sliderGlide = Preset(k: 420, c: 34)
    static let sliderBlur: Double = 8
}

// MARK: - Settings

enum MotionSettings {
    /// Mirrors `prefers-reduced-motion`; springs become critically damped and
    /// decorative autoplay stops. Cached and kept current by the system
    /// notification, because it is read on every spring step.
    @MainActor static var reduceMotion: Bool {
        if !observing { startObserving() }
        return cached
    }

    @MainActor private static var cached = UIAccessibility.isReduceMotionEnabled
    @MainActor private static var observing = false

    @MainActor private static func startObserving() {
        observing = true
        NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { cached = UIAccessibility.isReduceMotionEnabled }
        }
    }
}

// MARK: - Clock
//
// One display link per component. Calls `frame(dt)` with four sub-steps per
// frame (like the original) and then `render()`. Pause it when nothing moves so
// an idle screen costs nothing.

@MainActor
final class MotionClock {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var timers: [(id: Int, remaining: Double, fn: () -> Void)] = []
    private var nextTimer = 0
    /// Simulation step, called four times per frame with a quarter of the frame's dt.
    var frame: ((Double) -> Void)?
    /// Called once per frame after stepping; publish state for SwiftUI here.
    var render: (() -> Void)?

    var isRunning: Bool { link != nil }

    /// Creating a clock touches no UI, so it can be a stored-property default in
    /// models that aren't main-actor isolated (Xcode 16.4 rejects that otherwise).
    /// Everything that drives the display link stays on the main actor.
    nonisolated init() {}

    /// Frame-rate ceiling. 60 is plenty for decorative and state motion and halves
    /// the cost on ProMotion iPhones; pass 120 for motion that follows a finger.
    var maxFramesPerSecond: Float = 60 {
        didSet { link?.preferredFrameRateRange = frameRange }
    }

    private var frameRange: CAFrameRateRange {
        CAFrameRateRange(minimum: min(30, maxFramesPerSecond), maximum: maxFramesPerSecond, preferred: maxFramesPerSecond)
    }

    func start() {
        guard link == nil else { return }
        let proxy = Proxy { [weak self] now in self?.tick(now) }
        let l = CADisplayLink(target: proxy, selector: #selector(Proxy.fire(_:)))
        l.preferredFrameRateRange = frameRange
        l.add(to: .main, forMode: .common)
        last = CACurrentMediaTime()
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// Run `fn` after `seconds` of simulation time (pauses with the clock). Returns a token for `cancel`.
    @discardableResult
    func after(_ seconds: Double, _ fn: @escaping () -> Void) -> Int {
        nextTimer += 1
        timers.append((nextTimer, seconds, fn))
        start()
        return nextTimer
    }

    func cancel(_ token: Int) { timers.removeAll { $0.id == token } }

    func cancelAllTimers() { timers.removeAll() }

    private func tick(_ now: CFTimeInterval) {
        let dt = min(now - last, 1.0 / 30.0)
        last = now
        var due: [() -> Void] = []
        timers = timers.compactMap { t in
            let r = t.remaining - dt
            if r <= 0 { due.append(t.fn); return nil }
            return (t.id, r, t.fn)
        }
        due.forEach { $0() }
        let sub = 4
        for _ in 0..<sub { frame?(dt / Double(sub)) }
        render?()
    }

    private final class Proxy: NSObject {
        let handler: (CFTimeInterval) -> Void
        init(_ handler: @escaping (CFTimeInterval) -> Void) { self.handler = handler }
        @objc func fire(_ link: CADisplayLink) { handler(link.timestamp) }
    }

    deinit { link?.invalidate() }
}

// MARK: - Helpers

@inline(__always) func motionClamp(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }

/// Rubber-band resistance past a limit, as in the original slider: the further you pull, the less it gives.
func motionRubber(_ x: Double, min lo: Double, max hi: Double, give d: Double = 18) -> Double {
    if x < lo { return lo - (1 - 1 / ((lo - x) * 0.55 / d + 1)) * d }
    if x > hi { return hi + (1 - 1 / ((x - hi) * 0.55 / d + 1)) * d }
    return x
}

/// Continuous font weight (CSS 100…900) mapped onto the system font's variable weight axis.
extension UIFont.Weight {
    static func css(_ w: Double) -> UIFont.Weight {
        // Anchor points of the SF weight axis.
        let table: [(Double, CGFloat)] = [
            (100, UIFont.Weight.ultraLight.rawValue), (200, UIFont.Weight.thin.rawValue),
            (300, UIFont.Weight.light.rawValue), (400, UIFont.Weight.regular.rawValue),
            (500, UIFont.Weight.medium.rawValue), (600, UIFont.Weight.semibold.rawValue),
            (700, UIFont.Weight.bold.rawValue), (800, UIFont.Weight.heavy.rawValue),
            (900, UIFont.Weight.black.rawValue),
        ]
        let w = motionClamp(w, 100, 900)
        for i in 0..<(table.count - 1) {
            let (a, ra) = table[i], (b, rb) = table[i + 1]
            if w <= b {
                let f = CGFloat((w - a) / (b - a))
                return UIFont.Weight(rawValue: ra + (rb - ra) * f)
            }
        }
        return .black
    }
}
