import SwiftUI

// MARK: - Bowl guide mover
//
// Where the floating bowl is on screen, and how it gets there. Held: it follows
// the finger 1:1 from the grab point (rubber-banded at the edges). Released: it
// is thrown with the finger's velocity, slows like a flicked PiP window
// (0.998 per ms, so it travels v/1000·0.998/(1−0.998)), bounces off the edges
// with some energy lost, lands with a squash and walks to the nearest resting
// spot on the left or right edge. Reduce Motion: no throw or bounce; release
// slides straight to the nearest spot on a critically damped spring.
//
// Coordinates are the guide's own region (above the tab bar, inside the safe
// area); `position` is the mascot's centre.

@MainActor
@Observable
final class BowlGuideMover {
    enum Phase { case resting, held, flying, settling }

    private(set) var position: CGPoint = .zero
    private(set) var phase: Phase = .resting
    /// Bumped on each landing, for a soft haptic.
    private(set) var landings = 0

    var isMoving: Bool { phase != .resting }

    @ObservationIgnored let rig: MascotRig
    /// Called when the bowl comes to rest: which side, and how far down (0 top … 1 bottom).
    @ObservationIgnored var onRest: ((_ leading: Bool, _ fraction: Double) -> Void)?

    @ObservationIgnored private var region: CGRect = .zero
    @ObservationIgnored private var radius: CGFloat = 38
    @ObservationIgnored private var inset = CGSize(width: 16, height: 8)
    @ObservationIgnored private var grab = CGPoint.zero
    @ObservationIgnored private var velocity = CGVector.zero
    @ObservationIgnored private var flightTime: Double = 0
    @ObservationIgnored private var peakSpeed: Double = 0
    @ObservationIgnored private var sx = MotionSpring(0, MotionTokens.soft)
    @ObservationIgnored private var sy = MotionSpring(0, MotionTokens.soft)
    @ObservationIgnored private var restLeading = false
    @ObservationIgnored private var restFraction: Double = 1
    @ObservationIgnored private let clock = MotionClock()
    /// False until the region is known, so the bowl never flashes at the origin.
    private(set) var isPlaced = false

