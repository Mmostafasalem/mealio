import SwiftUI

// MARK: - Animated exercise figure
//
// How a movement goes, drawn in code: `ExerciseMotion` names each movement
// and gives its start and end position as a side-view stick figure (facing
// right). `FigureScene` turns those, a generated stride or a captured clip into
// a posed 3D body, and `LineFigureCanvas` draws it as a line drawing with the
// worked muscles in red. No image assets.
//
// Coordinates are a unit square, y down, with the floor at y = 0.9.

struct FigurePose: Equatable {
    var head = CGPoint(x: 0.5, y: 0.14)
    var shoulder = CGPoint(x: 0.5, y: 0.26)
    /// Mid-spine; `nil` draws a straight back.
    var spine: CGPoint? = nil
    var hip = CGPoint(x: 0.5, y: 0.55)
    // "Front" is the limb nearest the viewer, "back" the far one.
    var elbowF = CGPoint(x: 0.51, y: 0.4)
    var handF = CGPoint(x: 0.53, y: 0.53)
    var elbowB = CGPoint(x: 0.49, y: 0.4)
    var handB = CGPoint(x: 0.5, y: 0.53)
    var kneeF = CGPoint(x: 0.51, y: 0.72)
    var footF = CGPoint(x: 0.53, y: 0.9)
    var kneeB = CGPoint(x: 0.49, y: 0.72)
    var footB = CGPoint(x: 0.47, y: 0.9)
    /// How much of the body's weight each foot carries (0…1), when the pose
    /// knows (a stride cycle does). `nil` lets the figure work it out from
    /// which foot is lowest.
    var supportF: CGFloat? = nil
    var supportB: CGFloat? = nil

    /// Same position for both arms.
    func arms(elbow: CGPoint, hand: CGPoint) -> FigurePose {
        var p = self
        p.elbowF = elbow; p.handF = hand
        p.elbowB = CGPoint(x: elbow.x - 0.02, y: elbow.y); p.handB = CGPoint(x: hand.x - 0.02, y: hand.y)
        return p
    }

    /// Same position for both legs.
    func legs(knee: CGPoint, foot: CGPoint) -> FigurePose {
        var p = self
        p.kneeF = knee; p.footF = foot
        p.kneeB = CGPoint(x: knee.x - 0.02, y: knee.y); p.footB = CGPoint(x: foot.x - 0.03, y: foot.y)
        return p
    }

    /// The other side leading: swaps the near and far limbs.
    var mirroredLimbs: FigurePose {
        var p = self
        (p.elbowF, p.elbowB) = (elbowB, elbowF)
        (p.handF, p.handB) = (handB, handF)
        (p.kneeF, p.kneeB) = (kneeB, kneeF)
        (p.footF, p.footB) = (footB, footF)
        return p
    }

    func lerp(to other: FigurePose, _ t: CGFloat) -> FigurePose {
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        let midA = spine ?? CGPoint(x: (shoulder.x + hip.x) / 2, y: (shoulder.y + hip.y) / 2)
        let midB = other.spine ?? CGPoint(x: (other.shoulder.x + other.hip.x) / 2, y: (other.shoulder.y + other.hip.y) / 2)
        return FigurePose(head: mix(head, other.head), shoulder: mix(shoulder, other.shoulder),
                          spine: mix(midA, midB), hip: mix(hip, other.hip),
                          elbowF: mix(elbowF, other.elbowF), handF: mix(handF, other.handF),
                          elbowB: mix(elbowB, other.elbowB), handB: mix(handB, other.handB),
                          kneeF: mix(kneeF, other.kneeF), footF: mix(footF, other.footF),
                          kneeB: mix(kneeB, other.kneeB), footB: mix(footB, other.footB))
    }
}

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

enum ExerciseMotion: String, CaseIterable {
    case squat, lunge, hinge, pushUp, pikePushUp, plank, press, benchPress, seatedRow, pulldown, bentRow
    case bridge, run, walk, cycle, jump, burpee, climber, kneeRaise, fold, catCow, armCircle, dip, stepUp
    case superman, deadBug, rowing, twist, lungeReach, childsPose, legPress
    case backSquat, gobletSquat, dumbbellBench, jumpRope, woodchop, barbellRow
    case stairs
    // Movements that exist only as captured clips (see `ExerciseClips`).
    case lateralRaise, reverseFly, singleLegDeadlift, sideLunge, jumpingJack, crunch
    case highKnees, march, frontKick, skip, windmill, kneeLift, armRaise, squatReach
    case hipCircle, boxing, sideShuffle, jumpSquat
    // Gym candidates: a captured movement with a weight in the hands…
    case farmerCarry, dumbbellSquat, barbellLunge, gobletSideLunge, dumbbellSingleLegDeadlift
    case dumbbellPunch, raiseOverhead, dumbbellSquatReach
    // …and single-joint lifts drawn as two positions.
    case barbellCurl, dumbbellCurl, frontRaise, uprightRow, shrug, deadlift
    case tricepsOverhead, kickback, dumbbellPress

    enum Prop { case none, barbell, dumbbells, oneDumbbell, goblet, bench, benchDumbbells, highBar, pulldown, step, wheels, seat, cableSeat, rope, cableHandle, pedals }

