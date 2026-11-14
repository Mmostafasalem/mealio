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
            let seated = FigurePose(head: pt(0.44, 0.36), shoulder: pt(0.45, 0.48), hip: pt(0.46, 0.74))
                .legs(knee: pt(0.66, 0.73), foot: pt(0.67, 0.92))
            return (seated.arms(elbow: pt(0.5, 0.31), hand: pt(0.54, 0.14)),
                    seated.arms(elbow: pt(0.5, 0.64), hand: pt(0.57, 0.47)))
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
                .arms(elbow: pt(0.58, 0.54), hand: pt(0.7, 0.58))
            let back = FigurePose(head: pt(0.2, 0.36), shoulder: pt(0.23, 0.48), hip: pt(0.3, 0.72))
                .legs(knee: pt(0.5, 0.7), foot: pt(0.7, 0.74))
                .arms(elbow: pt(0.2, 0.62), hand: pt(0.36, 0.58))
            return (front, back)
        case .twist:
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

extension ExerciseMotion {
    /// Movements that swing continuously from side to side (no start and finish to pause on).
    var isContinuous: Bool {
        switch self {
        case .run, .walk, .cycle, .climber: return true
        default: return false
        }
    }

    /// Which limbs do the work, so they can be highlighted. Measured as how far
    /// the hand moves relative to the shoulder and the foot relative to the hip.
    var workingLimbs: (arms: Bool, legs: Bool) {
        let (a, b) = poses
        func travel(_ root: KeyPath<FigurePose, CGPoint>, _ end: KeyPath<FigurePose, CGPoint>) -> CGFloat {
            let da = CGPoint(x: a[keyPath: end].x - a[keyPath: root].x, y: a[keyPath: end].y - a[keyPath: root].y)
            let db = CGPoint(x: b[keyPath: end].x - b[keyPath: root].x, y: b[keyPath: end].y - b[keyPath: root].y)
            return hypot(da.x - db.x, da.y - db.y)
        }
        let arms = max(travel(\.shoulder, \.handF), travel(\.shoulder, \.handB))
        let legs = max(travel(\.hip, \.footF), travel(\.hip, \.footB), travel(\.hip, \.kneeF))
        if isContinuous { return (true, true) }
        if arms < 0.08 && legs < 0.08 { return (false, false) }       // a hold
        // Highlight the clear leader; both only when they move about equally.
        return (arms >= legs * 0.7, legs >= arms * 0.7)
    }
}

