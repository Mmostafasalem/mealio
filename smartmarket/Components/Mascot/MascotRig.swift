import SwiftUI

// MARK: - Mascot rig
//
// The Nourlo bowl as a set of independent parts, each on its own `MotionSpring`:
// body (squash/stretch with volume kept, tilt, bob, hop), the bowl contents and
// every fruit piece (a secondary jiggle that lags the body), eyes, mouth, cheeks,
// brows, both arms and both feet. Every frame the rig composes targets from the
// mood, the running gesture and the idle loops, steps the springs and publishes
// one `MascotPose` that `MascotFigure` draws.
//
// Cost: one `MotionClock`, running only while something moves. Idle life
// (breathing, blinks, glances, mood loops) runs only while the host says the
// mascot is visible and the app is active (`setActive`), capped at 30 fps;
// gestures run at 60, a finger drag at 120. Reduce Motion: no idle loops, no
// squash or jiggle, no limb motion; a mood change only cross-fades the face.

enum MascotReaction {
    case tap
}

/// Everything the drawing needs for one frame. Units are the 512-point design
/// space of the original artwork; angles are radians.
struct MascotPose: Equatable {
    struct Arm: Equatable {
        /// Rotation around the shoulder; positive raises the hand.
        var raise: Double = 0
        /// Vertical shift of the shoulder; positive is down.
        var lift: Double = 0
        /// Shift toward the body's centre line.
        var reach: Double = 0
    }

    struct Foot: Equatable {
        /// Positive lifts the foot, negative lets it hang lower.
        var lift: Double = 0
        var rotation: Double = 0
    }

    // Whole figure
    var altitude: Double = 0
    var bob: Double = 0
    var breathe: Double = 1
    var scaleX: Double = 1
    var scaleY: Double = 1
    var tilt: Double = 0
    var stretch: Double = 0
    var stretchAngle: Double = 0
    var shadow: Double = 1

    // Bowl contents (secondary motion)
    var contentX: Double = 0
    var contentY: Double = 0
    var contentTilt: Double = 0
    /// Bananas 0…2, strawberries 3…5.
    var fruitY: [Double] = Array(repeating: 0, count: 6)
    var fruitRotation: [Double] = Array(repeating: 0, count: 6)

    // Face
    var lookX: Double = 0
    var lookY: Double = 0
    /// Blink: 1 open, 0.1 shut (vertical scale of the eye).
    var blink: Double = 1
    var squint: Double = 0
    var wide: Double = 0
    var sleepy: Double = 0
    var smile: Double = 1
    var ooh: Double = 0
    var wavy: Double = 0
    var grin: Double = 0
    var blush: Double = 0.3
    var brows: Double = 0

    // Limbs
    var armL = Arm()
    var armR = Arm()
    var footL = Foot()
    var footR = Foot()
}

@MainActor
@Observable
final class MascotRig {
    /// Published once per frame.
    private(set) var pose = MascotPose()
    private(set) var mood: MascotMood = .idle

    /// Follows the system setting; the view keeps it in sync with the environment.
    var reduceMotion: Bool = MotionSettings.reduceMotion {
        didSet {
            guard reduceMotion != oldValue else { return }
            if reduceMotion {
                beatTask?.cancel(); breathPhase = 0
                held = false; falling = false; airborne = false; airY = 0; airV = 0
                walkSpeed = 0; waveUntil = -1; events.removeAll()
                composeTargets()
                snapBodyAndLimbs()
                render()
            }
            wake()
        }
    }

    @ObservationIgnored private let clock = MotionClock()
    @ObservationIgnored private var springs: [MotionSpring] = S.allCases.map { MotionSpring($0.rest, $0.preset.k, $0.preset.c) }
    @ObservationIgnored private var t: Double = 0
    @ObservationIgnored private var active = false
    @ObservationIgnored private var hasMood = false

    // Gesture state
    @ObservationIgnored private var held = false
    @ObservationIgnored private var falling = false
    @ObservationIgnored private var fallingSince: Double = 0
    @ObservationIgnored private var airborne = false
    @ObservationIgnored private var airY: Double = 0
    @ObservationIgnored private var airV: Double = 0
    @ObservationIgnored private var crouchUntil: Double = -1
    @ObservationIgnored private var dragVelocity = CGVector.zero
    @ObservationIgnored private var waveUntil: Double = -1
    @ObservationIgnored private var busyUntil: Double = -1
    @ObservationIgnored private var walkSpeed: Double = 0
    @ObservationIgnored private var walkPhase: Double = 0
    @ObservationIgnored private var events: [(at: Double, fn: () -> Void)] = []