    var prop: Prop {
        switch self {
        case .benchPress:            return .bench
        case .dumbbellBench:         return .benchDumbbells
        case .press, .hinge, .backSquat, .barbellRow: return .barbell
        case .jumpRope:              return .rope
        case .woodchop:              return .cableHandle
        case .lunge, .lateralRaise, .reverseFly, .farmerCarry, .dumbbellSquat, .dumbbellSingleLegDeadlift,
             .dumbbellPunch, .raiseOverhead, .dumbbellSquatReach, .dumbbellCurl, .frontRaise, .shrug,
             .tricepsOverhead, .kickback, .dumbbellPress: return .dumbbells
        case .barbellLunge, .barbellCurl, .uprightRow, .deadlift: return .barbell
        case .gobletSideLunge:       return .goblet
        case .bentRow:               return .oneDumbbell
        case .gobletSquat:           return .goblet
        case .pulldown:              return .pulldown
        case .kneeRaise:             return .highBar
        case .stepUp, .dip:          return .step
        case .stairs:                return .pedals
        case .cycle:                 return .wheels
        case .legPress:              return .seat
        case .seatedRow, .rowing:    return .cableSeat
        default:                     return .none
        }
    }

    /// Seconds for one full rep (there and back).
    var period: Double {
        if let gait { return gait.period }
        switch self {
        case .run, .climber:          return 0.7
        case .walk, .cycle, .jump, .jumpRope: return 1.0
        case .plank, .fold, .childsPose, .lungeReach: return 3.2
        default:                      return 2.2
        }
    }

