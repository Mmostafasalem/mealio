import SwiftUI

// MARK: - Animated exercise figure
//
// A stick figure, drawn in code, that shows how a movement goes: it loops
// between the start and end position of the exercise (side view, facing
// right). No image assets. Each exercise maps to one of a few dozen motions.
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

    enum Prop { case none, barbell, dumbbells, bench, highBar, step, wheels, seat }

    var prop: Prop {
        switch self {
        case .benchPress:            return .bench
        case .press, .hinge:         return .barbell
        case .bentRow, .lunge:       return .dumbbells
        case .pulldown, .kneeRaise:  return .highBar
        case .stepUp, .dip:          return .step
        case .cycle:                 return .wheels
        case .seatedRow, .rowing, .legPress: return .seat
        default:                     return .none
        }
    }

    /// Seconds for one full rep (there and back).
    var period: Double {
        switch self {
        case .run, .climber:          return 0.7
        case .walk, .cycle, .jump:    return 1.0
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
        case .lunge:
            var down = FigurePose(head: pt(0.5, 0.25), shoulder: pt(0.5, 0.37), hip: pt(0.5, 0.66))
            down.kneeF = pt(0.65, 0.72); down.footF = pt(0.66, 0.9)
            down.kneeB = pt(0.42, 0.86); down.footB = pt(0.27, 0.87)
            return (stand, down.arms(elbow: pt(0.5, 0.52), hand: pt(0.52, 0.66)))
        case .hinge:
            let down = FigurePose(head: pt(0.76, 0.44), shoulder: pt(0.65, 0.48), hip: pt(0.41, 0.55))
                .legs(knee: pt(0.47, 0.72), foot: pt(0.5, 0.9))
                .arms(elbow: pt(0.65, 0.6), hand: pt(0.64, 0.74))
            return (stand.arms(elbow: pt(0.51, 0.41), hand: pt(0.53, 0.56)), down)
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
        case .benchPress:
            let lying = FigurePose(head: pt(0.24, 0.6), shoulder: pt(0.35, 0.62), hip: pt(0.6, 0.62))
                .legs(knee: pt(0.76, 0.62), foot: pt(0.8, 0.9))
            return (lying.arms(elbow: pt(0.4, 0.7), hand: pt(0.38, 0.54)),
                    lying.arms(elbow: pt(0.37, 0.47), hand: pt(0.37, 0.33)))
        case .seatedRow:
            let seated = FigurePose(head: pt(0.43, 0.32), shoulder: pt(0.42, 0.44), hip: pt(0.4, 0.72))
                .legs(knee: pt(0.6, 0.64), foot: pt(0.74, 0.78))
            var back = seated
            back.head = pt(0.39, 0.32); back.shoulder = pt(0.38, 0.44)
            return (seated.arms(elbow: pt(0.58, 0.5), hand: pt(0.72, 0.52)),
                    back.arms(elbow: pt(0.3, 0.58), hand: pt(0.46, 0.55)))
        case .pulldown:
            let seated = FigurePose(head: pt(0.5, 0.36), shoulder: pt(0.5, 0.48), hip: pt(0.5, 0.74))
                .legs(knee: pt(0.68, 0.72), foot: pt(0.68, 0.9))
            return (seated.arms(elbow: pt(0.52, 0.3), hand: pt(0.54, 0.12)),
                    seated.arms(elbow: pt(0.56, 0.6), hand: pt(0.56, 0.44)))
        case .bentRow:
            let bent = FigurePose(head: pt(0.76, 0.44), shoulder: pt(0.65, 0.48), hip: pt(0.41, 0.55))
                .legs(knee: pt(0.47, 0.72), foot: pt(0.5, 0.9))
            return (bent.arms(elbow: pt(0.65, 0.6), hand: pt(0.64, 0.74)),
                    bent.arms(elbow: pt(0.55, 0.42), hand: pt(0.62, 0.54)))
        case .bridge:
            let lying = FigurePose(head: pt(0.19, 0.85), shoulder: pt(0.3, 0.86), hip: pt(0.5, 0.86))
                .legs(knee: pt(0.66, 0.66), foot: pt(0.76, 0.9))
                .arms(elbow: pt(0.4, 0.88), hand: pt(0.5, 0.89))
            var up = lying
            up.hip = pt(0.5, 0.67)
            return (lying, up)
        case .run:
            var a = FigurePose(head: pt(0.55, 0.15), shoulder: pt(0.52, 0.27), hip: pt(0.49, 0.55))
            a.kneeF = pt(0.63, 0.64); a.footF = pt(0.6, 0.82)
            a.kneeB = pt(0.42, 0.74); a.footB = pt(0.28, 0.72)
            a.elbowF = pt(0.44, 0.4); a.handF = pt(0.38, 0.5)
            a.elbowB = pt(0.6, 0.38); a.handB = pt(0.66, 0.29)
            return (a, a.mirroredLimbs)
        case .walk:
            var a = FigurePose()
            a.kneeF = pt(0.56, 0.72); a.footF = pt(0.62, 0.9)
            a.kneeB = pt(0.46, 0.73); a.footB = pt(0.4, 0.89)
            a.elbowF = pt(0.46, 0.4); a.handF = pt(0.43, 0.52)
            a.elbowB = pt(0.55, 0.4); a.handB = pt(0.6, 0.5)
            return (a, a.mirroredLimbs)
        case .cycle:
            var a = FigurePose(head: pt(0.66, 0.24), shoulder: pt(0.58, 0.34), hip: pt(0.4, 0.5))
                .arms(elbow: pt(0.68, 0.42), hand: pt(0.76, 0.46))
            a.kneeF = pt(0.6, 0.55); a.footF = pt(0.57, 0.74)
            a.kneeB = pt(0.5, 0.66); a.footB = pt(0.5, 0.86)
            return (a, a.mirroredLimbs)
        case .jump:
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
            return (stand.arms(elbow: pt(0.57, 0.16), hand: pt(0.62, 0.04)),
                    stand.arms(elbow: pt(0.42, 0.36), hand: pt(0.36, 0.48)))
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
                .arms(elbow: pt(0.58, 0.54), hand: pt(0.7, 0.58))
            let back = FigurePose(head: pt(0.2, 0.36), shoulder: pt(0.23, 0.48), hip: pt(0.3, 0.72))
                .legs(knee: pt(0.5, 0.7), foot: pt(0.7, 0.74))
                .arms(elbow: pt(0.2, 0.62), hand: pt(0.36, 0.58))
            return (front, back)
        case .twist:
            return (stand.arms(elbow: pt(0.44, 0.24), hand: pt(0.4, 0.12)),
                    stand.arms(elbow: pt(0.6, 0.46), hand: pt(0.68, 0.6)))
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
        "back-squat": .squat, "goblet-squat": .squat, "bodyweight-squat": .squat,
        "romanian-deadlift": .hinge, "leg-press": .legPress,
        "walking-lunge": .lunge, "reverse-lunge": .lunge,
        "bench-press": .benchPress, "dumbbell-bench-press": .benchPress,
        "overhead-press": .press, "lat-pulldown": .pulldown, "seated-row": .seatedRow,
        "dumbbell-row": .bentRow, "cable-woodchop": .twist, "hanging-knee-raise": .kneeRaise,
        "glute-bridge": .bridge, "step-up": .stepUp, "push-up": .pushUp, "pike-push-up": .pikePushUp,
        "chair-dip": .dip, "superman": .superman, "plank": .plank, "dead-bug": .deadBug,
        "mountain-climber": .climber, "burpee": .burpee,
        "brisk-walk": .walk, "easy-run": .run, "run-intervals": .run, "cycling": .cycle,
        "rowing": .rowing, "jump-rope": .jump, "stair-climb": .stepUp, "swimming": .superman,
        "cat-cow": .catCow, "worlds-greatest-stretch": .lungeReach, "hip-flexor-stretch": .lungeReach,
        "hamstring-stretch": .fold, "thoracic-rotation": .twist, "shoulder-circles": .armCircle,
        "childs-pose": .childsPose, "ankle-rocks": .lungeReach,
    ]

    static func forExercise(id: String) -> ExerciseMotion? { byExerciseID[id] }

    /// Best match for a free-text exercise name (AI-written workouts). `nil`
    /// when nothing fits, so no misleading demo is shown.
    static func matching(name: String) -> ExerciseMotion? {
        let n = name.lowercased()
        if let exact = Exercise.catalog.first(where: { $0.name.lowercased() == n }) { return byExerciseID[exact.id] }
        // Order matters: more specific phrases first.
        let rules: [(String, ExerciseMotion)] = [
            ("mountain climber", .climber), ("burpee", .burpee), ("pike", .pikePushUp), ("push-up", .pushUp),
            ("push up", .pushUp), ("pushup", .pushUp), ("bench", .benchPress), ("chest press", .benchPress),
            ("leg press", .legPress), ("overhead", .press), ("shoulder press", .press), ("military", .press),
            ("pulldown", .pulldown), ("pull-down", .pulldown), ("pull-up", .pulldown), ("pull up", .pulldown), ("chin", .pulldown),
            ("bent", .bentRow), ("dumbbell row", .bentRow), ("rowing", .rowing), ("rower", .rowing), ("row", .seatedRow),
            ("deadlift", .hinge), ("good morning", .hinge), ("hip hinge", .hinge), ("kettlebell swing", .hinge),
            ("lunge", .lunge), ("split squat", .lunge), ("step", .stepUp), ("stair", .stepUp), ("squat", .squat),
            ("bridge", .bridge), ("hip thrust", .bridge), ("plank", .plank), ("dead bug", .deadBug),
            ("knee raise", .kneeRaise), ("leg raise", .kneeRaise), ("dip", .dip), ("superman", .superman),
            ("woodchop", .twist), ("twist", .twist), ("rotation", .twist),
            ("jump", .jump), ("skipping", .jump), ("rope", .jump),
            ("sprint", .run), ("interval", .run), ("jog", .run), ("run", .run), ("walk", .walk),
            ("cycl", .cycle), ("bike", .cycle), ("spin", .cycle), ("swim", .superman),
            ("cat", .catCow), ("child", .childsPose), ("hamstring", .fold), ("forward fold", .fold), ("toe touch", .fold),
            ("hip flexor", .lungeReach), ("world's greatest", .lungeReach), ("circle", .armCircle),
        ]
        return rules.first { n.contains($0.0) }?.1
    }
}