    // Idle life
    @ObservationIgnored private var breathPhase: Double = 0
    /// Full idle life (breathing, glances, mood beats) runs for a few seconds after
    /// appearing or any interaction; then the clock rests and only wakes for short
    /// beats (a blink or a glance every 3–6 s). An app that is never idle costs
    /// battery and keeps UI automation waiting.
    @ObservationIgnored private var lifeUntil: Double = -1
    @ObservationIgnored private var beatUntil: Double = -1
    @ObservationIgnored private var beatTask: Task<Void, Never>?
    @ObservationIgnored private var blinkStart: Double = -1
    @ObservationIgnored private var nextBlink: Double = .random(in: 3...6)
    @ObservationIgnored private var nextGlance: Double = .random(in: 4...8)
    @ObservationIgnored private var glanceUntil: Double = -1
    @ObservationIgnored private var glanceTarget = CGPoint.zero
    @ObservationIgnored private var nextMoodBeat: Double = .infinity
    @ObservationIgnored private var explicitLook: CGPoint?
    @ObservationIgnored private var flash: Expression?
    @ObservationIgnored private var flashUntil: Double = -1

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
        composeTargets()
        snapAll()
        render()
    }

    // MARK: Public API

    /// Change mood. The first call snaps; later calls blend, and play the mood's
    /// entrance (a hop for celebrate, a wave for help) unless Reduce Motion is on.
    func set(mood newMood: MascotMood) {
        let first = !hasMood
        hasMood = true
        guard first || newMood != mood else { return }
        mood = newMood
        nextMoodBeat = .infinity
        if first || !active {
            composeTargets()
            snapAll()
            render()
            scheduleMoodBeat(entering: false)
            return
        }
        if !reduceMotion {
            switch newMood {
            case .celebrate: hop()
            case .help: wave()
            case .thinking, .happy:
                springs[S.sq.rawValue].v += -1.2
            case .idle, .sleepy: break
            }
        }
        scheduleMoodBeat(entering: true)
        busy(0.6)
        liven(6)
        wake()
    }

    /// Where the eyes look, in mascot-local unit coordinates: (0, 0) is the
    /// mascot's centre and ±1 its edges (larger values are clamped to the
    /// direction). `nil` looks forward and resumes idle glances.
    func look(at point: CGPoint?) {
        if let p = point {
            let len = (p.x * p.x + p.y * p.y).squareRoot()
            explicitLook = len > 1 ? CGPoint(x: p.x / len, y: p.y / len) : p
        } else {
            explicitLook = nil
        }
        wake()
    }

    /// The host started holding the mascot (finger down + lift).
    func pickUp() {
        held = true
        falling = false
        airborne = false; airY = 0; airV = 0
        dragVelocity = .zero
        if !reduceMotion { springs[S.sq.rawValue].v += 2.5 }
        busy(0.5)
        liven(4)
        wake()
    }

    /// Finger velocity in points per second while held. The body stretches along
    /// it, the contents lag behind, the feet dangle and the arms flail with speed.
    func drag(velocity: CGVector) {
        dragVelocity = velocity
        if !held { held = true }
        wake()
    }

    /// Finger lifted; the host is flinging or settling the mascot. Call `land` on touchdown.
    func drop() {
        held = false
        if !reduceMotion {
            falling = true
            fallingSince = t
        }
        busy(0.6)
        wake()
    }

    /// Touchdown. `impact` 0…1: how hard (squash depth, topping bounce).
    func land(impact: Double) {
        held = false
        falling = false
        airborne = false; airY = 0; airV = 0
        landImpulse(motionClamp(impact, 0, 1))
        liven(4)
        wake()
    }

    /// One-arm wave, about 1.6 s.
    func wave() {
        guard !reduceMotion else { flashExpression(.happy, for: 0.8); return }
        waveUntil = t + 1.6
        busy(1.6)
        wake()
    }

    /// A little jump with anticipation squash; toppings bounce on landing.
    func hop() {
        guard !reduceMotion else { flashExpression(.happy, for: 0.8); return }
        guard !airborne, !held, crouchUntil < t else { return }
        crouchUntil = t + 0.09
        at(t + 0.09) { [weak self] in self?.launch(speed: 620) }
        busy(0.9)
        wake()
    }

    func react(_ reaction: MascotReaction) {
        switch reaction {
        case .tap:
            // Hop and wave hello; under Reduce Motion only the face brightens.
            flashExpression(.happy, for: 0.9)
            if !reduceMotion, !held {
                hop()
                waveUntil = max(waveUntil, t + 1.2)
            }
            busy(1.2)
            liven(5)
            wake()
        }
    }

    /// Walk in place: 0 stops, 1 is a brisk two steps a second.
    func walk(speed: Double) {
        walkSpeed = reduceMotion ? 0 : motionClamp(speed, 0, 1.5)
        wake()
    }

    /// Visible on screen and the app active. Idle life only runs while true.
    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if !on {
            clock.stop()
            beatTask?.cancel(); beatTask = nil
            breathPhase = 0; lifeUntil = -1; beatUntil = -1
            events.removeAll()
            held = false; falling = false; airborne = false; airY = 0; airV = 0
            crouchUntil = -1; waveUntil = -1; busyUntil = -1; flash = nil
            dragVelocity = .zero; glanceUntil = -1
            composeTargets()
            snapAll()
            render()
        } else {
            scheduleMoodBeat(entering: false)
            liven(6)
            wake()
        }
    }

    /// Advance the simulation without the display link (snapshots, previews, tests).
    func simulate(seconds: Double, fps: Double = 60) {
        let frames = max(1, Int((seconds * fps).rounded()))
        let dt = 1 / fps
        for _ in 0..<frames {
            for _ in 0..<4 { frame(dt / 4) }
            publish()
        }
    }

    func stop() { clock.stop() }

    // MARK: Expressions

    struct Expression {
        var smile = 0.0, ooh = 0.0, wavy = 0.0, grin = 0.0
        var squint = 0.0, wide = 0.0, sleepy = 0.0, brows = 0.0, blush = 0.3

        static let neutral = Expression(smile: 1)
        static let happy = Expression(smile: 1, squint: 1, blush: 0.75)
        static let thinking = Expression(wavy: 1, blush: 0.2)
        static let celebrate = Expression(grin: 1, squint: 1, blush: 0.8)
        static let help = Expression(smile: 1, wide: 1, brows: 1, blush: 0.35)
        static let sleepy = Expression(ooh: 1, sleepy: 1, blush: 0.3)
        static let surprised = Expression(ooh: 1, wide: 1, brows: 0.8, blush: 0.5)
        static let whee = Expression(grin: 1, wide: 0.6, brows: 0.6, blush: 0.6)
        static let landed = Expression(grin: 1, squint: 1, blush: 0.7)
    }

    private func expression() -> Expression {
        if let flash { return flash }
        if falling, !reduceMotion { return .whee }
        if held { return reduceMotion || dragSpeed < 900 ? .surprised : .whee }
        switch mood {
        case .idle: return .neutral
        case .thinking: return .thinking
        case .celebrate: return .celebrate
        case .help: return .help
        case .happy: return .happy
        case .sleepy: return .sleepy
        }
    }

    // MARK: Springs

    private enum S: Int, CaseIterable {
        case sq, stretchX, stretchY, tilt
        case cX, cY, cRot
        case f0, f1, f2, f3, f4, f5
        case r0, r1, r2, r3, r4, r5
        case lookX, lookY
        case smile, ooh, wavy, grin, squint, wide, sleepy, brows, blush
        case armLRaise, armLLift, armLReach, armRRaise, armRLift, armRReach
        case footLLift, footLRot, footRLift, footRRot

        var rest: Double {
            switch self {
            case .sq: return 1
            case .smile: return 1
            case .blush: return 0.3
            default: return 0
            }
        }

        var preset: MotionTokens.Preset {
            switch self {
            case .sq: return .init(k: 420, c: 13)
            case .stretchX, .stretchY: return .init(k: 320, c: 20)
            case .tilt: return .init(k: 260, c: 18)
            case .cX, .cY: return .init(k: 200, c: 9)
            case .cRot: return .init(k: 180, c: 8)
            case .f0, .f1, .f2, .f3, .f4, .f5: return .init(k: 300, c: 9)
            case .r0, .r1, .r2, .r3, .r4, .r5: return .init(k: 240, c: 8)
            case .lookX, .lookY: return .init(k: 260, c: 26)
            // Quick, critically damped: a long cross-fade reads as a grey half-face.
            case .smile, .ooh, .wavy, .grin, .squint, .wide, .sleepy, .brows: return .init(k: 900, c: 60)
            case .blush: return MotionTokens.fade
            case .armLRaise, .armLLift, .armLReach, .armRRaise, .armRLift, .armRReach: return .init(k: 300, c: 19)
            case .footLLift, .footLRot, .footRLift, .footRRot: return .init(k: 380, c: 22)
            }
        }

        /// Settle tolerance in the spring's own units.
        var epsilon: Double {
            switch self {
            case .cX, .cY, .f0, .f1, .f2, .f3, .f4, .f5, .armLLift, .armLReach, .armRLift, .armRReach, .footLLift, .footRLift:
                return MotionSpring.points
            default: return 0.002
            }
        }

        /// Face springs still cross-fade under Reduce Motion; everything else snaps.
        var isExpression: Bool {
            switch self {
            case .smile, .ooh, .wavy, .grin, .squint, .wide, .sleepy, .brows, .blush: return true
            default: return false
            }
        }
    }

    private func x(_ s: S) -> Double { springs[s.rawValue].x }
    private func target(_ s: S, _ v: Double) { springs[s.rawValue].t = v }


    private var dragSpeed: Double {
        (dragVelocity.dx * dragVelocity.dx + dragVelocity.dy * dragVelocity.dy).squareRoot()
    }

    // MARK: Simulation

    private func frame(_ dt: Double) {
        t += dt
        runEvents()
        let motion = !reduceMotion
        let loops = loopsOn

        // Breathe while lively; once life rests, finish the breath (no jump) and stop.
        if loops, lively || breathPhase > 0 {
            breathPhase += dt * 2 * .pi * (mood == .sleepy ? 0.15 : 0.25)
            if breathPhase >= 2 * .pi { breathPhase = lively ? breathPhase - 2 * .pi : 0 }
        }
        if !held { dragVelocity = CGVector(dx: dragVelocity.dx * exp(-dt * 10), dy: dragVelocity.dy * exp(-dt * 10)) }
        else { dragVelocity = CGVector(dx: dragVelocity.dx * exp(-dt * 4), dy: dragVelocity.dy * exp(-dt * 4)) }
        if walkSpeed > 0 { walkPhase += dt * 2 * .pi * walkSpeed }
        if let _ = flash, t >= flashUntil { flash = nil }
        if falling, t - fallingSince > 1.4 { falling = false }

        if airborne {
            airV += 2600 * dt
            airY += airV * dt
            if airY >= 0 {
                let impact = motionClamp(airV / 700, 0, 1)
                airY = 0; airV = 0; airborne = false
                landImpulse(impact)
            }
        }

        if loops { idleLife() }
        composeTargets()

        let sqV0 = springs[S.sq.rawValue].v
        let tiltV0 = springs[S.tilt.rawValue].v
        for i in springs.indices { springs[i].step(dt) }

        if motion {
            // Secondary motion: the contents feel the body's acceleration and lag it.
            let dSq = springs[S.sq.rawValue].v - sqV0
            let dTilt = springs[S.tilt.rawValue].v - tiltV0
            springs[S.cY.rawValue].v += dSq * 55
            springs[S.cRot.rawValue].v -= dTilt * 0.5
            for i in 0..<6 {
                springs[S.f0.rawValue + i].v += dSq * (40 + 8 * Double(i))
                springs[S.r0.rawValue + i].v -= dTilt * (0.6 + 0.12 * Double(i))
            }
        } else {
            snapBodyAndLimbs()
        }
    }

    private func idleLife() {
        // Blinks every 3–6 s (sometimes a double blink).
        if t >= nextBlink {
            blinkStart = t
            nextBlink = t + (Double.random(in: 0...1) < 0.15 ? 0.28 : .random(in: 3...6))
        }
        // Occasional glances when nobody is steering the eyes.
        if explicitLook == nil, mood != .thinking, mood != .sleepy, !held, t >= nextGlance {
            glanceTarget = CGPoint(x: .random(in: -0.8...0.8), y: .random(in: -0.45...0.35))
            glanceUntil = t + .random(in: 0.7...1.3)
            nextGlance = t + .random(in: 4...8)
        }
        // Mood beats: celebrate hops again, help waves again.
        if lively, t >= nextMoodBeat {
            switch mood {
            case .celebrate: hop()
            case .help: wave()
            default: break
            }
            scheduleMoodBeat(entering: false)
        }
    }

    private func scheduleMoodBeat(entering: Bool) {
        switch mood {
        case .celebrate: nextMoodBeat = t + 2.2
        case .help: nextMoodBeat = t + (entering ? 6 : .random(in: 6...9))
        default: nextMoodBeat = .infinity
        }
    }

    /// Compose every spring target from mood, gestures and loops.
    private func composeTargets() {
        let motion = !reduceMotion
        let loops = loopsOn
        let e = expression()
        target(.smile, e.smile); target(.ooh, e.ooh); target(.wavy, e.wavy); target(.grin, e.grin)
        target(.squint, e.squint); target(.wide, e.wide); target(.sleepy, e.sleepy)
        target(.brows, e.brows); target(.blush, e.blush)

        // Eyes
        var look = CGPoint.zero
        if mood == .thinking { look = CGPoint(x: 0.6, y: -0.8) }
        if mood == .sleepy { look = CGPoint(x: 0, y: 0.3) }
        if loops, t < glanceUntil { look = glanceTarget }
        if let explicitLook { look = explicitLook }
        if held, motion, explicitLook == nil {
            look = CGPoint(x: motionClamp(-dragVelocity.dx / 1500, -1, 1), y: motionClamp(-dragVelocity.dy / 1500, -1, 1))
        }
        target(.lookX, look.x); target(.lookY, look.y)

        // Body
        let time = t
        var tilt = 0.0
        var sq = 1.0
        if time < crouchUntil { sq = 0.86 }
        if loops {
            switch mood {
            case .thinking: tilt += sin(time * 2 * .pi * 0.3) * 0.035
            case .sleepy: tilt += sin(time * 2 * .pi * 0.15) * 0.03
            case .help: tilt += -0.03
            default: break
            }
        }
        if walkSpeed > 0 { tilt += sin(walkPhase) * 0.04 }
        var stretch = CGVector.zero
        if held, motion {
            let v = dragVelocity
            let speed = dragSpeed
            let amount = min(0.22, speed / 3000)
            if speed > 1 { stretch = CGVector(dx: v.dx / speed * amount, dy: v.dy / speed * amount) }
            tilt += motionClamp(v.dx * 0.00015, -0.25, 0.25)
            sq = 1.04
        }
        target(.sq, sq); target(.tilt, tilt)
        target(.stretchX, stretch.dx); target(.stretchY, stretch.dy)

        // Contents lag the drag
        if held, motion {
            target(.cX, motionClamp(-dragVelocity.dx * 0.006, -10, 10))
            target(.cY, motionClamp(-dragVelocity.dy * 0.004, -6, 8))
            target(.cRot, motionClamp(-dragVelocity.dx * 0.00008, -0.12, 0.12))
            for i in 0..<6 {
                target(S(rawValue: S.r0.rawValue + i)!, motionClamp(-dragVelocity.dx * (0.0001 + 0.00003 * Double(i)), -0.3, 0.3))
            }
        } else {
            target(.cX, 0); target(.cY, 0); target(.cRot, 0)
            for i in 0..<6 { target(S(rawValue: S.r0.rawValue + i)!, 0) }
        }

        // Arms
        var l = MascotPose.Arm(), r = MascotPose.Arm()
        switch mood {
        case .idle: break
        case .thinking:
            l = .init(raise: 1.9, lift: 75, reach: 80)
            r = .init(raise: -0.2)
            if loops { l.lift -= max(0, sin(time * 2 * .pi * 1.4)) * 8 }
        case .celebrate:
            l = .init(raise: 1.5, lift: -4, reach: -14); r = .init(raise: 1.5, lift: -4, reach: -14)
            if loops {
                let pump = sin(time * 2 * .pi * 1.6) * 0.15
                l.raise += pump; r.raise += pump
            }
        case .help:
            l = .init(raise: -0.1); r = .init(raise: 1.45, lift: -6, reach: -8)
        case .happy:
            l = .init(raise: 0.35); r = .init(raise: 0.35)
        case .sleepy:
            l = .init(raise: -0.3); r = .init(raise: -0.3)
        }
        if motion, time < waveUntil {
            r = .init(raise: 1.5 + sin((waveUntil - time) * 2 * .pi * 2.2) * 0.4, lift: -6, reach: -8)
        }
        if motion, held {
            let amp = min(0.6, dragSpeed / 1500)
            l = .init(raise: 0.9 + sin(time * 16) * amp, reach: -6)
            r = .init(raise: 0.9 + sin(time * 16 + 1.7) * amp, reach: -6)
        } else if motion, falling || airborne {
            l = .init(raise: 1.4, reach: -10); r = .init(raise: 1.4, reach: -10)
        }
        target(.armLRaise, l.raise); target(.armLLift, l.lift); target(.armLReach, l.reach)
        target(.armRRaise, r.raise); target(.armRLift, r.lift); target(.armRReach, r.reach)

        // Feet
        var fl = MascotPose.Foot(), fr = MascotPose.Foot()
        if motion, held {
            let lag = motionClamp(-dragVelocity.dx * 0.0002, -0.35, 0.35)
            fl = .init(lift: -6, rotation: lag + sin(time * 2 * .pi * 1.3) * 0.16)
            fr = .init(lift: -6, rotation: lag + sin(time * 2 * .pi * 1.3 + 1.4) * 0.16)
        } else if motion, falling || airborne {
            fl = .init(lift: -4, rotation: sin(time * 14) * 0.3)
            fr = .init(lift: -4, rotation: -sin(time * 14) * 0.3)
        } else if walkSpeed > 0 {
            fl.lift = max(0, sin(walkPhase)) * 16
            fr.lift = max(0, -sin(walkPhase)) * 16
        } else if loops, mood == .thinking {
            fr.lift = max(0, sin(time * 2 * .pi * 1.4)) * 4
            fr.rotation = -max(0, sin(time * 2 * .pi * 1.4)) * 0.12
        }
        target(.footLLift, fl.lift); target(.footLRot, fl.rotation)
        target(.footRLift, fr.lift); target(.footRRot, fr.rotation)
    }

    private func launch(speed: Double) {
        guard !held else { return }
        airborne = true
        airV = -speed
        airY = 0
        springs[S.sq.rawValue].v += 3
        springs[S.cY.rawValue].v += 140
        for i in 0..<6 { springs[S.f0.rawValue + i].v += 100 + Double(i) * 18 }
    }

    private func landImpulse(_ impact: Double) {
        guard !reduceMotion, impact > 0.01 else { busy(0.3); return }
        springs[S.sq.rawValue].v += -6.5 * impact
        springs[S.cY.rawValue].v += 240 * impact
        springs[S.cRot.rawValue].v += Double.random(in: -1...1) * impact
        for i in 0..<6 {
            springs[S.f0.rawValue + i].v -= (280 + Double((i * 37) % 5) * 45) * impact
            springs[S.r0.rawValue + i].v += (i % 2 == 0 ? 1 : -1) * (2 + Double(i % 3)) * impact
        }
        for s in [S.footLLift, .footLRot, .footRLift, .footRRot] { springs[s.rawValue].snap(0) }
        if impact > 0.3 {
            // The face pops on impact instead of fading.
            flashExpression(.landed, for: 0.6)
            composeTargets()
            for s in S.allCases where s.isExpression && s != .blush { springs[s.rawValue].snap(springs[s.rawValue].t) }
        }
        busy(0.9)
    }

    private func flashExpression(_ e: Expression, for seconds: Double) {
        flash = e
        flashUntil = t + seconds
        wake()
    }

    private func busy(_ seconds: Double) { busyUntil = max(busyUntil, t + seconds) }

    private func at(_ time: Double, _ fn: @escaping () -> Void) {
        events.append((time, fn))
    }

    private func runEvents() {
        guard !events.isEmpty else { return }
        let due = events.filter { $0.at <= t }
        guard !due.isEmpty else { return }
        events.removeAll { $0.at <= t }
        due.forEach { $0.fn() }
    }

    private func snapAll() {
        for i in springs.indices { springs[i].snap(springs[i].t) }
    }

    private func snapBodyAndLimbs() {
        for s in S.allCases where !s.isExpression { springs[s.rawValue].snap(springs[s.rawValue].t) }
    }

    // MARK: Clock

    /// Moods whose loop is the message (working, celebrating) stay lively throughout.
    private var lively: Bool { t < lifeUntil || mood == .thinking || mood == .celebrate }

    private var loopsOn: Bool { active && !reduceMotion && (lively || t < beatUntil || breathPhase > 0) }

    private func liven(_ seconds: Double) { lifeUntil = max(lifeUntil, t + seconds) }

    /// While resting, wake briefly every 3–6 s to blink or glance.
    private func scheduleBeat() {
        beatTask?.cancel()
        guard active, !reduceMotion else { return }
        beatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Double.random(in: 3...6)))
            guard !Task.isCancelled, let self, self.active, !self.reduceMotion, !self.clock.isRunning else { return }
            self.beat()
        }
    }

    private func beat() {
        if Double.random(in: 0...1) < 0.35, explicitLook == nil, mood != .sleepy {
            nextGlance = t
            beatUntil = t + 1.8
        } else {
            nextBlink = t
            beatUntil = t + 0.35
        }
        wake()
    }

    private var gestureBusy: Bool {
        held || falling || airborne || walkSpeed > 0 || !events.isEmpty || t < busyUntil || flash != nil || t < crouchUntil
    }

    private func wake() {
        guard active || gestureBusy || !allSettled else {
            composeTargets(); snapAll(); render(); return
        }
        clock.maxFramesPerSecond = frameRate
        clock.start()
    }

    private var frameRate: Float {
        if held { return 120 }
        if gestureBusy { return 60 }
        return 30
    }

    private var allSettled: Bool {
        S.allCases.allSatisfy { springs[$0.rawValue].isSettled(within: $0.epsilon) }
    }

    private func render() {
        publish()
        guard clock.isRunning else { return }
        if !loopsOn, !gestureBusy, allSettled {
            snapAll()
            publish()
            clock.stop()
            scheduleBeat()
        } else if clock.maxFramesPerSecond != frameRate {
            clock.maxFramesPerSecond = frameRate
        }
    }

    private func publish() {
        var p = MascotPose()
        let loops = loopsOn
        let sq = x(.sq)
        p.scaleY = sq
        p.scaleX = pow(max(sq, 0.3), -0.75)
        p.breathe = loops ? 1 + 0.0075 * (1 - cos(breathPhase)) : 1
        p.tilt = x(.tilt)
        let sx = x(.stretchX), sy = x(.stretchY)
        p.stretch = (sx * sx + sy * sy).squareRoot()
        p.stretchAngle = atan2(sy, sx)
        p.altitude = airY
        p.bob = walkSpeed > 0 ? -abs(sin(walkPhase)) * 5 : 0
        p.shadow = held ? 0.45 : motionClamp(1 + airY / 220, 0.4, 1)

        p.contentX = x(.cX); p.contentY = x(.cY); p.contentTilt = x(.cRot)
        p.fruitY = (0..<6).map { springs[S.f0.rawValue + $0].x }
        p.fruitRotation = (0..<6).map { springs[S.r0.rawValue + $0].x }

        p.lookX = x(.lookX); p.lookY = x(.lookY)
        if blinkStart >= 0, !reduceMotion {
            let u = (t - blinkStart) / 0.12
            if u >= 0, u < 1 { p.blink = 1 - 0.9 * sin(.pi * u) }
        }
        p.smile = x(.smile); p.ooh = x(.ooh); p.wavy = x(.wavy); p.grin = x(.grin)
        p.squint = x(.squint); p.wide = x(.wide); p.sleepy = x(.sleepy)
        p.brows = x(.brows); p.blush = x(.blush)

        p.armL = .init(raise: x(.armLRaise), lift: x(.armLLift), reach: x(.armLReach))
        p.armR = .init(raise: x(.armRRaise), lift: x(.armRLift), reach: x(.armRReach))
        p.footL = .init(lift: x(.footLLift), rotation: x(.footLRot))
        p.footR = .init(lift: x(.footRLift), rotation: x(.footRRot))
        if p != pose { pose = p }
    }
}