    /// Start and end positions; the figure eases between them and back.
    var poses: (FigurePose, FigurePose) {
        let stand = FigurePose()
        switch self {
        case .squat:
            let down = FigurePose(head: pt(0.55, 0.33), shoulder: pt(0.5, 0.44), hip: pt(0.4, 0.68))
                .legs(knee: pt(0.6, 0.72), foot: pt(0.5, 0.9))
                .arms(elbow: pt(0.61, 0.47), hand: pt(0.72, 0.44))
            return (stand.arms(elbow: pt(0.56, 0.36), hand: pt(0.62, 0.3)), down)
        case .backSquat:
            // The bar rides on the upper back; the hands hold it just outside the shoulders.
            let down = FigurePose(head: pt(0.55, 0.33), shoulder: pt(0.5, 0.44), hip: pt(0.4, 0.68))
                .legs(knee: pt(0.6, 0.72), foot: pt(0.5, 0.9))
                .arms(elbow: pt(0.395, 0.537), hand: pt(0.4435, 0.433))
            return (stand.arms(elbow: pt(0.44, 0.39), hand: pt(0.445, 0.275)), down)
        case .gobletSquat:
            // One weight held at the chest with both hands.
            let down = FigurePose(head: pt(0.55, 0.33), shoulder: pt(0.5, 0.44), hip: pt(0.4, 0.68))
                .legs(knee: pt(0.6, 0.72), foot: pt(0.5, 0.9))
                .arms(elbow: pt(0.59, 0.59), hand: pt(0.655, 0.48))
            return (stand.arms(elbow: pt(0.56, 0.41), hand: pt(0.625, 0.3)), down)
        case .lunge:
            var down = FigurePose(head: pt(0.5, 0.25), shoulder: pt(0.5, 0.37), hip: pt(0.5, 0.66))
            down.kneeF = pt(0.65, 0.72); down.footF = pt(0.66, 0.9)
            down.kneeB = pt(0.42, 0.86); down.footB = pt(0.27, 0.87)
            return (stand, down.arms(elbow: pt(0.5, 0.52), hand: pt(0.52, 0.66)))
        case .hinge:
            let down = FigurePose(head: pt(0.76, 0.44), shoulder: pt(0.65, 0.48), hip: pt(0.41, 0.55))
                .legs(knee: pt(0.47, 0.72), foot: pt(0.5, 0.9))
                .arms(elbow: pt(0.65, 0.6), hand: pt(0.64, 0.74))
            return (stand.arms(elbow: pt(0.535, 0.41), hand: pt(0.575, 0.555)), down)
        case .pushUp:
            let top = FigurePose(head: pt(0.79, 0.57), shoulder: pt(0.68, 0.62), hip: pt(0.45, 0.7))
                .legs(knee: pt(0.3, 0.8), foot: pt(0.15, 0.9))
                .arms(elbow: pt(0.69, 0.76), hand: pt(0.7, 0.9))
            let bottom = FigurePose(head: pt(0.79, 0.77), shoulder: pt(0.68, 0.81), hip: pt(0.45, 0.83))
                .legs(knee: pt(0.3, 0.86), foot: pt(0.15, 0.9))
                .arms(elbow: pt(0.58, 0.75), hand: pt(0.7, 0.9))
            return (top, bottom)
        case .pikePushUp:
            let top = FigurePose(head: pt(0.68, 0.62), shoulder: pt(0.62, 0.52), hip: pt(0.42, 0.3))
                .legs(knee: pt(0.32, 0.6), foot: pt(0.22, 0.9))
                .arms(elbow: pt(0.67, 0.7), hand: pt(0.72, 0.9))
            let bottom = FigurePose(head: pt(0.72, 0.82), shoulder: pt(0.64, 0.7), hip: pt(0.42, 0.36))
                .legs(knee: pt(0.32, 0.63), foot: pt(0.22, 0.9))
                .arms(elbow: pt(0.58, 0.8), hand: pt(0.72, 0.9))
            return (top, bottom)
        case .plank:
            let hold = FigurePose(head: pt(0.79, 0.66), shoulder: pt(0.68, 0.7), hip: pt(0.45, 0.75))
                .legs(knee: pt(0.3, 0.82), foot: pt(0.15, 0.9))
                .arms(elbow: pt(0.68, 0.9), hand: pt(0.82, 0.9))
            var breathe = hold
            breathe.hip = pt(0.45, 0.73)
            return (hold, breathe)
        case .press:
            return (stand.arms(elbow: pt(0.57, 0.4), hand: pt(0.57, 0.25)),
                    stand.arms(elbow: pt(0.54, 0.13), hand: pt(0.53, 0.02)))
        case .benchPress, .dumbbellBench:
            let lying = FigurePose(head: pt(0.24, 0.6), shoulder: pt(0.35, 0.62), hip: pt(0.6, 0.62))
                .legs(knee: pt(0.76, 0.62), foot: pt(0.8, 0.9))
            return (lying.arms(elbow: pt(0.4, 0.68), hand: pt(0.38, 0.49)),
                    lying.arms(elbow: pt(0.37, 0.47), hand: pt(0.37, 0.33)))
        case .seatedRow:
            let seated = FigurePose(head: pt(0.43, 0.32), shoulder: pt(0.42, 0.44), hip: pt(0.4, 0.72))
                .legs(knee: pt(0.6, 0.64), foot: pt(0.74, 0.78))
            var back = seated
            back.head = pt(0.39, 0.32); back.shoulder = pt(0.38, 0.44)
            return (seated.arms(elbow: pt(0.58, 0.45), hand: pt(0.72, 0.435)),
                    back.arms(elbow: pt(0.3, 0.53), hand: pt(0.52, 0.445)))
        case .pulldown:
            let seated = FigurePose(head: pt(0.44, 0.36), shoulder: pt(0.45, 0.48), hip: pt(0.46, 0.74))
                .legs(knee: pt(0.66, 0.73), foot: pt(0.67, 0.92))
            return (seated.arms(elbow: pt(0.5, 0.31), hand: pt(0.54, 0.14)),
                    seated.arms(elbow: pt(0.5, 0.64), hand: pt(0.57, 0.47)))
        case .barbellRow:
            let bent = FigurePose(head: pt(0.76, 0.44), shoulder: pt(0.65, 0.48), hip: pt(0.41, 0.55))
                .legs(knee: pt(0.47, 0.72), foot: pt(0.5, 0.9))
            return (bent.arms(elbow: pt(0.65, 0.6), hand: pt(0.64, 0.74)),
                    bent.arms(elbow: pt(0.55, 0.42), hand: pt(0.62, 0.54)))
        case .bentRow:
            let bent = FigurePose(head: pt(0.76, 0.44), shoulder: pt(0.65, 0.48), hip: pt(0.41, 0.55))
                .legs(knee: pt(0.47, 0.72), foot: pt(0.5, 0.9))
            // One arm rows; the other braces on the knee.
            var start = bent.arms(elbow: pt(0.65, 0.6), hand: pt(0.64, 0.74))
            var finish = bent.arms(elbow: pt(0.55, 0.42), hand: pt(0.62, 0.54))
            for brace in [\FigurePose.elbowB] { start[keyPath: brace] = pt(0.6, 0.62); finish[keyPath: brace] = pt(0.6, 0.62) }
            start.handB = pt(0.5, 0.7); finish.handB = pt(0.5, 0.7)
            return (start, finish)
        case .bridge:
            let lying = FigurePose(head: pt(0.19, 0.85), shoulder: pt(0.3, 0.86), hip: pt(0.5, 0.86))
                .legs(knee: pt(0.66, 0.66), foot: pt(0.76, 0.9))
                .arms(elbow: pt(0.4, 0.88), hand: pt(0.5, 0.89))
            var up = lying
            up.hip = pt(0.5, 0.67)
            return (lying, up)
        case .run:
            // A stride cycle (see `Gait`); these two moments are its stills.
            return (Gait.run.pose(phase: 0.05), Gait.run.pose(phase: 0.55))
        case .walk:
            return (Gait.walk.pose(phase: 0.0), Gait.walk.pose(phase: 0.5))
        case .stairs:
            return (Gait.stairs.pose(phase: 0.25), Gait.stairs.pose(phase: 0.75))
        case .lateralRaise, .reverseFly, .armRaise, .jumpingJack, .boxing:
            // Captured movements: these two positions only stand in if the clips are missing.
            return (stand, stand.arms(elbow: pt(0.56, 0.3), hand: pt(0.62, 0.3)))
        case .barbellCurl, .dumbbellCurl:
            // The elbow stays by the ribs; only the forearm moves.
            return (stand.arms(elbow: pt(0.51, 0.4), hand: pt(0.55, 0.53)),
                    stand.arms(elbow: pt(0.52, 0.4), hand: pt(0.6, 0.29)))
        case .frontRaise:
            return (stand.arms(elbow: pt(0.51, 0.4), hand: pt(0.54, 0.53)),
                    stand.arms(elbow: pt(0.635, 0.275), hand: pt(0.765, 0.265)))
        case .uprightRow:
            return (stand.arms(elbow: pt(0.51, 0.4), hand: pt(0.54, 0.53)),
                    stand.arms(elbow: pt(0.5, 0.235), hand: pt(0.555, 0.33)))
        case .shrug:
            var up = FigurePose(head: pt(0.5, 0.118), shoulder: pt(0.5, 0.232))
            up = up.arms(elbow: pt(0.51, 0.372), hand: pt(0.53, 0.502))
            return (stand.arms(elbow: pt(0.51, 0.4), hand: pt(0.53, 0.53)), up)
        case .deadlift:
            let down = FigurePose(head: pt(0.66, 0.36), shoulder: pt(0.58, 0.44), hip: pt(0.4, 0.6))
                .legs(knee: pt(0.54, 0.74), foot: pt(0.52, 0.9))
                .arms(elbow: pt(0.62, 0.58), hand: pt(0.635, 0.71))
            // At lockout the bar sits just in front of the thighs.
            return (down, stand.arms(elbow: pt(0.52, 0.4), hand: pt(0.56, 0.53)))
        case .tricepsOverhead:
            return (stand.arms(elbow: pt(0.52, 0.13), hand: pt(0.45, 0.21)),
                    stand.arms(elbow: pt(0.52, 0.125), hand: pt(0.525, 0.0)))
        case .kickback:
            let bent = FigurePose(head: pt(0.7, 0.33), shoulder: pt(0.62, 0.4), hip: pt(0.42, 0.56))
                .legs(knee: pt(0.52, 0.73), foot: pt(0.48, 0.9))
            return (bent.arms(elbow: pt(0.5, 0.42), hand: pt(0.535, 0.545)),
                    bent.arms(elbow: pt(0.5, 0.42), hand: pt(0.375, 0.43)))
        case .dumbbellPress:
            return (stand.arms(elbow: pt(0.555, 0.385), hand: pt(0.565, 0.255)),
                    stand.arms(elbow: pt(0.535, 0.135), hand: pt(0.525, 0.005)))
        case .singleLegDeadlift, .sideLunge, .crunch, .highKnees, .march, .frontKick, .skip, .windmill,
             .kneeLift, .squatReach, .hipCircle, .sideShuffle, .jumpSquat,
             .farmerCarry, .dumbbellSquat, .dumbbellSingleLegDeadlift,
             .dumbbellPunch, .raiseOverhead, .dumbbellSquatReach:
            var up = stand
            up.kneeF = pt(0.6, 0.62); up.footF = pt(0.58, 0.78)
            return (stand, up)
        case .barbellLunge:
            // Captured; these stand in without the clip. The bar stays on the upper back
            // (hands just outside the shoulders, as in the back squat) while the legs lunge.
            let rack = stand.arms(elbow: pt(0.44, 0.39), hand: pt(0.445, 0.275))
            var down = FigurePose(head: pt(0.5, 0.25), shoulder: pt(0.5, 0.37), hip: pt(0.5, 0.66))
                .arms(elbow: pt(0.44, 0.5), hand: pt(0.445, 0.385))
            down.kneeF = pt(0.65, 0.72); down.footF = pt(0.66, 0.9)
            down.kneeB = pt(0.42, 0.86); down.footB = pt(0.27, 0.87)
            return (rack, down)
        case .gobletSideLunge:
            // Captured; without the clip it is drawn like the goblet squat, the weight at the chest.
            return ExerciseMotion.gobletSquat.poses
        case .cycle:
            var a = FigurePose(head: pt(0.66, 0.24), shoulder: pt(0.58, 0.34), hip: pt(0.4, 0.5))
                .arms(elbow: pt(0.68, 0.42), hand: pt(0.76, 0.46))
            a.kneeF = pt(0.6, 0.55); a.footF = pt(0.57, 0.74)
            a.kneeB = pt(0.5, 0.66); a.footB = pt(0.5, 0.86)
            return (a, a.mirroredLimbs)
        case .jump, .jumpRope:
            let low = FigurePose(head: pt(0.5, 0.2), shoulder: pt(0.5, 0.32), hip: pt(0.48, 0.6))
                .legs(knee: pt(0.54, 0.75), foot: pt(0.5, 0.9))
                .arms(elbow: pt(0.56, 0.44), hand: pt(0.62, 0.54))
            let high = FigurePose(head: pt(0.5, 0.06), shoulder: pt(0.5, 0.18), hip: pt(0.5, 0.47))
                .legs(knee: pt(0.51, 0.64), foot: pt(0.51, 0.8))
                .arms(elbow: pt(0.56, 0.3), hand: pt(0.62, 0.4))
            return (low, high)
        case .burpee:
            let plank = FigurePose(head: pt(0.79, 0.57), shoulder: pt(0.68, 0.62), hip: pt(0.45, 0.7))
                .legs(knee: pt(0.3, 0.8), foot: pt(0.15, 0.9))
                .arms(elbow: pt(0.69, 0.76), hand: pt(0.7, 0.9))
            let high = FigurePose(head: pt(0.5, 0.06), shoulder: pt(0.5, 0.18), hip: pt(0.5, 0.47))
                .legs(knee: pt(0.51, 0.64), foot: pt(0.51, 0.8))
                .arms(elbow: pt(0.54, 0.08), hand: pt(0.56, -0.02))
            return (plank, high)
        case .climber:
            var a = FigurePose(head: pt(0.79, 0.57), shoulder: pt(0.68, 0.62), hip: pt(0.45, 0.68))
                .arms(elbow: pt(0.69, 0.76), hand: pt(0.7, 0.9))
            a.kneeF = pt(0.57, 0.76); a.footF = pt(0.47, 0.84)
            a.kneeB = pt(0.3, 0.8); a.footB = pt(0.15, 0.9)
            return (a, a.mirroredLimbs)
        case .kneeRaise:
            let hang = FigurePose(head: pt(0.5, 0.2), shoulder: pt(0.5, 0.28), hip: pt(0.5, 0.56))
                .arms(elbow: pt(0.52, 0.17), hand: pt(0.52, 0.06))
            return (hang.legs(knee: pt(0.51, 0.72), foot: pt(0.5, 0.86)),
                    hang.legs(knee: pt(0.67, 0.52), foot: pt(0.64, 0.7)))
        case .fold:
            let folded = FigurePose(head: pt(0.68, 0.7), shoulder: pt(0.63, 0.6), hip: pt(0.43, 0.52))
                .legs(knee: pt(0.47, 0.71), foot: pt(0.5, 0.9))
                .arms(elbow: pt(0.63, 0.73), hand: pt(0.6, 0.86))
            return (stand, folded)
        case .catCow:
            let base = FigurePose(head: pt(0.81, 0.52), shoulder: pt(0.7, 0.62), spine: pt(0.52, 0.69), hip: pt(0.35, 0.62))
                .legs(knee: pt(0.35, 0.9), foot: pt(0.15, 0.9))
                .arms(elbow: pt(0.7, 0.76), hand: pt(0.7, 0.9))
            var cat = base
            cat.spine = pt(0.52, 0.5); cat.head = pt(0.8, 0.72)
            return (base, cat)
        case .armCircle:
            return (stand.arms(elbow: pt(0.6, 0.16), hand: pt(0.68, 0.04)),
                    stand.arms(elbow: pt(0.38, 0.36), hand: pt(0.28, 0.46)))
        case .dip:
            let top = FigurePose(head: pt(0.43, 0.24), shoulder: pt(0.43, 0.36), hip: pt(0.48, 0.62))
                .legs(knee: pt(0.66, 0.64), foot: pt(0.74, 0.9))
                .arms(elbow: pt(0.38, 0.49), hand: pt(0.4, 0.62))
            let bottom = FigurePose(head: pt(0.45, 0.38), shoulder: pt(0.45, 0.5), hip: pt(0.5, 0.76))
                .legs(knee: pt(0.67, 0.7), foot: pt(0.74, 0.9))
                .arms(elbow: pt(0.3, 0.54), hand: pt(0.4, 0.62))
            return (top, bottom)
        case .stepUp:
            var low = FigurePose(head: pt(0.48, 0.16), shoulder: pt(0.47, 0.28), hip: pt(0.45, 0.57))
            low.kneeF = pt(0.6, 0.62); low.footF = pt(0.62, 0.78)
            low.kneeB = pt(0.43, 0.74); low.footB = pt(0.4, 0.9)
            var high = FigurePose(head: pt(0.6, 0.04), shoulder: pt(0.6, 0.16), hip: pt(0.6, 0.44))
                .arms(elbow: pt(0.61, 0.3), hand: pt(0.63, 0.42))
            high.kneeF = pt(0.61, 0.61); high.footF = pt(0.62, 0.78)
            high.kneeB = pt(0.58, 0.61); high.footB = pt(0.57, 0.78)
            return (low, high)
        case .superman:
            let flat = FigurePose(head: pt(0.79, 0.82), shoulder: pt(0.68, 0.85), hip: pt(0.45, 0.86))
                .legs(knee: pt(0.3, 0.87), foot: pt(0.15, 0.88))
                .arms(elbow: pt(0.8, 0.87), hand: pt(0.92, 0.87))
            let lifted = FigurePose(head: pt(0.79, 0.73), shoulder: pt(0.68, 0.8), hip: pt(0.45, 0.86))
                .legs(knee: pt(0.3, 0.83), foot: pt(0.15, 0.76))
                .arms(elbow: pt(0.8, 0.76), hand: pt(0.92, 0.71))
            return (flat, lifted)
        case .deadBug:
            var a = FigurePose(head: pt(0.19, 0.84), shoulder: pt(0.3, 0.86), hip: pt(0.55, 0.86))
            a.kneeF = pt(0.6, 0.66); a.footF = pt(0.74, 0.66)
            a.kneeB = pt(0.6, 0.66); a.footB = pt(0.74, 0.66)
            a.elbowF = pt(0.3, 0.73); a.handF = pt(0.31, 0.6)
            a.elbowB = pt(0.3, 0.73); a.handB = pt(0.31, 0.6)
            var b = a
            b.kneeF = pt(0.71, 0.8); b.footF = pt(0.87, 0.79)
            b.elbowB = pt(0.2, 0.78); b.handB = pt(0.08, 0.8)
            return (a, b)
        case .rowing:
            let front = FigurePose(head: pt(0.52, 0.36), shoulder: pt(0.48, 0.47), hip: pt(0.4, 0.72))
                .legs(knee: pt(0.56, 0.55), foot: pt(0.7, 0.74))
                .arms(elbow: pt(0.58, 0.5), hand: pt(0.7, 0.52))
            let back = FigurePose(head: pt(0.2, 0.36), shoulder: pt(0.23, 0.48), hip: pt(0.3, 0.72))
                .legs(knee: pt(0.5, 0.7), foot: pt(0.7, 0.74))
                .arms(elbow: pt(0.2, 0.59), hand: pt(0.36, 0.54))
            return (front, back)
        case .twist, .woodchop:
            return (stand.arms(elbow: pt(0.4, 0.2), hand: pt(0.32, 0.08)),
                    stand.arms(elbow: pt(0.62, 0.44), hand: pt(0.74, 0.6)))
        case .lungeReach:
            var base = FigurePose(head: pt(0.52, 0.27), shoulder: pt(0.5, 0.39), hip: pt(0.48, 0.68))
            base.kneeF = pt(0.65, 0.72); base.footF = pt(0.66, 0.9)
            base.kneeB = pt(0.4, 0.88); base.footB = pt(0.24, 0.88)
            return (base.arms(elbow: pt(0.5, 0.54), hand: pt(0.52, 0.68)),
                    base.arms(elbow: pt(0.53, 0.25), hand: pt(0.55, 0.11)))
        case .childsPose:
            let allFours = FigurePose(head: pt(0.81, 0.58), shoulder: pt(0.7, 0.62), hip: pt(0.35, 0.62))
                .legs(knee: pt(0.35, 0.9), foot: pt(0.15, 0.9))
                .arms(elbow: pt(0.7, 0.76), hand: pt(0.7, 0.9))
            let back = FigurePose(head: pt(0.6, 0.86), shoulder: pt(0.52, 0.8), hip: pt(0.27, 0.78))
                .legs(knee: pt(0.38, 0.9), foot: pt(0.15, 0.9))
                .arms(elbow: pt(0.66, 0.86), hand: pt(0.8, 0.9))
            return (allFours, back)
        case .legPress:
            let seated = FigurePose(head: pt(0.26, 0.46), shoulder: pt(0.3, 0.57), hip: pt(0.42, 0.78))
                .arms(elbow: pt(0.36, 0.7), hand: pt(0.44, 0.8))
            return (seated.legs(knee: pt(0.56, 0.56), foot: pt(0.68, 0.66)),
                    seated.legs(knee: pt(0.62, 0.66), foot: pt(0.82, 0.56)))
        }
    }