extension Exercise {
    var motion: ExerciseMotion? { ExerciseMotion.forExercise(id: id) }
}

// MARK: - Drawing

/// Draws one pose. `ghost` is drawn faintly behind it (the other end of the movement).
struct ExerciseFigureCanvas: View {
    let pose: FigurePose
    var ghost: FigurePose? = nil
    let prop: ExerciseMotion.Prop

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            func at(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * side, y: origin.y + p.y * side) }
            let limb = side * 0.045

            // Floor
            var floor = Path()
            floor.move(to: at(pt(0.04, 0.925))); floor.addLine(to: at(pt(0.96, 0.925)))
            context.stroke(floor, with: .color(Color.hairline), style: StrokeStyle(lineWidth: max(1, side * 0.012), lineCap: .round))

            drawProp(&context, pose: pose, at: at, side: side)
            if let ghost {
                context.opacity = 0.18
                drawFigure(&context, ghost, at: at, limb: limb, side: side)
                context.opacity = 1
            }
            drawFigure(&context, pose, at: at, limb: limb, side: side)
        }
        .accessibilityHidden(true)
    }

    private func line(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }

    private func drawFigure(_ context: inout GraphicsContext, _ p: FigurePose, at: (CGPoint) -> CGPoint, limb: CGFloat, side: CGFloat) {
        let style = StrokeStyle(lineWidth: limb, lineCap: .round, lineJoin: .round)
        let far = Color.labelTertiary
        let near = Color.labelPrimary
        // Far limbs first so the near ones overlap them.
        context.stroke(line([at(p.hip), at(p.kneeB), at(p.footB)]), with: .color(far), style: style)
        context.stroke(line([at(p.shoulder), at(p.elbowB), at(p.handB)]), with: .color(far), style: style)
        let mid = p.spine ?? CGPoint(x: (p.shoulder.x + p.hip.x) / 2, y: (p.shoulder.y + p.hip.y) / 2)
        var torso = Path()
        torso.move(to: at(p.shoulder))
        torso.addQuadCurve(to: at(p.hip), control: at(CGPoint(x: mid.x * 2 - (p.shoulder.x + p.hip.x) / 2,
                                                              y: mid.y * 2 - (p.shoulder.y + p.hip.y) / 2)))
        context.stroke(torso, with: .color(near), style: StrokeStyle(lineWidth: limb * 1.25, lineCap: .round))
        context.stroke(line([at(p.hip), at(p.kneeF), at(p.footF)]), with: .color(near), style: style)
        context.stroke(line([at(p.shoulder), at(p.elbowF), at(p.handF)]), with: .color(near), style: style)
        let r = side * 0.075
        let head = at(p.head)
        context.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)), with: .color(near))
    }

    private func drawProp(_ context: inout GraphicsContext, pose p: FigurePose, at: (CGPoint) -> CGPoint, side: CGFloat) {
        let tint = Color.progress
        let thin = StrokeStyle(lineWidth: side * 0.03, lineCap: .round)
        func disc(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
        switch prop {
        case .none:
            break
        case .barbell:
            // Seen end-on from the side: a plate at the hands.
            context.fill(disc(at(p.handF), side * 0.075), with: .color(tint))
        case .dumbbells:
            context.fill(disc(at(p.handF), side * 0.045), with: .color(tint))
            context.fill(disc(at(p.handB), side * 0.045), with: .color(tint.opacity(0.6)))
        case .bench:
            context.stroke(line([at(pt(0.18, 0.67)), at(pt(0.66, 0.67))]), with: .color(tint), style: StrokeStyle(lineWidth: side * 0.045, lineCap: .round))
            context.stroke(line([at(pt(0.26, 0.69)), at(pt(0.26, 0.9))]), with: .color(tint), style: thin)
            context.stroke(line([at(pt(0.58, 0.69)), at(pt(0.58, 0.9))]), with: .color(tint), style: thin)
            context.fill(disc(at(p.handF), side * 0.07), with: .color(tint))
        case .highBar:
            let y = min(p.handF.y, 0.12)
            context.stroke(line([at(pt(0.36, y)), at(pt(0.7, y))]), with: .color(tint), style: StrokeStyle(lineWidth: side * 0.035, lineCap: .round))
            // The bar travels with the hands on a pulldown; the cable stays up.
            if p.handF.y > 0.14 {
                context.stroke(line([at(pt(0.55, 0.0)), at(p.handF)]), with: .color(tint.opacity(0.5)), style: StrokeStyle(lineWidth: side * 0.015))
                context.stroke(line([at(pt(p.handF.x - 0.12, p.handF.y)), at(pt(p.handF.x + 0.12, p.handF.y))]), with: .color(tint), style: StrokeStyle(lineWidth: side * 0.035, lineCap: .round))
            }
        case .step:
            let box = CGRect(x: at(pt(0.3, 0.64)).x, y: at(pt(0.3, 0.64)).y, width: side * 0.16, height: side * 0.28)
            let stepBox = CGRect(x: at(pt(0.55, 0.8)).x, y: at(pt(0.55, 0.8)).y, width: side * 0.22, height: side * 0.12)
            // A chair behind for dips, a low box in front for step-ups.
            let rect = p.handF.y > 0.55 && p.hip.y > 0.55 && p.footF.y > 0.85 ? box : stepBox
            context.fill(Path(roundedRect: rect, cornerRadius: side * 0.02), with: .color(tint.opacity(0.55)))
        case .wheels:
            let ring = StrokeStyle(lineWidth: side * 0.025)
            context.stroke(disc(at(pt(0.26, 0.76)), side * 0.15), with: .color(tint), style: ring)
            context.stroke(disc(at(pt(0.78, 0.76)), side * 0.15), with: .color(tint), style: ring)
            context.stroke(line([at(pt(0.26, 0.76)), at(pt(0.4, 0.52)), at(pt(0.53, 0.8)), at(pt(0.26, 0.76))]), with: .color(tint), style: ring)
            context.stroke(line([at(pt(0.53, 0.8)), at(pt(0.72, 0.5)), at(pt(0.78, 0.76))]), with: .color(tint), style: ring)
        case .seat:
            context.stroke(line([at(pt(p.hip.x - 0.08, p.hip.y + 0.06)), at(pt(p.hip.x + 0.08, p.hip.y + 0.06))]),
                           with: .color(tint), style: StrokeStyle(lineWidth: side * 0.04, lineCap: .round))
            context.stroke(line([at(pt(0.14, 0.9)), at(pt(0.86, 0.9))]), with: .color(tint.opacity(0.5)), style: thin)
        }
    }
}

