import Foundation
import CoreGraphics

// MARK: - Gaits
//
// Walking, running and stair climbing are cycles, not two positions swung
// back and forth. Each leg goes through its own stride half a cycle apart:
// a stance phase with the foot on the ground travelling back under the body
// (the figure walks on the spot, like on a treadmill), then a swing phase
// where the foot lifts, the knee drives through and the foot reaches forward
// to land. The arms swing against the legs and the body rises and falls with
// each step. A run has shorter ground contact (so both feet are in the air
// between steps), a heel kick and bent elbows; the stair climb is a stepper,
// each foot riding its own step up and down.
//
// Poses are in the same side-view unit square as the drawn ones (y down,
// floor at 0.9, facing +x), so the 3D figure treats them the same way.

enum Gait {
    case walk, run, stairs

    /// Seconds for one full stride (two steps).
    var period: Double {
        switch self {
        case .walk: return 1.15
        case .run: return 0.74
        case .stairs: return 1.5
        }
    }

    private static let floor: CGFloat = 0.9
    private static let thigh: CGFloat = 0.17, shin: CGFloat = 0.18
    private static let upperArm: CGFloat = 0.14, forearm: CGFloat = 0.13

    /// The body at `phase` (0…1, wraps) through the stride.
    func pose(phase: Double) -> FigurePose {
        let phi = phase - Foundation.floor(phase)
        let twoPi = 2 * Double.pi

        // Hips: lowest when the weight lands, highest between steps.
        let hip: CGPoint
        let lean: CGFloat
        switch self {
        case .walk:
            // Nearly straight over the standing leg, a little lower as the weight changes feet.
            hip = CGPoint(x: 0.5, y: 0.558 + 0.011 * cos(2 * twoPi * (phi - 0.05))); lean = 0.016
        case .run:
            hip = CGPoint(x: 0.48, y: 0.558 + 0.012 * cos(2 * twoPi * (phi - 0.18))); lean = 0.05
        case .stairs:
            // Tall enough that the pushing leg nearly straightens at the bottom of each step.
            hip = CGPoint(x: 0.48, y: 0.538 + 0.005 * cos(2 * twoPi * phi)); lean = 0.035
        }

        var p = FigurePose()
        p.hip = hip
        p.shoulder = CGPoint(x: hip.x + lean, y: hip.y - 0.288)
        p.spine = CGPoint(x: hip.x + lean * 0.45, y: hip.y - 0.145)
        p.head = CGPoint(x: p.shoulder.x + lean * 0.35 + 0.008, y: p.shoulder.y - 0.12)

        let near = phi, far = phi + 0.5
        let footF = foot(legPhase: near, hip: hip), footB = foot(legPhase: far, hip: hip)
        p.footF = footF; p.kneeF = Self.knee(hip: hip, foot: footF)
        p.footB = footB; p.kneeB = Self.knee(hip: hip, foot: footB)

        // Which foot carries the weight: all of it in stance, handed over around each landing.
        if let fade = handover {
            p.supportF = support(legPhase: near, fade: fade)
            p.supportB = support(legPhase: far, fade: fade)
        }

        // Each arm swings against the leg on its own side.
        let armF = arm(legPhase: near, shoulder: p.shoulder), armB = arm(legPhase: far, shoulder: p.shoulder)
        p.elbowF = armF.elbow; p.handF = armF.hand
        p.elbowB = armB.elbow; p.handB = armB.hand
        return p
    }

    private static let walkStance = 0.62, runStance = 0.36

    /// How much of the stride it takes to hand the weight from one foot to
    /// the other (longer for a run, which spends it in the air). `nil` for the
    /// stepper, where both feet stay on their steps.
    private var handover: (stance: Double, fade: Double)? {
        switch self {
        case .walk: return (Self.walkStance, 0.07)
        case .run: return (Self.runStance, 0.17)
        case .stairs: return nil
        }
    }