    // MARK: Lookup

    private static let byExerciseID: [String: ExerciseMotion] = [
        "back-squat": .backSquat, "goblet-squat": .gobletSquat, "bodyweight-squat": .squat,
        "romanian-deadlift": .hinge, "leg-press": .legPress,
        "walking-lunge": .lunge, "reverse-lunge": .lunge,
        "bench-press": .benchPress, "dumbbell-bench-press": .dumbbellBench,
        "overhead-press": .press, "lat-pulldown": .pulldown, "seated-row": .seatedRow,
        "dumbbell-row": .bentRow, "cable-woodchop": .woodchop, "hanging-knee-raise": .kneeRaise,
        "glute-bridge": .bridge, "step-up": .stepUp, "push-up": .pushUp, "pike-push-up": .pikePushUp,
        "chair-dip": .dip, "superman": .superman, "plank": .plank, "dead-bug": .deadBug,
        "mountain-climber": .climber, "burpee": .burpee,
        "brisk-walk": .walk, "easy-run": .run, "run-intervals": .run, "cycling": .cycle,
        "rowing": .rowing, "jump-rope": .jumpRope, "stair-climb": .stairs, "swimming": .superman,
        "cat-cow": .catCow, "worlds-greatest-stretch": .lungeReach, "hip-flexor-stretch": .lungeReach,
        "hamstring-stretch": .fold, "thoracic-rotation": .twist, "shoulder-circles": .armCircle,
        "childs-pose": .childsPose, "ankle-rocks": .lungeReach,
        "lateral-raise": .lateralRaise, "reverse-fly": .reverseFly, "single-leg-deadlift": .singleLegDeadlift,
        "side-lunge": .sideLunge, "jumping-jack": .jumpingJack, "leg-extension-crunch": .crunch,
        "high-knees": .highKnees, "marching": .march, "front-kick": .frontKick, "skipping": .skip,
        "windmill-toe-touch": .windmill, "standing-knee-lift": .kneeLift, "overhead-arm-raise": .armRaise,
        "squat-and-reach": .squatReach, "leg-circles": .hipCircle, "shadow-boxing": .boxing,
        "side-shuffle": .sideShuffle, "jump-squat": .jumpSquat,
        // Mat Pilates: the nearest posed movement (none of these has a drawing yet).
        "pilates-hundred": .crunch, "pilates-roll-up": .crunch, "pilates-single-leg-circles": .deadBug,
        "pilates-rolling-like-a-ball": .crunch, "pilates-single-leg-stretch": .deadBug,
        "pilates-double-leg-stretch": .deadBug, "pilates-criss-cross": .crunch,
        "pilates-spine-stretch-forward": .fold, "pilates-saw": .windmill, "pilates-swan": .superman,
        "pilates-swimming": .superman, "pilates-side-kick-series": .hipCircle, "pilates-teaser": .crunch,
        "pilates-shoulder-bridge": .bridge, "pilates-leg-pull-front": .plank, "pilates-leg-pull-back": .bridge,
        "pilates-open-leg-rocker": .crunch, "pilates-spine-twist": .twist, "pilates-scissors": .deadBug,
        "pilates-mermaid": .windmill,
        // HYROX stations and running.
        "sled-push": .run, "sled-pull": .boxing, "burpee-broad-jump": .burpee, "wall-ball": .squatReach,
        "sandbag-lunge": .barbellLunge, "long-run": .run,
    ]