/// The looping demo. It plays a few reps when it appears and when tapped, then
/// rests on the end position (with the start shown faintly), so nothing on
/// screen animates forever. Under Reduce Motion it never moves.
struct ExerciseDemo: View {
    let motion: ExerciseMotion
    var reps: Int = 4

    @State private var startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var runTime: Double { motion.period * Double(reps) }

    var body: some View {
        let (a, b) = motion.poses
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: startedAt == nil)) { timeline in
            let elapsed = startedAt.map { timeline.date.timeIntervalSince($0) } ?? runTime
            if elapsed >= runTime || reduceMotion {
                ExerciseFigureCanvas(pose: b, ghost: a, prop: motion.prop)
                    .onChange(of: elapsed >= runTime, initial: true) { _, done in if done { startedAt = nil } }
            } else {
                // Ease there and back: 0 → 1 → 0 once per period.
                let phase = 0.5 - 0.5 * cos(2 * .pi * elapsed / motion.period)
                ExerciseFigureCanvas(pose: a.lerp(to: b, phase), prop: motion.prop)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture { play() }
        .onAppear { play() }
        .accessibilityElement()
        .accessibilityLabel("Movement demo")
        .accessibilityHint("Replays the animation")
        .accessibilityAddTraits(.isButton)
    }

    private func play() {
        guard !reduceMotion else { return }
        startedAt = Date()
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
