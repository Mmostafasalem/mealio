import Foundation
import CoreGraphics

// MARK: - Rep tempo
//
// How a rep moves through time. The two drawn positions say *where* the body
// goes; this says *how*: the lowering half is slower than the lift, the part
// doing the work leads and the rest of the body follows a beat behind, the far
// arm trails the near one, a move settles with a small overshoot instead of
// stopping dead, and the chest keeps breathing through the holds.
//
// Kept apart from the posing so a captured clip can replace it per exercise:
// anything that can answer "where is each part at time t" can drive the figure.

/// How far through the movement each part of the body is (0 at the start
/// position, 1 at the finish; a settle can pass 1 by a hair).
struct RepState: Equatable {
    var legs: CGFloat = 0
    var spine: CGFloat = 0
    var armNear: CGFloat = 0
    var armFar: CGFloat = 0
    var head: CGFloat = 0
    /// Breathing, -1…1.
    var breath: CGFloat = 0

    /// Every part at the same point (still frames, the old lockstep motion).
    static func all(_ t: CGFloat) -> RepState {
        RepState(legs: t, spine: t, armNear: t, armFar: t, head: t)
    }
}

enum RepTempo {
    /// Seconds for one rep.
    static func period(for motion: ExerciseMotion) -> Double {
        motion.isContinuous ? motion.period : max(motion.period * 1.45, 3.6)   // gaits carry their own stride time
    }

    /// Fractions of a rep: hold at the start, move out, hold at the finish, move back, rest.
    private static func segments(loweringFirst: Bool) -> (hold0: Double, out: Double, hold1: Double, back: Double) {
        // The lowering (eccentric) half takes about half as long again as the lift.
        loweringFirst ? (0.05, 0.37, 0.10, 0.27) : (0.05, 0.27, 0.13, 0.37)
    }

    static func state(for motion: ExerciseMotion, elapsed: Double) -> RepState {
        let period = period(for: motion)
        let u = (elapsed / period).truncatingRemainder(dividingBy: 1)
        let breath = CGFloat(sin(2 * .pi * elapsed / 3.8))

        if motion.isContinuous {
            // Running, cycling, skipping: one smooth loop, the arms a touch behind the legs.
            func loop(_ shift: Double) -> CGFloat { CGFloat(0.5 - 0.5 * cos(2 * .pi * (u - shift))) }
            return RepState(legs: loop(0), spine: loop(0.03), armNear: loop(0.05), armFar: loop(0.05),
                            head: loop(0.06), breath: breath)
        }

        let loweringFirst = motion.startsWithLowering
        let s = segments(loweringFirst: loweringFirst)
        let lag = lags(for: motion)

        // Raw travel 0…1 within the moving segment, the direction, and seconds since arriving.
        let x: Double, outward: Bool, sinceArrival: Double
        switch u {
        case ..<s.hold0:
            x = 0; outward = true; sinceArrival = 10
        case ..<(s.hold0 + s.out):
            x = (u - s.hold0) / s.out; outward = true; sinceArrival = 0
        case ..<(s.hold0 + s.out + s.hold1):
            x = 1; outward = true; sinceArrival = (u - s.hold0 - s.out) * period
        case ..<(s.hold0 + s.out + s.hold1 + s.back):
            x = (u - s.hold0 - s.out - s.hold1) / s.back; outward = false; sinceArrival = 0
        default:
            x = 1; outward = false; sinceArrival = (u - s.hold0 - s.out - s.hold1 - s.back) * period
        }
        let lowering = outward == loweringFirst

        func part(_ delay: Double, settle: Double) -> CGFloat {
            // Each part covers the same ground in a shorter window that starts later.
            let window = 1 - lag.longest
            let local = min(max((x - delay) / window, 0), 1)
            var v = lowering ? easeLowering(local) : easeLift(local)
            // Arriving: a small damped overshoot, then still.
            if x >= 1, sinceArrival < 1.2 {
                v += settle * exp(-5.5 * sinceArrival) * sin(13 * sinceArrival)
            }
            return CGFloat(outward ? v : 1 - v)
        }
        return RepState(legs: part(lag.legs, settle: 0.012),
                        spine: part(lag.spine, settle: 0.02),
                        armNear: part(lag.arms, settle: 0.025),
                        armFar: part(lag.arms + 0.035, settle: 0.025),
                        head: part(lag.head, settle: 0.015),
                        breath: breath)
    }

    /// The lift: quick off the mark, easing into the top.
    private static func easeLift(_ x: Double) -> Double {
        let smooth = x * x * x * (x * (6 * x - 15) + 10)       // smootherstep
        let eager = 1 - pow(1 - x, 2.2)
        return 0.7 * smooth + 0.3 * eager
    }

    /// The lowering: controlled and even, no drop.
    private static func easeLowering(_ x: Double) -> Double {
        0.5 - 0.5 * cos(.pi * x)
    }

    /// How late each part starts, as a fraction of the move. The part doing
    /// the work starts first; the rest follows.
    private static func lags(for motion: ExerciseMotion) -> (legs: Double, spine: Double, arms: Double, head: Double, longest: Double) {
        if motion.legsLead {
            return (0, 0.05, 0.10, 0.12, 0.135)
        }
        return (0.04, 0.07, 0, 0.11, 0.11)
    }
}

extension ExerciseMotion {
    /// True when the drawn start is the top of the rep and the first half is
    /// the controlled lowering (a squat, a push-up); false when the first half
    /// is the lift (a press, a row).
    var startsWithLowering: Bool {
        switch self {
        case .squat, .backSquat, .gobletSquat, .lunge, .lungeReach, .hinge, .pushUp, .pikePushUp,
             .benchPress, .dumbbellBench, .dip, .legPress, .fold, .burpee, .childsPose:
            return true
        default:
            return false
        }
    }

    /// The legs and hips start the move (squats, hinges, steps); otherwise the arms do.
    var legsLead: Bool {
        switch self {
        case .squat, .backSquat, .gobletSquat, .lunge, .lungeReach, .hinge, .legPress, .stepUp, .bridge,
             .burpee, .jump, .fold, .kneeRaise, .deadBug, .superman:
            return true
        default:
            return false
        }
    }
}