    static func forExercise(id: String) -> ExerciseMotion? { byExerciseID[id] }

    /// A movement waiting for review: built, but not yet an exercise in the catalogue.
    var candidateTitle: String? {
        switch self {
        case .farmerCarry: return "Farmer's carry"
        case .dumbbellSquat: return "Dumbbell squat"
        case .barbellLunge: return "Barbell lunge"
        case .gobletSideLunge: return "Goblet side lunge"
        case .dumbbellSingleLegDeadlift: return "Dumbbell single-leg deadlift"
        case .dumbbellPunch: return "Dumbbell punches"
        case .raiseOverhead: return "Lateral-to-overhead raise"
        case .dumbbellSquatReach: return "Dumbbell squat to overhead reach"
        case .barbellCurl: return "Barbell curl"
        case .dumbbellCurl: return "Dumbbell curl"
        case .frontRaise: return "Front raise"
        case .uprightRow: return "Upright row"
        case .shrug: return "Dumbbell shrug"
        case .deadlift: return "Deadlift"
        case .tricepsOverhead: return "Overhead triceps extension"
        case .kickback: return "Triceps kickback"
        case .dumbbellPress: return "Dumbbell shoulder press"
        default: return nil
        }
    }

    /// Best match for a free-text exercise name (AI-written workouts). A catalogue
    /// exercise with the same (or nearly the same) name wins; otherwise whole words
    /// and phrases are matched, most specific first, so "Narrow-grip push-up" is a
    /// push-up and "Overhead triceps extension" is not a press. `nil` when nothing
    /// fits, so no misleading demo is shown.
    static func matching(name: String) -> ExerciseMotion? {
        if let known = Exercise.closestMatch(name: name), let motion = known.motion { return motion }
        let words = ExerciseText.matchWords(name)
        return rules.first { rule in
            rule.phrases.contains { ExerciseText.containsFolded(words, $0) }
                && !(rule.motion == .walk && notAPlainWalk(words))
        }?.motion
    }