    private func support(legPhase: Double, fade: (stance: Double, fade: Double)) -> CGFloat {
        let psi = legPhase - Foundation.floor(legPhase)
        func smooth(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
        if psi < fade.stance { return 1 }
        // Fading out after toe-off, fading in before the next landing.
        return CGFloat(max(smooth(1 - (psi - fade.stance) / fade.fade), smooth(1 - (1 - psi) / fade.fade)))
    }

    /// Where a foot (ankle) is at its own point in the stride.
    private func foot(legPhase: Double, hip: CGPoint) -> CGPoint {
        let psi = legPhase - Foundation.floor(legPhase)
        func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        switch self {
        case .walk:
            let stance = Self.walkStance, reach: CGFloat = 0.12
            if psi < stance {
                // On the ground, carried back under the body at a steady pace.
                return CGPoint(x: hip.x + reach - 2 * reach * CGFloat(psi / stance), y: Self.floor)
            }
            let t = (psi - stance) / (1 - stance)
            // Lifts off the toe, swings through low, reaches forward to land on the heel.
            let lift = 0.042 * sin(.pi * pow(t, 0.8))
            return CGPoint(x: hip.x - reach + 2 * reach * CGFloat(smooth(t)), y: Self.floor - CGFloat(lift))
        case .run:
            let stance = Self.runStance, front: CGFloat = 0.06, back: CGFloat = 0.12
            if psi < stance {
                return CGPoint(x: hip.x + front - (front + back) * CGFloat(psi / stance), y: Self.floor)
            }
            let t = (psi - stance) / (1 - stance)
            // Heel kicks up behind, then the knee drives forward and the foot comes down to land.
            let lift = 0.19 * sin(.pi * pow(t, 0.75))
            let carry = smooth(min(max((t - 0.12) / 0.88, 0), 1))
            return CGPoint(x: hip.x - back - 0.03 * CGFloat(sin(.pi * min(t / 0.3, 1))) * (t < 0.3 ? 1 : 0)
                              + (front + back) * CGFloat(carry),
                           y: Self.floor - CGFloat(lift))
        case .stairs:
            // On a stepper each foot rides its own step: up as the knee lifts, down as the leg pushes.
            let up = 0.5 - 0.5 * cos(2 * .pi * psi)
            return CGPoint(x: hip.x + 0.05 + 0.02 * CGFloat(sin(2 * .pi * psi)),
                           y: Self.floor - 0.012 - 0.1 * CGFloat(up))
        }
    }

    /// The knee for a hip and foot: two bones bending forward.
    private static func knee(hip: CGPoint, foot: CGPoint) -> CGPoint {
        let dx = foot.x - hip.x, dy = foot.y - hip.y
        let distance = min(max(hypot(dx, dy), 0.02), thigh + shin - 0.001)
        let ux = dx / max(hypot(dx, dy), 0.0001), uy = dy / max(hypot(dx, dy), 0.0001)
        let cosine = (thigh * thigh + distance * distance - shin * shin) / (2 * thigh * distance)
        let angle = acos(min(max(cosine, -1), 1))
        // Of the two ways to bend, a knee points forward (+x).
        let a = CGPoint(x: hip.x + (ux * cos(angle) - uy * sin(angle)) * thigh, y: hip.y + (ux * sin(angle) + uy * cos(angle)) * thigh)
        let b = CGPoint(x: hip.x + (ux * cos(-angle) - uy * sin(-angle)) * thigh, y: hip.y + (ux * sin(-angle) + uy * cos(-angle)) * thigh)
        return a.x >= b.x ? a : b
    }

    /// The arm on the same side as a leg at `legPhase`: forward when that leg is back.
    private func arm(legPhase: Double, shoulder: CGPoint) -> (elbow: CGPoint, hand: CGPoint) {
        let psi = legPhase - Foundation.floor(legPhase)
        let legForward: Double, swing: Double, bend: Double
        switch self {
        case .walk: legForward = cos(2 * .pi * (psi + 0.06)); swing = 0.38; bend = 0.32
        case .run: legForward = cos(2 * .pi * (psi + 0.12)); swing = 0.72; bend = 1.45
        case .stairs: legForward = -cos(2 * .pi * psi); swing = 0.34; bend = 0.85
        }
        // Angle from straight down, positive toward the front.
        let theta = -swing * legForward
        // The elbow bends a little more as the hand comes forward.
        let flex = bend + 0.18 * max(theta / swing, 0)
        let elbow = CGPoint(x: shoulder.x + Self.upperArm * CGFloat(sin(theta)), y: shoulder.y + Self.upperArm * CGFloat(cos(theta)))
        let hand = CGPoint(x: elbow.x + Self.forearm * CGFloat(sin(theta + flex)), y: elbow.y + Self.forearm * CGFloat(cos(theta + flex)))
        return (elbow, hand)
    }
}

extension ExerciseMotion {
    /// The stride cycle that drives this movement, when it is one.
    var gait: Gait? {
        switch self {
        case .walk: return .walk
        case .run: return .run
        case .stairs: return .stairs
        default: return nil
        }
    }
}