/// Draws one pose of the figure: a solid body, the far-side limbs paler so
/// they read as behind, and the working limbs in the accent colour.
struct ExerciseFigureCanvas: View {
    let pose: FigurePose
    let prop: ExerciseMotion.Prop
    var working: (arms: Bool, legs: Bool) = (false, false)

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            func at(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * side, y: origin.y + p.y * side) }

            // Floor
            var floor = Path()
            floor.move(to: at(pt(0.04, 0.935))); floor.addLine(to: at(pt(0.96, 0.935)))
            context.stroke(floor, with: .color(Color.labelTertiary.opacity(0.35)),
                           style: StrokeStyle(lineWidth: max(1, side * 0.012), lineCap: .round))

            drawProp(&context, pose: pose, at: at, side: side)
            drawFigure(&context, pose, at: at, side: side)
        }
        .accessibilityHidden(true)
    }

    private func line(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }

    private func drawFigure(_ context: inout GraphicsContext, _ p: FigurePose, at: (CGPoint) -> CGPoint, side: CGFloat) {
        let body = Color.labelPrimary
        let accent = Color.progress
        func limb(_ points: [CGPoint], active: Bool, far: Bool) {
            let colour = (active ? accent : body).opacity(far ? 0.38 : 1)
            context.stroke(line(points.map(at)), with: .color(colour),
                           style: StrokeStyle(lineWidth: side * (far ? 0.05 : 0.062), lineCap: .round, lineJoin: .round))
        }
        // Far side first, then torso and head, then the near side on top.
        limb([p.hip, p.kneeB, p.footB], active: working.legs, far: true)
        limb([p.shoulder, p.elbowB, p.handB], active: working.arms, far: true)

        let mid = p.spine ?? CGPoint(x: (p.shoulder.x + p.hip.x) / 2, y: (p.shoulder.y + p.hip.y) / 2)
        var torso = Path()
        torso.move(to: at(p.shoulder))
        torso.addQuadCurve(to: at(p.hip), control: at(CGPoint(x: mid.x * 2 - (p.shoulder.x + p.hip.x) / 2,
                                                              y: mid.y * 2 - (p.shoulder.y + p.hip.y) / 2)))
        context.stroke(torso, with: .color(body), style: StrokeStyle(lineWidth: side * 0.105, lineCap: .round))

        // A short neck joins the head to the shoulders so the head never floats.
        context.stroke(line([at(p.shoulder), at(p.head)]), with: .color(body),
                       style: StrokeStyle(lineWidth: side * 0.045, lineCap: .round))
        let r = side * 0.078
        let head = at(p.head)
        context.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)), with: .color(body))

        limb([p.hip, p.kneeF, p.footF], active: working.legs, far: false)
        limb([p.shoulder, p.elbowF, p.handF], active: working.arms, far: false)
    }

    private func drawProp(_ context: inout GraphicsContext, pose p: FigurePose, at: (CGPoint) -> CGPoint, side: CGFloat) {
        let kit = Color.labelSecondary
        let thin = StrokeStyle(lineWidth: side * 0.03, lineCap: .round)
        func disc(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
        switch prop {
        case .none:
            break
        case .barbell:
            // Seen end-on from the side: a plate at the hands.
            context.stroke(disc(at(p.handF), side * 0.07), with: .color(kit), style: StrokeStyle(lineWidth: side * 0.03))
            context.fill(disc(at(p.handF), side * 0.02), with: .color(kit))
        case .dumbbells:
            context.fill(Path(roundedRect: CGRect(x: at(p.handF).x - side * 0.05, y: at(p.handF).y - side * 0.028,
                                                  width: side * 0.1, height: side * 0.056), cornerRadius: side * 0.02), with: .color(kit))
        case .bench:
            context.stroke(line([at(pt(0.16, 0.685)), at(pt(0.68, 0.685))]), with: .color(kit), style: StrokeStyle(lineWidth: side * 0.04, lineCap: .round))
            context.stroke(line([at(pt(0.24, 0.7)), at(pt(0.24, 0.93))]), with: .color(kit), style: thin)
            context.stroke(line([at(pt(0.6, 0.7)), at(pt(0.6, 0.93))]), with: .color(kit), style: thin)
            context.stroke(disc(at(p.handF), side * 0.07), with: .color(kit), style: StrokeStyle(lineWidth: side * 0.03))
        case .highBar:
            if p.handF.y > 0.1 && p.hip.y > 0.6 {
                // Pulldown: the bar travels with the hands on a cable.
                context.stroke(line([at(pt(p.handF.x, 0.0)), at(p.handF)]), with: .color(kit.opacity(0.6)), style: StrokeStyle(lineWidth: side * 0.014))
                context.stroke(line([at(pt(p.handF.x - 0.13, p.handF.y)), at(pt(p.handF.x + 0.13, p.handF.y))]), with: .color(kit), style: StrokeStyle(lineWidth: side * 0.035, lineCap: .round))
            } else {
                // A fixed bar to hang from.
                context.stroke(line([at(pt(0.3, 0.055)), at(pt(0.74, 0.055))]), with: .color(kit), style: StrokeStyle(lineWidth: side * 0.035, lineCap: .round))
            }
        case .step:
            // A chair behind for dips, a low box in front for step-ups.
            let chair = p.handF.y > 0.55 && p.footF.y > 0.85 && p.handF.x < 0.5
            let rect = chair
                ? CGRect(x: at(pt(0.26, 0.64)).x, y: at(pt(0.26, 0.64)).y, width: side * 0.2, height: side * 0.295)
                : CGRect(x: at(pt(0.54, 0.8)).x, y: at(pt(0.54, 0.8)).y, width: side * 0.24, height: side * 0.135)
            context.fill(Path(roundedRect: rect, cornerRadius: side * 0.02), with: .color(kit.opacity(0.45)))
        case .wheels:
            let ring = StrokeStyle(lineWidth: side * 0.025)
            context.stroke(disc(at(pt(0.26, 0.77)), side * 0.15), with: .color(kit), style: ring)
            context.stroke(disc(at(pt(0.78, 0.77)), side * 0.15), with: .color(kit), style: ring)
            context.stroke(line([at(pt(0.26, 0.77)), at(pt(0.4, 0.54)), at(pt(0.53, 0.8)), at(pt(0.26, 0.77))]), with: .color(kit), style: ring)
            context.stroke(line([at(pt(0.53, 0.8)), at(pt(0.74, 0.5)), at(pt(0.78, 0.77))]), with: .color(kit), style: ring)
        case .seat:
            context.stroke(line([at(pt(p.hip.x - 0.09, p.hip.y + 0.075)), at(pt(p.hip.x + 0.09, p.hip.y + 0.075))]),
                           with: .color(kit), style: StrokeStyle(lineWidth: side * 0.04, lineCap: .round))
            context.stroke(line([at(pt(0.12, 0.93)), at(pt(0.88, 0.93))]), with: .color(kit.opacity(0.5)), style: thin)
        }
    }
}

/// A single still frame: the start or the finish position, in 3D.
struct ExerciseFrame: View {
    let motion: ExerciseMotion
    /// `false` for the start position, `true` for the finish.
    let finish: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = ExerciseSnapshot.image(motion, finish: finish, dark: colorScheme == .dark) {
                Image(uiImage: image).resizable().interpolation(.high)
            } else {
                // Flat drawing if the 3D renderer is unavailable.
                ExerciseFigureCanvas(pose: finish ? motion.poses.1 : motion.poses.0, prop: motion.prop,
                                     working: motion.workingLimbs)
            }
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var period: Double { motion.isContinuous ? motion.period : max(motion.period, 2.6) }
    private var runTime: Double { period * Double(reps) }
    private var isPlaying: Bool { startedAt != nil }

    var body: some View {
        let (a, b) = motion.poses
        ZStack(alignment: .bottomTrailing) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
                let elapsed = startedAt.map { timeline.date.timeIntervalSince($0) } ?? runTime
                let done = elapsed >= runTime
                ExerciseFigure3DView(pose: done ? a : a.lerp(to: b, phase(elapsed)), motion: motion)
                    .onChange(of: done) { _, finished in if finished { startedAt = nil } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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

    /// 0 at the start position, 1 at the finish.
    private func phase(_ elapsed: Double) -> CGFloat {
        let t = (elapsed / period).truncatingRemainder(dividingBy: 1)
        if motion.isContinuous { return 0.5 - 0.5 * cos(2 * .pi * t) }
        // Hold start, move, hold finish, return.
        func ease(_ x: Double) -> Double { 0.5 - 0.5 * cos(.pi * min(max(x, 0), 1)) }
        switch t {
        case ..<0.12: return 0
        case ..<0.47: return ease((t - 0.12) / 0.35)
        case ..<0.65: return 1
        default:      return 1 - ease((t - 0.65) / 0.35)
        }
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