    /// Words that make a "walk" a different exercise (a wall walk, crab walk, banded
    /// monster walk, waiter's walk …): no demo is better than a misleading plain walk.
    private static let notWalkWords: Set<String> = [
        "wall", "crab", "bear", "duck", "spider", "hand", "monster", "band", "banded", "lateral",
        "out", "plank", "inchworm", "waiter", "suitcase", "farmer", "carry", "overhead", "sled",
        "lunge", "knee", "tightrope", "heel", "toe", "squat",
    ]

    private static func notAPlainWalk(_ words: [String]) -> Bool {
        words.contains { notWalkWords.contains($0) }
    }

    /// Phrases are matched as whole words, after plurals are folded ("lunges" → "lunge").
    private static let rules: [(phrases: [String], motion: ExerciseMotion)] = [
        (["mountain climber"], .climber), (["burpee"], .burpee),
        (["pike push up", "pike pushup"], .pikePushUp), (["push up", "pushup"], .pushUp),
        (["dumbbell bench", "dumbbell chest press"], .dumbbellBench), (["bench press", "chest press"], .benchPress),
        (["goblet squat"], .gobletSquat), (["back squat", "barbell squat"], .backSquat),
        (["jump squat", "squat jump"], .jumpSquat), (["leg press"], .legPress),
        (["overhead press", "shoulder press", "military press"], .press),
        (["lat pulldown", "pulldown", "pull down", "pull up", "pullup", "chin up", "chinup"], .pulldown),
        (["dumbbell row", "one arm row", "single arm row"], .bentRow),
        (["bent over row", "barbell row"], .barbellRow),
        (["rowing machine", "rower", "rowing", "erg row"], .rowing),
        (["seated row", "cable row", "seated cable row"], .seatedRow),
        (["upright row"], .uprightRow),
        (["single leg deadlift", "single leg romanian deadlift"], .singleLegDeadlift),
        (["romanian deadlift", "rdl", "deadlift", "good morning", "hip hinge", "kettlebell swing"], .hinge),
        (["side lunge", "lateral lunge"], .sideLunge),
        (["lunge", "split squat"], .lunge), (["step up"], .stepUp),
        (["stair", "stair climb", "stair climber"], .stairs), (["squat"], .squat),
        (["glute bridge", "hip bridge", "hip thrust"], .bridge), (["plank"], .plank), (["dead bug"], .deadBug),
        (["knee raise", "leg raise"], .kneeRaise), (["dip"], .dip), (["superman"], .superman),
        (["woodchop", "wood chop"], .woodchop), (["russian twist", "twist", "thoracic rotation"], .twist),
        (["jump rope", "skipping rope", "skip rope", "rope skipping"], .jumpRope),
        (["jumping jack", "star jump"], .jumpingJack), (["high knee"], .highKnees),
        (["lateral raise", "side raise"], .lateralRaise), (["reverse fly", "rear delt fly"], .reverseFly),
        (["shadow boxing", "shadowboxing"], .boxing), (["march", "marching"], .march), (["front kick"], .frontKick),
        (["box jump", "tuck jump", "jump"], .jump),
        (["cycling", "cycle", "bike", "spin", "spinning"], .cycle),
        (["sprint", "jog", "jogging", "run", "running", "interval"], .run),
        (["walk", "walking", "hike", "hiking"], .walk),
        (["swim", "swimming"], .superman),
        (["cat cow", "cat camel"], .catCow), (["child's pose", "childs pose", "child pose"], .childsPose),
        (["hamstring stretch", "forward fold", "toe touch"], .fold),
        (["hip flexor stretch", "hip flexor", "world's greatest stretch", "worlds greatest stretch"], .lungeReach),
        (["arm circle", "shoulder circle"], .armCircle), (["leg circle", "hip circle"], .hipCircle),
    ]
}