    init(rig: MascotRig) {
        self.rig = rig
        clock.maxFramesPerSecond = 120
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    // MARK: Layout

    /// The guide's region and the mascot's half-size. Re-places a resting bowl.
    func configure(region: CGRect, radius: CGFloat, inset: CGSize, leading: Bool, fraction: Double) {
        let changed = region != self.region || radius != self.radius || !isPlaced
        self.region = region
        self.radius = radius
        self.inset = inset
        guard changed, region.width > 0, region.height > 0 else { return }
        if phase == .resting || !isPlaced {
            restLeading = leading
            restFraction = fraction
            snap(to: restPoint(leading: leading, fraction: fraction))
            isPlaced = true
        }
    }

    /// Allowed centres for a resting or flying bowl.
    private var lane: CGRect {
        let minX = region.minX + inset.width + radius
        let maxX = region.maxX - inset.width - radius
        // Stay clear of the screen's header, where the title and the profile
        // avatar live; a bowl resting there would cover them.
        let minY = region.minY + inset.height + radius + 96
        let maxY = region.maxY - inset.height - radius
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    func restPoint(leading: Bool, fraction: Double) -> CGPoint {
        let l = lane
        return CGPoint(x: leading ? l.minX : l.maxX, y: l.minY + l.height * motionClamp(fraction, 0, 1))
    }

    private func nearestRest(from p: CGPoint) -> (CGPoint, Bool, Double) {
        let l = lane
        let leading = p.x < l.midX
        let y = motionClamp(p.y, l.minY, l.maxY)
        let fraction = l.height > 0 ? (y - l.minY) / l.height : 1
        return (CGPoint(x: leading ? l.minX : l.maxX, y: y), leading, fraction)
    }

    // MARK: Moves

    /// Jump with no motion.
    func snap(to p: CGPoint) {
        clock.stop()
        phase = .resting
        position = p
        sx.snap(p.x); sy.snap(p.y)
        velocity = .zero
    }

    /// Glide (walking) to a resting spot, e.g. docking while the panel is open.
    func settle(leading: Bool, fraction: Double, remember: Bool = true) {
        guard isPlaced else { return }
        if remember { restLeading = leading; restFraction = fraction }
        beginSettling(to: restPoint(leading: leading, fraction: fraction), leading: leading, fraction: fraction, notify: remember)
    }

    func grab(at location: CGPoint) {
        clock.stop()
        grab = CGPoint(x: location.x - position.x, y: location.y - position.y)
        phase = .held
        rig.walk(speed: 0)
        rig.pickUp()
        lookAtFinger()
    }

    func drag(to location: CGPoint, velocity v: CGSize) {
        guard phase == .held else { return }
        let l = lane
        let x = motionRubber(location.x - grab.x, min: l.minX, max: l.maxX, give: 24)
        let y = motionRubber(location.y - grab.y, min: l.minY, max: l.maxY, give: 24)
        position = CGPoint(x: x, y: y)
        rig.drag(velocity: CGVector(dx: v.width, dy: v.height))
        lookAtFinger()
    }

    func release(velocity v: CGSize, reduceMotion: Bool) {
        guard phase == .held else { return }
        rig.look(at: nil)
        if reduceMotion {
            rig.land(impact: 0)
            let (p, leading, fraction) = nearestRest(from: position)
            beginSettling(to: p, leading: leading, fraction: fraction, notify: true)
            return
        }
        velocity = CGVector(dx: v.width, dy: v.height)
        peakSpeed = speed
        flightTime = 0
        rig.drop()
        phase = .flying
        clock.start()
    }

    /// Where a throw released now would come to rest (for tests and debugging).
    func projected(from p: CGPoint, velocity v: CGSize) -> CGPoint {
        let d = 0.998
        let k = d / (1 - d) / 1000
        return CGPoint(x: p.x + v.width * k, y: p.y + v.height * k)
    }

    func stop() {
        clock.stop()
        if phase != .resting && phase != .held { snap(to: restPoint(leading: restLeading, fraction: restFraction)) }
    }

    // MARK: Simulation

    private var speed: Double { (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot() }

    private func lookAtFinger() {
        rig.look(at: CGPoint(x: grab.x / max(radius, 1), y: grab.y / max(radius, 1)))
    }

    private func beginSettling(to p: CGPoint, leading: Bool, fraction: Double, notify: Bool) {
        sx.x = position.x; sy.x = position.y
        sx.v = phase == .flying ? velocity.dx : 0
        sy.v = phase == .flying ? velocity.dy : 0
        sx.t = p.x; sy.t = p.y
        phase = .settling
        pendingRest = notify ? (leading, fraction) : nil
        let distance = hypot(p.x - position.x, p.y - position.y)
        rig.walk(speed: distance > 14 ? 1.1 : 0)
        clock.start()
    }

    @ObservationIgnored private var pendingRest: (Bool, Double)?

    private func frame(_ dt: Double) {
        switch phase {
        case .flying:
            flightTime += dt
            let decay = pow(0.998, dt * 1000)
            velocity = CGVector(dx: velocity.dx * decay, dy: velocity.dy * decay)
            var p = CGPoint(x: position.x + velocity.dx * dt, y: position.y + velocity.dy * dt)
            let l = lane
            // Rubber walls: reflect with energy loss, a little give past the edge.
            if p.x < l.minX { p.x = l.minX + (l.minX - p.x) * 0.3; velocity.dx = bounced(velocity.dx) }
            if p.x > l.maxX { p.x = l.maxX - (p.x - l.maxX) * 0.3; velocity.dx = bounced(velocity.dx) }
            if p.y < l.minY { p.y = l.minY + (l.minY - p.y) * 0.3; velocity.dy = bounced(velocity.dy) }
            if p.y > l.maxY { p.y = l.maxY - (p.y - l.maxY) * 0.3; velocity.dy = bounced(velocity.dy) }
            position = p
            if speed < 90 || flightTime > 3 {
                rig.land(impact: motionClamp(0.25 + peakSpeed / 3200, 0.25, 1))
                landings += 1
                let (rest, leading, fraction) = nearestRest(from: position)
                restLeading = leading; restFraction = fraction
                beginSettling(to: rest, leading: leading, fraction: fraction, notify: true)
            }
        case .settling:
            sx.step(dt); sy.step(dt)
            position = CGPoint(x: sx.x, y: sy.x)
            let remaining = hypot(sx.t - sx.x, sy.t - sy.x)
            if remaining < 6 { rig.walk(speed: 0) }
        case .resting, .held:
            break
        }
    }

    private func bounced(_ v: Double) -> Double {
        rig.land(impact: motionClamp(abs(v) / 2600, 0, 0.7))
        return -v * 0.62
    }

    private func render() {
        guard phase == .settling, sx.isSettled(within: MotionSpring.points), sy.isSettled(within: MotionSpring.points) else { return }
        position = CGPoint(x: sx.t, y: sy.t)
        sx.snap(sx.t); sy.snap(sy.t)
        phase = .resting
        rig.walk(speed: 0)
        clock.stop()
        if let (leading, fraction) = pendingRest {
            pendingRest = nil
            onRest?(leading, fraction)
        }
    }
}