extension Exercise {
    var motion: ExerciseMotion? { ExerciseMotion.forExercise(id: id) }

    /// The catalogue exercise a free-text name refers to: the same name ignoring case,
    /// or the same words ignoring hyphens and plurals ("Push ups" → "Push-up").
    static func closestMatch(name: String) -> Exercise? {
        if let exact = named(name) { return exact }
        let words = ExerciseText.matchWords(name)
        guard !words.isEmpty else { return nil }
        return byMatchWords[words.joined(separator: " ")]
    }

    private static let byMatchWords: [String: Exercise] = Dictionary(
        catalog.map { (ExerciseText.matchWords($0.name).joined(separator: " "), $0) },
        uniquingKeysWith: { first, _ in first })
}

extension ExerciseText {
    /// Words for matching: lowercased, apostrophes dropped ("Child's" → "childs"), hyphens
    /// split, plurals folded ("Lunges" → "lunge", "Push ups" → "push up", "childs" → "child");
    /// two-letter words and "-ss" words are kept.
    static func matchWords(_ text: String) -> [String] {
        let plain = text.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
        return words(plain).map { word in
            guard word.count >= 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
            return String(word.dropLast())
        }
    }

    /// `contains` for a phrase, folding the phrase's plurals the same way.
    static func containsFolded(_ words: [String], _ phrase: String) -> Bool {
        contains(words, matchWords(phrase).joined(separator: " "))
    }
}

// MARK: - Drawing

extension ExerciseMotion {
    /// Movements that swing continuously from side to side (no start and finish to pause on).
    var isContinuous: Bool {
        switch self {
        case .run, .walk, .cycle, .climber, .stairs,
             .jumpingJack, .highKnees, .march, .frontKick, .skip, .boxing, .sideShuffle,
             .farmerCarry, .dumbbellPunch: return true
        default: return false
        }
    }
}

/// A single still frame: the start or the finish position.
struct ExerciseFrame: View {
    let motion: ExerciseMotion
    /// `false` for the start position, `true` for the finish.
    let finish: Bool

    var body: some View {
        LineFigureCanvas(frame: ExerciseStill.frame(motion, finish: finish), muscles: motion.muscles)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// The moving demo. It plays a few reps when it appears and when tapped, then
/// rests on the start position, so nothing on screen animates forever. Each
/// rep pauses at the start and at the finish so both positions register.
/// Under Reduce Motion it never moves (the still frames carry the meaning).
struct ExerciseDemo: View {
    let motion: ExerciseMotion
    var reps: Int = 5

    @State private var startedAt: Date?
    @State private var holder = FigureHolder()
    /// How far the figure has been turned by dragging, in radians.
    @State private var turn: Float = 0
    @State private var turnAtDragStart: Float?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var period: Double { motion.clip?.duration ?? RepTempo.period(for: motion) }
    private var runTime: Double { period * Double(reps) }
    private var isPlaying: Bool { startedAt != nil }

    var body: some View {
        let (a, b) = motion.poses
        ZStack(alignment: .bottomTrailing) {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { timeline in
                let elapsed = startedAt.map { timeline.date.timeIntervalSince($0) } ?? runTime
                let done = elapsed >= runTime
                LineFigureCanvas(frame: pose(elapsed: done ? nil : elapsed, a, b), muscles: motion.muscles, turn: turn)
                    .onChange(of: done) { _, finished in if finished { startedAt = nil } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { drag in
                    let start = turnAtDragStart ?? turn
                    turnAtDragStart = start
                    turn = start - Float(drag.translation.width) / 120
                }
                .onEnded { _ in turnAtDragStart = nil })

            // Dragging the figure turns the view, so playing has its own button.
            if !reduceMotion {
                Button { play() } label: {
                    Label(isPlaying ? "Playing" : "Play", systemImage: isPlaying ? "waveform" : "play.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
                        .foregroundStyle(Color.labelPrimary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ScalePressStyle())
                .disabled(isPlaying)
                .opacity(isPlaying ? 0.6 : 1)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xs)
                .accessibilityLabel("Play the movement")
                .accessibilityIdentifier("exerciseDemo.play")
            }
        }
        .onAppear { play() }
        .animation(.snappyValue, value: isPlaying)
    }

    private func play() {
        guard !reduceMotion else { return }
        startedAt = Date()
    }

    /// Poses the figure for this moment of the movement (`nil`: resting on the start position).
    private func pose(elapsed: Double?, _ a: FigurePose, _ b: FigurePose) -> FigureFrame {
        let figure = holder.figure(for: motion)
        if let clip = motion.clip {
            // Captured human movement.
            figure.apply(clip: clip, at: elapsed.map { $0.truncatingRemainder(dividingBy: clip.duration) } ?? 0)
        } else if let gait = motion.gait {
            // A stride cycle: the pose is generated for this moment.
            let phase = (elapsed ?? 0) / gait.period
            let pose = elapsed == nil ? a : gait.pose(phase: phase)
            figure.apply(from: pose, to: pose, progress: CGFloat(phase - phase.rounded(.down)))
        } else {
            let state = elapsed.map { RepTempo.state(for: motion, elapsed: $0) } ?? RepState()
            figure.apply(from: a, to: b, progress: motion.legsLead ? state.legs : state.armNear, parts: state)
        }
        return figure.frame()
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
            ForEach(ExerciseMotion.allCases, id: \.self) { motion in
                VStack {
                    ExerciseDemo(motion: motion, reps: 50)
                    Text(motion.rawValue).font(.caption2)
                }
            }
        }
        .padding()
    }
}
