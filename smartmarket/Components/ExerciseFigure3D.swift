import SwiftUI
import SceneKit

// MARK: - Exercise figure posing
//
// Poses the how-to figure in 3D: a 16-bone body of fixed proportions
// (`BodyRig`), its equipment, and a camera that frames the whole movement.
// Poses come from `ExerciseMotion` (a side-view start and finish, eased by
// `RepTempo`), a generated stride (`Gait`) or a captured clip (`MotionClip`);
// each bone keeps its real length and takes its direction from the source.
// Nothing here is rendered: `FigureScene.frame()` hands the posed joints and
// equipment to `LineFigureCanvas`, which draws them as a line drawing.

/// The muscle groups the figure can light up.
enum Muscle: CaseIterable {
    case chest, shoulders, traps, lats, lowerBack, abs, obliques
    case biceps, triceps, forearms, glutes, quads, hamstrings, calves
}

extension ExerciseMotion {
    /// The muscles this movement mainly works, shown in red on the figure.
    var muscles: Set<Muscle> {
        switch self {
        case .squat, .backSquat, .gobletSquat, .legPress, .stepUp, .lunge: return [.quads, .glutes]
        case .hinge:        return [.hamstrings, .glutes, .lowerBack]
        case .pushUp, .benchPress, .dumbbellBench: return [.chest, .triceps, .shoulders]
        case .pikePushUp, .press:  return [.shoulders, .triceps]
        case .plank:        return [.abs, .obliques]
        case .seatedRow:    return [.lats, .traps, .biceps]
        case .pulldown:     return [.lats, .biceps]
        case .bentRow, .barbellRow: return [.lats, .traps]
        case .bridge:       return [.glutes, .hamstrings]
        case .run:          return [.quads, .hamstrings, .calves]
        case .walk:         return [.quads, .calves, .glutes]
        case .stairs:       return [.quads, .glutes, .calves]
        case .lateralRaise, .armRaise: return [.shoulders]
        case .reverseFly:   return [.shoulders, .traps]
        case .singleLegDeadlift: return [.hamstrings, .glutes]
        case .sideLunge, .sideShuffle: return [.quads, .glutes]
        case .jumpingJack:  return [.calves, .shoulders, .quads]
        case .crunch:       return [.abs]
        case .highKnees:    return [.quads, .abs, .calves]
        case .march, .skip: return [.quads, .calves]
        case .frontKick:    return [.quads, .abs]
        case .windmill:     return [.obliques, .hamstrings]
        case .kneeLift:     return [.abs, .obliques]
        case .squatReach:   return [.quads, .glutes, .shoulders]
        case .hipCircle:    return [.glutes]
        case .boxing:       return [.shoulders, .abs]
        case .jumpSquat:    return [.quads, .glutes, .calves]
        case .farmerCarry:  return [.forearms, .traps]
        case .dumbbellSquat, .barbellLunge, .gobletSideLunge: return [.quads, .glutes]
        case .dumbbellSingleLegDeadlift: return [.hamstrings, .glutes]
        case .dumbbellPunch: return [.shoulders, .abs]
        case .raiseOverhead, .frontRaise: return [.shoulders]
        case .dumbbellSquatReach: return [.quads, .glutes, .shoulders]
        case .barbellCurl, .dumbbellCurl: return [.biceps, .forearms]
        case .uprightRow:   return [.shoulders, .traps]
        case .shrug:        return [.traps]
        case .deadlift:     return [.hamstrings, .glutes, .lowerBack]
        case .tricepsOverhead, .kickback: return [.triceps]
        case .dumbbellPress: return [.shoulders, .triceps]
        case .cycle:        return [.quads, .calves]
        case .jump, .jumpRope: return [.calves, .quads]
        case .burpee:       return [.quads, .chest, .shoulders, .abs]
        case .climber:      return [.abs, .quads, .shoulders]
        case .kneeRaise, .deadBug: return [.abs]
        case .fold:         return [.hamstrings]
        case .catCow:       return [.lowerBack, .abs]
        case .armCircle:    return [.shoulders]
        case .dip:          return [.triceps]
        case .superman:     return [.lowerBack, .glutes]
        case .rowing:       return [.lats, .traps, .quads]
        case .twist, .woodchop: return [.obliques]
        case .lungeReach:   return [.quads, .obliques]
        case .childsPose:   return [.lowerBack, .lats]
        }
    }

    /// How the hands are held: closed over a bar, closed around dumbbells at
    /// the sides, cupping one weight together at the chest, or open (relaxed
    /// in the air, flat when they are on the floor).
    enum Grip { case bar, neutral, cup, open }

    var grip: Grip {
        switch prop {
        case .barbell, .bench, .benchDumbbells, .highBar, .pulldown, .wheels, .cableSeat: return .bar
        case .dumbbells, .oneDumbbell, .rope: return .neutral
        case .goblet, .cableHandle: return .cup
        case .none, .step, .seat, .pedals: return .open
        }
    }

    /// Where the arms stay on a captured movement that carries a weight.
    enum ArmHold { case backRack, goblet, hang }

    var armHold: ArmHold? {
        switch self {
        case .backSquat, .barbellLunge: return .backRack
        case .gobletSquat, .gobletSideLunge: return .goblet
        case .lunge, .farmerCarry, .dumbbellSquat: return .hang
        default: return nil
        }
    }

    /// Back and pulling work is shown from behind, where those muscles are.
    var viewedFromBehind: Bool {
        let m = muscles
        if m.contains(.lats) || m.contains(.traps) || m.contains(.lowerBack) { return true }
        if m.contains(.hamstrings) && !m.contains(.quads) { return true }
        return m == [.triceps]
    }
}

// MARK: - Rig

/// The joints of the body the poses were made for, standing in a T-pose
/// (metres; x forward, y up, z to the figure's right). Measured once on an
/// adult male figure 1.74 m tall: top, mid and bottom of the spine, head, then
/// per side shoulder, elbow, wrist, hip, knee, ankle; then per side the middle
/// knuckle and a point off the palm.
enum BodyRig {
    static let joints: [SIMD3<Float>] = [
        SIMD3(-0.0117, 1.3505, 0), SIMD3(-0.0058, 1.1231, 0), SIMD3(0, 0.8957, 0), SIMD3(0.0355, 1.6182, 0),
        SIMD3(-0.0117, 1.3505, 0.2053), SIMD3(0.0059, 1.3509, 0.5158), SIMD3(0.0643, 1.3492, 0.792),
        SIMD3(0, 0.8957, 0.0957), SIMD3(0.0337, 0.4627, 0.1754), SIMD3(0.0411, 0.0705, 0.2242),
        SIMD3(-0.0117, 1.3505, -0.2053), SIMD3(0.0059, 1.3509, -0.5158), SIMD3(0.0643, 1.3492, -0.792),
        SIMD3(0, 0.8957, -0.0957), SIMD3(0.0337, 0.4627, -0.1754), SIMD3(0.0418, 0.0705, -0.2242),
        SIMD3(0.0697, 1.3489, 0.8713), SIMD3(0.0643, 1.2622, 0.792),
        SIMD3(0.0697, 1.3489, -0.8713), SIMD3(0.0643, 1.2622, -0.792),
    ]
}

@MainActor
final class FigureScene {

    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let prop: ExerciseMotion.Prop
    private let grip: ExerciseMotion.Grip
    private var propNodes: [String: SCNNode] = [:]

    /// Where a bone starts, which way it runs, and how long it is. The basis
    /// columns are across the body, along the bone, and toward the front.
    private struct Frame {
        var origin: SIMD3<Float>
        var basis: simd_float3x3
        var length: Float

        /// A bone that swings in the side-view plane (spine, legs, posed arms):
        /// "front" is the bone turned a quarter turn about the across-the-body axis.
        static func sagittal(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Frame {
            let delta = b - a
            let length = max(simd_length(delta), 0.0001)
            let down = delta / length
            var front = simd_cross(SIMD3<Float>(0, 0, 1), down)
            front = simd_length(front) > 0.001 ? simd_normalize(front) : SIMD3(1, 0, 0)
            return Frame(origin: a, basis: simd_float3x3(simd_cross(down, front), down, front), length: length)
        }

        /// A bone given the way it runs and the way its front faces (the hands).
        static func facing(_ origin: SIMD3<Float>, down: SIMD3<Float>, front: SIMD3<Float>) -> Frame {
            let down = simd_normalize(down)
            var front = front - down * simd_dot(front, down)
            front = simd_length(front) > 0.001 ? simd_normalize(front) : simd_normalize(simd_cross(SIMD3(0, 0, 1), down))
            return Frame(origin: origin, basis: simd_float3x3(simd_cross(down, front), down, front), length: 1)
        }

        /// A bone given the across axis to stay close to (the mesh's arms, which
        /// rest out to the sides, and the feet).
        static func aligned(_ a: SIMD3<Float>, _ b: SIMD3<Float>, across hint: SIMD3<Float>) -> Frame {
            let delta = b - a
            let length = max(simd_length(delta), 0.0001)
            let down = delta / length
            let across = simd_normalize(hint - down * simd_dot(hint, down))
            return Frame(origin: a, basis: simd_float3x3(across, down, simd_cross(across, down)), length: length)
        }
    }

    // Bones: pelvis, waist, chest, head, then per side upper arm, forearm, thigh, shin, foot; then the two hands.
    private var bones: [SCNNode] = []
    private var rest: [Frame] = []
    private let shoulderHalf: Float
    private let hipHalf: Float
    /// How far the mesh's ankle sits above its sole, beyond the pose model's.
    private let lift: Float
    /// How far outside the hip the knee and the ankle stand (the body's own stance).
    private let kneeOut: Float, footOut: Float

    /// Where every joint ended up in the last pose (also read by the overlap check in the tests).
    struct Joints {
        var top, mid, bottom, head: SIMD3<Float>
        /// Index 0 is the near side (+z), 1 the far side.
        var shoulder, elbow, hand, hip, knee, foot: [SIMD3<Float>]
    }
    /// The middle of the space the movement takes up; the camera looks here.
    private(set) var focus = SIMD3<Float>(0, 0.8, 0)
    /// Extra height for a body hanging from a bar, so its feet clear the floor.
    private var hangLift: Float = 0
    /// For a captured movement: the moment last shown and how the capture was scaled to this body.
    private var capturedTime: Double = 0, capturedScale: Float = 1
    private let clip: MotionClip?
    private let armHold: ExerciseMotion.ArmHold?
    /// How far through the movement the last pose was, and whether it was moving toward the finish.
    private var lastProgress: Float = 0, rising = true
    private(set) var joints = Joints(top: .zero, mid: .zero, bottom: .zero, head: .zero,
                                     shoulder: [.zero, .zero], elbow: [.zero, .zero], hand: [.zero, .zero],
                                     hip: [.zero, .zero], knee: [.zero, .zero], foot: [.zero, .zero])

    convenience init(motion: ExerciseMotion, dark: Bool) {
        self.init(prop: motion.prop, grip: motion.grip, muscles: motion.muscles, fromBehind: motion.viewedFromBehind,
                  clip: motion.clip, poses: motion.poses, armHold: motion.armHold, dark: dark)
    }

    /// A figure for a captured clip that no exercise uses yet (the review reel).
    convenience init(clip: MotionClip, dark: Bool) {
        self.init(prop: .none, grip: .open, muscles: [], fromBehind: false, clip: clip,
                  poses: (FigurePose(), FigurePose()), armHold: nil, dark: dark)
    }

    init(prop: ExerciseMotion.Prop, grip: ExerciseMotion.Grip, muscles: Set<Muscle>, fromBehind: Bool,
         clip: MotionClip?, poses: (FigurePose, FigurePose), armHold: ExerciseMotion.ArmHold?, dark: Bool) {
        self.armHold = armHold
        self.prop = prop
        self.grip = grip
        self.clip = clip
        let r = BodyRig.joints
        shoulderHalf = abs(r[4].z)
        hipHalf = abs(r[7].z)
        lift = max(0, r[9].y - 0.04)
        kneeOut = 0.8 * (abs(r[8].z) - abs(r[7].z))
        footOut = 0.8 * (abs(r[9].z) - abs(r[7].z))
        buildRig(r)

        // The equipment is kept as nodes so `propShapes()` can read where each piece sits.
        buildProps(SCNMaterial(), SCNMaterial())

        // Three-quarter view, slightly above, from the way the body actually faces
        // (captured movements face all sorts of ways): from the front, or from
        // behind when the working muscles are on the back of the body.
        let camera = SCNCamera()
        camera.fieldOfView = 36
        camera.zNear = 0.05          // so zooming right in never slices the body open
        camera.zFar = 40
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        // Frame the whole movement: find how much room both key positions
        // take (a hanging body is also lifted until its feet clear the floor),
        // then stand the camera back far enough to fit it.
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude), high = -low
        var facing = SIMD3<Float>(repeating: 0), upright: Float = 0, samples: Float = 0
        for pass in 0..<2 {
            low = SIMD3(repeating: .greatestFiniteMagnitude); high = -low
            facing = .zero; upright = 0; samples = 0
            // A captured movement is framed over the whole clip, a drawn one over its two positions.
            let moments: [() -> Void] = clip.map { clip in
                (0..<10).map { i in { self.apply(clip: clip, at: clip.duration * Double(i) / 10) } }
            } ?? [poses.0, poses.1].map { pose in { self.apply(pose) } }
            for moment in moments {
                moment()
                let j = joints
                for p in [j.top, j.bottom, j.head] + j.elbow + j.hand + j.knee + j.foot {
                    low = simd_min(low, p); high = simd_max(high, p)
                }
                // Which way the chest and hips face (index 0 is the figure's right), and how upright the trunk is.
                var right = (j.shoulder[0] - j.shoulder[1]) + (j.hip[0] - j.hip[1])
                right.y = 0
                if simd_length(right) > 0.01 { facing += simd_cross(SIMD3(0, 1, 0), simd_normalize(right)) }
                upright += abs(simd_normalize(j.top - j.bottom).y)
                samples += 1
            }
            if pass == 0, prop == .highBar, low.y < 0.16 { hangLift = 0.16 - low.y }
        }
        low -= SIMD3(0.16, 0.14, 0.14); high += SIMD3(0.16, 0.2, 0.14)        // flesh, head, feet, hands
        if prop == .barbell || prop == .bench { low.z = min(low.z, -0.78); high.z = max(high.z, 0.78); high.y += 0.1 }
        low.y = min(low.y, 0)
        let centre = (low + high) / 2
        let forward = simd_length(facing) > 0.01 ? simd_normalize(facing) : SIMD3<Float>(1, 0, 0)
        let right = simd_cross(forward, SIMD3(0, 1, 0))
        // Standing: well round to the front, so the two legs and arms stand apart.
        // Lying or on all fours: more from the side, so the body is not seen end-on.
        let lying = samples > 0 && upright / samples < 0.55
        let turn: Float = (lying ? 62 : 34) * .pi / 180, rise: Float = 13 * .pi / 180
        let around = (fromBehind ? -forward : forward) * cos(turn) + right * sin(turn)
        let direction = simd_normalize(around * cos(rise) + SIMD3(0, sin(rise), 0))
        let radius = simd_length(high - low) / 2
        let distance = max(radius / tan(18 * .pi / 180) * 0.92, 2.2)
        focus = centre
        cameraNode.simdPosition = centre + direction * distance
        cameraNode.look(at: SCNVector3(centre.x, centre.y, centre.z))
        if let clip { apply(clip: clip, at: 0) } else { apply(poses.0) }
    }

    // MARK: Rig

    /// One node per bone, at its rest frame. Nothing is drawn from them: each
    /// only carries its bone's transform (read by `feet`).
    private func buildRig(_ r: [SIMD3<Float>]) {
        bones = (0..<16).map { _ in
            let node = SCNNode()
            scene.rootNode.addChildNode(node)
            return node
        }
        // Rest frames, in bone order.
        let top = r[0], mid = r[1], bottom = r[2], head = r[3]
        var waist = Frame.sagittal(mid, bottom)
        rest = [waist, waist, .sagittal(top, mid), .sagittal(head, top)]
        waist.origin = bottom
        rest[0] = waist
        let forward = SIMD3<Float>(1, 0, 0)
        for side in 0..<2 {
            let j = 4 + side * 6
            let shoulder = r[j], elbow = r[j + 1], hand = r[j + 2], hip = r[j + 3], knee = r[j + 4], foot = r[j + 5]
            // The arms rest out to the sides with the biceps facing forward.
            let armDown = simd_normalize(elbow - shoulder)
            let upper = Frame.aligned(shoulder, elbow, across: simd_cross(armDown, forward))
            rest += [upper, .aligned(elbow, hand, across: upper.basis.columns.0),
                     .sagittal(hip, knee), .sagittal(knee, foot),
                     Frame(origin: foot, basis: simd_float3x3(SIMD3(0, 0, 1), SIMD3(0, -1, 0), forward), length: 1)]
        }
        for side in 0..<2 {
            let wrist = r[4 + side * 6 + 2], middle = r[16 + side * 2], palm = r[17 + side * 2]
            rest.append(.facing(wrist, down: middle - wrist, front: palm - wrist))
        }
    }

    // MARK: Props

    /// The equipment: `m` for frames, bars and pads, `heavy` for weights.
    private func buildProps(_ m: SCNMaterial, _ heavy: SCNMaterial) {
        m.lightingModel = .blinn
        m.specular.contents = UIColor(white: 0.35, alpha: 1)
        heavy.lightingModel = .blinn
        heavy.specular.contents = UIColor(white: 0.25, alpha: 1)
        @discardableResult
        func add(_ name: String, _ geometry: SCNGeometry, _ material: SCNMaterial? = nil) -> SCNNode {
            geometry.materials = [material ?? m]
            let node = SCNNode(geometry: geometry)
            scene.rootNode.addChildNode(node)
            propNodes[name] = node
            return node
        }
        func rod(_ radius: CGFloat, _ length: CGFloat) -> SCNCylinder {
            let c = SCNCylinder(radius: radius, height: length)
            c.radialSegmentCount = 32
            return c
        }
        /// A barbell: the bar, and on each end a collar and two plates.
        func addBarbell() {
            add("bar", rod(0.014, 1.56))
            for side in ["L", "R"] {
                add("collar" + side, rod(0.03, 0.03))
                add("plate" + side, rod(0.2, 0.035), heavy)
                add("plateSmall" + side, rod(0.15, 0.03), heavy)
            }
        }
        /// A dumbbell lying along its own y axis: a handle with a round head at each end.
        func addDumbbell(_ name: String) {
            let root = SCNNode()
            let handle = SCNNode(geometry: rod(0.013, 0.2))
            handle.geometry?.materials = [m]
            root.addChildNode(handle)
            for y in [Float(-0.078), 0.078] {
                let head = SCNNode(geometry: rod(0.05, 0.062))
                head.geometry?.materials = [heavy]
                head.simdPosition = SIMD3(0, y, 0)
                root.addChildNode(head)
                let cap = SCNNode(geometry: rod(0.042, 0.078))
                cap.geometry?.materials = [heavy]
                cap.simdPosition = SIMD3(0, y, 0)
                root.addChildNode(cap)
            }
            scene.rootNode.addChildNode(root)
            propNodes[name] = root
        }
        func addBench() {
            add("bench", SCNBox(width: 1.25, height: 0.08, length: 0.36, chamferRadius: 0.03))
            for i in 0..<2 { add("benchLeg\(i)", SCNBox(width: 0.06, height: 0.4, length: 0.32, chamferRadius: 0.01)) }
        }
        switch prop {
        case .none:
            break
        case .pedals:
            // Stairs that keep coming, like a stair machine: a run of steps moving down and back.
            for i in 0..<Self.stairCount { add("stair\(i)", SCNBox(width: 1, height: 1, length: 0.78, chamferRadius: 0)).isHidden = true }
        case .barbell:
            addBarbell()
        case .dumbbells:
            addDumbbell("db0"); addDumbbell("db1")
        case .oneDumbbell, .goblet:
            addDumbbell("db0")
        case .bench:
            addBench(); addBarbell()
        case .benchDumbbells:
            addBench(); addDumbbell("db0"); addDumbbell("db1")
        case .highBar:
            add("bar", rod(0.016, 1.0))
        case .pulldown:
            add("bar", rod(0.014, 1.1))
            add("cable", rod(0.005, 1))
            add("seat", SCNBox(width: 0.34, height: 0.06, length: 0.36, chamferRadius: 0.02))
            add("post", SCNBox(width: 0.07, height: 1, length: 0.07, chamferRadius: 0.01))
        case .rope:
            add("rope", Self.ropeArc())
        case .cableHandle:
            add("bar", rod(0.014, 0.16))
            add("cable", rod(0.005, 1))
        case .step:
            add("box", SCNBox(width: 0.5, height: 0.26, length: 0.6, chamferRadius: 0.03))
            // A chair for dips: a seat on four legs.
            add("chairSeat", SCNBox(width: 0.46, height: 0.05, length: 0.62, chamferRadius: 0.015))
            for i in 0..<4 { add("chairLeg\(i)", SCNBox(width: 0.04, height: 1, length: 0.04, chamferRadius: 0.008)) }
        case .wheels:
            for (i, x) in [Float(-0.48), 0.56].enumerated() {
                let wheel = add("wheel\(i)", SCNTorus(ringRadius: 0.3, pipeRadius: 0.022))
                wheel.position = SCNVector3(x, 0.3, 0)
                wheel.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            }
            add("frameA", rod(0.02, 1)); add("frameB", rod(0.02, 1)); add("frameC", rod(0.02, 1))
            add("bar", rod(0.014, 0.62))
        case .seat:
            add("seat", SCNBox(width: 0.34, height: 0.06, length: 0.4, chamferRadius: 0.02))
            add("rail", SCNBox(width: 1.7, height: 0.04, length: 0.1, chamferRadius: 0.01)).position = SCNVector3(0.2, 0.02, 0)
            add("plate", SCNBox(width: 0.04, height: 0.5, length: 0.62, chamferRadius: 0.01), heavy)
        case .cableSeat:
            add("seat", SCNBox(width: 0.34, height: 0.06, length: 0.4, chamferRadius: 0.02))
            add("rail", SCNBox(width: 1.7, height: 0.04, length: 0.1, chamferRadius: 0.01)).position = SCNVector3(0.2, 0.02, 0)
            add("bar", rod(0.014, 0.82))
            add("cable", rod(0.005, 1))
        }
    }

    // MARK: Posing

    private static let stairCount = 6

    private func stretch(_ node: SCNNode, from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let delta = b - a
        let length = max(simd_length(delta), 0.0001)
        node.simdPosition = (a + b) / 2
        node.simdScale = SIMD3(1, length, 1)
        let direction = delta / length
        // A cylinder's axis is +Y; turning it exactly upside down has no unique rotation.
        node.simdOrientation = direction.y < -0.9999
            ? simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0))
            : simd_quatf(from: SIMD3(0, 1, 0), to: direction)
    }

    /// Moves a bone so its rest frame lands on `pose`, stretched along its length if asked.
    private func place(_ bone: Int, at pose: Frame, stretch: Bool = true) {
        guard bone < bones.count else { return }
        let from = rest[bone]
        let scale = stretch ? pose.length / from.length : 1
        let turned = simd_float3x3(pose.basis.columns.0, pose.basis.columns.1 * scale, pose.basis.columns.2)
            * from.basis.transpose
        let offset = pose.origin - turned * from.origin
        bones[bone].simdTransform = simd_float4x4(SIMD4(turned.columns.0, 0), SIMD4(turned.columns.1, 0),
                                                  SIMD4(turned.columns.2, 0), SIMD4(offset, 1))
    }

    func apply(_ pose: FigurePose) { apply(from: pose, to: pose, progress: 0) }

    /// Poses the body part-way between two key positions.
    ///
    /// The key positions were drawn as stick figures whose limbs change
    /// length from one pose to the next, so they are not used as joint
    /// positions. Instead each bone keeps its real length and takes only its
    /// *direction* from the drawing, turning steadily from the start angle to
    /// the finish angle. The shoulders stay where the drawing puts them, the
    /// spine hangs from there, the legs reach for the drawn foot positions,
    /// and hands that rest on the floor pull the shoulders to the right height.
    ///
    /// `parts` gives each part of the body its own place in the movement (the
    /// working part leads, the rest follows: see `RepTempo`); without it every
    /// part is at `progress`.
    func apply(from a: FigurePose, to b: FigurePose, progress: CGFloat, parts: RepState? = nil) {
        let t = Float(min(max(progress, 0), 1))
        if t != lastProgress { rising = t > lastProgress; lastProgress = t }
        let state = parts ?? .all(progress)
        func part(_ value: CGFloat) -> Float { Float(min(max(value, -0.06), 1.06)) }
        let tLegs = part(state.legs), tSpine = part(state.spine), tHead = part(state.head)
        let tArmF = part(state.armNear), tArmB = part(state.armFar)
        let sw = shoulderHalf, hw = hipHalf

        func flat(_ p: CGPoint) -> SIMD2<Float> { SIMD2((Float(p.x) - 0.5) * 2, (0.92 - Float(p.y)) * 2 + lift) }
        func spine(_ p: FigurePose) -> CGPoint {
            p.spine ?? CGPoint(x: (p.shoulder.x + p.hip.x) / 2, y: (p.shoulder.y + p.hip.y) / 2)
        }
        /// A drawn point, moved in a straight line from start to finish.
        func target(_ t: Float, _ point: (FigurePose) -> CGPoint) -> SIMD2<Float> {
            simd_mix(flat(point(a)), flat(point(b)), SIMD2(repeating: t))
        }
        /// The direction of a drawn segment, turned by angle from start to finish
        /// (the way round that passes through the straight-line midpoint).
        func heading(_ t: Float, _ from: (FigurePose) -> CGPoint, _ to: (FigurePose) -> CGPoint, avoiding: SIMD2<Float>? = nil) -> SIMD2<Float> {
            let va = flat(to(a)) - flat(from(a)), vb = flat(to(b)) - flat(from(b))
            guard simd_length(va) > 0.001, simd_length(vb) > 0.001 else {
                let v = simd_length(va) > 0.001 ? va : vb
                return simd_length(v) > 0.001 ? simd_normalize(v) : SIMD2(0, -1)
            }
            func wrap(_ x: Float) -> Float { x - 2 * .pi * (x / (2 * .pi)).rounded() }
            let start = atan2(va.y, va.x)
            var turn = wrap(atan2(vb.y, vb.x) - start)
            if let avoiding {
                // A limb never swings through a direction it cannot reach (an
                // upper arm cannot point straight back): go the other way round.
                let blocked = wrap(atan2(avoiding.y, avoiding.x) - start)
                if (blocked > 0) == (turn > 0), abs(blocked) < abs(turn) { turn -= 2 * .pi * (turn > 0 ? 1 : -1) }
            } else {
                // A big swing goes the way round that passes through the straight-line midpoint.
                let middle = (va + vb) / 2
                if abs(turn) > 2.2, simd_length(middle) > 0.03 {
                    let viaMiddle = wrap(atan2(middle.y, middle.x) - start)
                    if (viaMiddle > 0) != (turn > 0) { turn -= 2 * .pi * (turn > 0 ? 1 : -1) }
                }
            }
            let angle = start + turn * t
            return SIMD2(cos(angle), sin(angle))
        }
        /// Two bones from `root` reaching for `goal`, bending toward the side the drawing bends.
        func reach(from root: SIMD2<Float>, to goal: SIMD2<Float>, _ first: Float, _ second: Float,
                   bend: Float) -> (joint: SIMD2<Float>, end: SIMD2<Float>) {
            let delta = goal - root
            let distance = min(max(simd_length(delta), abs(first - second) + 0.001), first + second - 0.0005)
            let toward = simd_length(delta) > 0.0001 ? simd_normalize(delta) : SIMD2<Float>(0, -1)
            let cosine = (first * first + distance * distance - second * second) / (2 * first * distance)
            let angle = acos(min(max(cosine, -1), 1)) * bend
            let direction = SIMD2(toward.x * cos(angle) - toward.y * sin(angle), toward.x * sin(angle) + toward.y * cos(angle))
            let joint = root + direction * first
            return (joint, joint + simd_normalize(root + toward * distance - joint) * second)
        }

        // Bone lengths of the body itself (or of the drawing, when there is no body).
        func length(_ bone: Int, _ fallback: Float) -> Float { bone < rest.count ? rest[bone].length : fallback }
        let waistLength = length(1, 0.29), chestLength = length(2, 0.29), neckLength = length(3, 0.24)
        let upperArm = length(4, 0.28), forearm = length(5, 0.26), thighLength = length(6, 0.34), shinLength = length(7, 0.36)

        // 1. Build the body around the hips, every bone at its real length in its drawn direction.
        let chestDir = heading(tSpine, { $0.shoulder }, spine), waistDir = heading(tSpine, spine, { $0.hip })
        let chestFront = SIMD2(-chestDir.y, chestDir.x)
        let upperF = heading(tArmF, { $0.shoulder }, { $0.elbowF }, avoiding: -chestFront), lowerF = heading(tArmF, { $0.elbowF }, { $0.handF })
        let upperB = heading(tArmB, { $0.shoulder }, { $0.elbowB }, avoiding: -chestFront), lowerB = heading(tArmB, { $0.elbowB }, { $0.handB })
        var bottom2 = SIMD2<Float>(0, 0)
        var mid2 = bottom2 - waistDir * waistLength
        var top2 = mid2 - chestDir * chestLength
        var head2 = top2 + heading(tHead, { $0.shoulder }, { $0.head }) * neckLength

        // Arms sit a little out from the body, and further out wherever the
        // side-view drawing would put them through it: an elbow drawn behind
        // the chest (the bottom of a bench press, a row, a push-up) or an
        // elbow or hand drawn inside the outline of the torso swings out to
        // the side instead. On a bar the hands keep one width throughout.
        func sideways(_ pose: FigurePose, _ elbow: CGPoint, _ hand: CGPoint) -> (elbow: Float, hand: Float) {
            func direction(_ from: CGPoint, _ to: CGPoint) -> SIMD2<Float>? {
                let v = flat(to) - flat(from)
                return simd_length(v) > 0.001 ? simd_normalize(v) : nil
            }
            guard let chest = direction(pose.shoulder, spine(pose)), let waist = direction(spine(pose), pose.hip),
                  let upper = direction(pose.shoulder, elbow) else { return (0, 0) }
            let lower = direction(elbow, hand) ?? upper
            // This pose's torso and arm at the body's real lengths, from the shoulder.
            let middle = chest * chestLength, hips = middle + waist * waistLength
            let elbowAt = upper * upperArm, handAt = elbowAt + lower * forearm
            func distance(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
                let ab = b - a
                let along = min(max(simd_dot(p - a, ab) / max(simd_length_squared(ab), 0.0001), 0), 1)
                return simd_length(p - (a + ab * along))
            }
            func inside(_ p: SIMD2<Float>) -> Float {
                return 1 - simd_smoothstep(0.05, 0.13, min(distance(p, SIMD2(0, 0), middle), distance(p, middle, hips)))
            }
            let front = SIMD2(-chest.y, chest.x)
            let behind = 0.15 * simd_smoothstep(0.1, 0.7, -simd_dot(upper, front))
            let elbowOut = max(behind, 0.04 * inside(elbowAt))
            return (elbowOut, max(elbowOut * 0.6, 0.1 * inside(handAt)))
        }
        func sideways(_ t: Float, _ elbow: (FigurePose) -> CGPoint, _ hand: (FigurePose) -> CGPoint) -> (elbow: Float, hand: Float) {
            let start = sideways(a, elbow(a), hand(a)), finish = sideways(b, elbow(b), hand(b))
            let elbowOut = start.elbow + (finish.elbow - start.elbow) * t
            switch grip {
            case .bar:  return (elbowOut + 0.05, max(start.hand, finish.hand) + 0.09)
            case .cup:  return (0.07, 0.062 - sw)                        // elbows tucked, both hands meet at the middle
            default:    return (elbowOut + 0.05, start.hand + (finish.hand - start.hand) * t + 0.09)
            }
        }
        let outF = sideways(tArmF, { $0.elbowF }, { $0.handF }), outB = sideways(tArmB, { $0.elbowB }, { $0.handB })
        func planar(_ length: Float, _ sideways: Float) -> Float { (max(length * length - sideways * sideways, 0.0004)).squareRoot() }
        var elbowF = top2 + upperF * planar(upperArm, outF.elbow), elbowB = top2 + upperB * planar(upperArm, outB.elbow)
        var handF = elbowF + lowerF * planar(forearm, outF.hand - outF.elbow)
        var handB = elbowB + lowerB * planar(forearm, outB.hand - outB.elbow)
        // Legs keep the body's own stance width, so the thighs never press through each other.
        let thigh = planar(thighLength, kneeOut), shin = planar(shinLength, footOut - kneeOut)
        let kneeF = heading(tLegs, { $0.hip }, { $0.kneeF }) * thigh, kneeB = heading(tLegs, { $0.hip }, { $0.kneeB }) * thigh
        let footF = kneeF + heading(tLegs, { $0.kneeF }, { $0.footF }) * shin
        let footB = kneeB + heading(tLegs, { $0.kneeB }, { $0.footB }) * shin

        // 2. Put it down where it is supported: on its feet when they are the
        // lowest part of the drawing, hanging from its hands under a high bar,
        // otherwise by the hips (seated, lying, on a saddle).
        let drawnHip = target(tLegs) { $0.hip }, drawnTop = target(tSpine) { $0.shoulder }
        let drawnHandF = target(tArmF) { $0.handF }, drawnHandB = target(tArmB) { $0.handB }
        let drawnFootF = target(tLegs) { $0.footF }, drawnFootB = target(tLegs) { $0.footB }
        let lowest = [drawnHip, drawnTop, drawnHandF, drawnHandB, drawnFootF, drawnFootB,
                      target(tLegs) { $0.kneeF }, target(tLegs) { $0.kneeB }, target(tHead) { $0.head }].map(\.y).min() ?? 0
        let handsHigh = simd_smoothstep(0.08, 0.2, min(drawnHandF.y, drawnHandB.y) - drawnTop.y)
        let hanging: Float = prop == .highBar ? handsHigh * simd_smoothstep(0.5, 0.7, drawnTop.y - lift) : 0
        let standsOnFeet: Float = prop == .wheels ? 0 : 1 - hanging
        // A knee on the floor (kneeling, the back leg of a lunge) carries the weight in place of its foot.
        let drawnKneeF = target(tLegs) { $0.kneeF }, drawnKneeB = target(tLegs) { $0.kneeB }
        let kneelingF = standsOnFeet * (1 - simd_smoothstep(0.05, 0.2, drawnKneeF.y - lowest))
        let kneelingB = standsOnFeet * (1 - simd_smoothstep(0.05, 0.2, drawnKneeB.y - lowest))
        var plantedF = standsOnFeet * (1 - simd_smoothstep(0.05, 0.2, drawnFootF.y - lowest))
        var plantedB = standsOnFeet * (1 - simd_smoothstep(0.05, 0.2, drawnFootB.y - lowest))
        // A stride knows which foot carries the weight; a foot swinging through
        // just above the floor must not drag the hips down.
        if let aF = a.supportF, let aB = a.supportB, let bF = b.supportF, let bB = b.supportB {
            plantedF = standsOnFeet * (Float(aF) + (Float(bF) - Float(aF)) * tLegs)
            plantedB = standsOnFeet * (Float(aB) + (Float(bB) - Float(aB)) * tLegs)
        }
        let footWeightF = plantedF * (1 - kneelingF), footWeightB = plantedB * (1 - kneelingB)
        let onFeet = max(max(plantedF, plantedB), max(kneelingF, kneelingB))
        let grounded = footWeightF + footWeightB + kneelingF + kneelingB
        var offset = drawnHip
        if grounded > 0.001 {
            let byLegs = ((drawnFootF - footF) * footWeightF + (drawnFootB - footB) * footWeightB
                          + (drawnKneeF - kneeF) * kneelingF + (drawnKneeB - kneeB) * kneelingB) / grounded
            offset = simd_mix(offset, byLegs, SIMD2(repeating: onFeet))
        }
        if hanging > 0.001 {
            let byHands = ((drawnHandF - handF) + (drawnHandB - handB)) / 2 + SIMD2(0, hangLift)
            offset = simd_mix(offset, byHands, SIMD2(repeating: hanging))
        }
        bottom2 += offset; mid2 += offset; top2 += offset; head2 += offset
        elbowF += offset; elbowB += offset; handF += offset; handB += offset

        // 3. A second support (hands or shoulders on the floor, hands on the
        // dip chair) sets the tilt: turn the whole body about the feet until it rests there.
        if grounded > 0.001 {
            let pivot = (drawnFootF * footWeightF + drawnFootB * footWeightB
                         + drawnKneeF * kneelingF + drawnKneeB * kneelingB) / grounded
            let onChair: Float = prop == .step && drawnHandF.x < drawnHip.x ? 1 : 0
            func rests(_ drawn: SIMD2<Float>) -> Float { max(1 - simd_smoothstep(0.1, 0.24, drawn.y - lift), onChair) }
            let supports: [(SIMD2<Float>, SIMD2<Float>, Float)] = [
                (handF, drawnHandF, rests(drawnHandF)), (handB, drawnHandB, rests(drawnHandB)),
                (top2, drawnTop, (1 - simd_smoothstep(0.1, 0.24, drawnTop.y - lift)) * 0.6),
            ]
            let weight = supports.reduce(Float(0)) { $0 + $1.2 }
            if weight > 0.001 {
                let at = supports.reduce(SIMD2<Float>(0, 0)) { $0 + $1.0 * $1.2 } / weight
                let wanted = supports.reduce(Float(0)) { $0 + $1.1.y * $1.2 } / weight
                let arm = at - pivot
                if abs(arm.x) > 0.15 {
                    let goal = min(max(wanted - pivot.y, -simd_length(arm)), simd_length(arm))
                    let turn = (asin(goal / simd_length(arm)) - atan2(arm.y, abs(arm.x))) * (arm.x > 0 ? 1 : -1)
                        * min(weight, 1) * onFeet
                    func turned(_ p: SIMD2<Float>) -> SIMD2<Float> {
                        let d = p - pivot
                        return pivot + SIMD2(d.x * cos(turn) - d.y * sin(turn), d.x * sin(turn) + d.y * cos(turn))
                    }
                    bottom2 = turned(bottom2); mid2 = turned(mid2); top2 = turned(top2); head2 = turned(head2)
                    elbowF = turned(elbowF); elbowB = turned(elbowB); handF = turned(handF); handB = turned(handB)
                }
            }
        }

        // 4. Legs: a planted foot stays exactly on its drawn spot; a free one keeps its drawn shape.
        // A planted knee stays on its spot and the shin lies as drawn behind it.
        func leg(knee: SIMD2<Float>, foot: SIMD2<Float>, drawnKnee: SIMD2<Float>, drawnFoot: SIMD2<Float>,
                 planted: Float, kneeling: Float) -> (joint: SIMD2<Float>, end: SIMD2<Float>) {
            let side = foot.x * knee.y - foot.y * knee.x
            let goal = simd_mix(bottom2 + foot, drawnFoot, SIMD2(repeating: planted))
            let standing = reach(from: bottom2, to: goal, thigh, shin, bend: side >= -0.004 ? 1 : -1)
            guard kneeling > 0.001 else { return standing }
            let toKnee = drawnKnee - bottom2
            let onKnee = bottom2 + (simd_length(toKnee) > 0.001 ? simd_normalize(toKnee) : SIMD2(0, -1)) * thigh
            let joint = simd_mix(standing.joint, onKnee, SIMD2(repeating: kneeling))
            let end = simd_mix(standing.end, onKnee + (foot - knee), SIMD2(repeating: kneeling))
            return (joint, end)
        }
        // On a bike the feet stay on the pedals, wherever the saddle puts the hips.
        let onPedals: Float = prop == .wheels ? 1 : 0
        let legF = leg(knee: kneeF, foot: footF, drawnKnee: drawnKneeF, drawnFoot: drawnFootF,
                       planted: max(plantedF, onPedals), kneeling: kneelingF)
        let legB = leg(knee: kneeB, foot: footB, drawnKnee: drawnKneeB, drawnFoot: drawnFootB,
                       planted: max(plantedB, onPedals), kneeling: kneelingB)

        // Breathing: the shoulders and head ride a few millimetres up the line of the chest.
        let breath = chestDir * (-0.005 * Float(state.breath))
        top2 += breath; head2 += breath

        func space(_ p: SIMD2<Float>, _ z: Float) -> SIMD3<Float> { SIMD3(p.x, p.y, z) }
        let top = space(top2, 0), mid = space(mid2, 0), bottom = space(bottom2, 0), headAt = space(head2, 0)

        // The near ("front") side is +z, toward the camera; the far side is -z.
        struct Side { let shoulder, elbow, hand, hip, knee, foot: SIMD3<Float> }
        let near = Side(shoulder: top + SIMD3(0, 0, sw), elbow: space(elbowF, sw + outF.elbow),
                        hand: space(handF, sw + outF.hand),
                        hip: bottom + SIMD3(0, 0, hw), knee: space(legF.joint, hw + kneeOut), foot: space(legF.end, hw + footOut))
        let far = Side(shoulder: top - SIMD3(0, 0, sw), elbow: space(elbowB, -sw - outB.elbow),
                       hand: space(handB, -sw - outB.hand),
                       hip: bottom - SIMD3(0, 0, hw), knee: space(legB.joint, -hw - kneeOut), foot: space(legB.end, -hw - footOut))
        joints = Joints(top: top, mid: mid, bottom: bottom, head: headAt,
                        shoulder: [near.shoulder, far.shoulder], elbow: [near.elbow, far.elbow], hand: [near.hand, far.hand],
                        hip: [near.hip, far.hip], knee: [near.knee, far.knee], foot: [near.foot, far.foot])

        var waist = Frame.sagittal(mid, bottom)
        place(1, at: waist)
        waist.origin = bottom
        place(0, at: waist, stretch: false)
        place(2, at: .sagittal(top, mid))
        place(3, at: .sagittal(headAt, top), stretch: false)
        var grips: [SIMD3<Float>] = [], knuckles: [SIMD3<Float>] = []
        for (i, side) in [near, far].enumerated() {
            let b = 4 + i * 5
            place(b, at: .sagittal(side.shoulder, side.elbow))
            let forearm = Frame.sagittal(side.elbow, side.hand)
            place(b + 1, at: forearm)

            // The hand: over a bar the palm faces away from the biceps side;
            // otherwise it faces the body, and turns palm-down as it nears the floor.
            let along = forearm.basis.columns.1, biceps = forearm.basis.columns.2
            let inward = SIMD3<Float>(0, 0, i == 0 ? -1 : 1)
            var hand: Frame
            switch grip {
            case .bar:
                hand = .facing(side.hand, down: along, front: -biceps)
            case .neutral, .cup:
                hand = .facing(side.hand, down: along, front: inward)
            case .open:
                let onFloor = 1 - simd_smoothstep(0.1, 0.24, side.hand.y - lift)
                var level = along + biceps
                level.y = 0
                level = simd_length(level) > 0.2 ? simd_normalize(level) : SIMD3(1, 0, 0)
                hand = .facing(side.hand, down: simd_mix(along, level, SIMD3(repeating: onFloor)),
                               front: simd_mix(inward, SIMD3(0, -1, 0), SIMD3(repeating: onFloor)))
            }
            place(14 + i, at: hand, stretch: false)
            // Where a held bar or handle sits: in the curl of the fingers.
            grips.append(side.hand + hand.basis.columns.1 * 0.085 + hand.basis.columns.2 * 0.028)
            knuckles.append(hand.basis.columns.0)
            place(b + 2, at: .sagittal(side.hip, side.knee))
            let shin = Frame.sagittal(side.knee, side.foot)
            place(b + 3, at: shin)
            // Under an upright shin the foot stays flat on the floor; under a
            // level one (plank, lying, seated) it follows the shin.
            let upright = simd_smoothstep(0.45, 0.7, -shin.basis.columns.1.y)
            var down = simd_normalize(simd_mix(shin.basis.columns.1, SIMD3(0, -1, 0), SIMD3(repeating: upright)))
            // On the leg press the soles lie flat on the plate, square to the line of the push.
            if prop == .seat { down = simd_normalize(SIMD3(side.foot.x - bottom.x, side.foot.y - bottom.y, 0)) }
            var foot = Frame.sagittal(side.foot, side.foot + down)
            foot.length = 1
            place(b + 4, at: foot, stretch: false)
        }

        poseProps(grips: grips, knuckles: knuckles, pose: t < 0.5 ? a : b)
    }

    /// The skipping rope: the long way round a circle from one hand to the
    /// other, leaving out the short stretch that would pass through the body.
    /// The circle lies flat (in x and z) and is centred `ropeReach` beyond the hands.
    private static let ropeRadius: Float = 0.52, ropeReach: Float = 0.43
    private static func ropeArc() -> SCNGeometry {
        let handAngle = Float.pi - asin(0.3 / ropeRadius)          // where each hand sits on the circle
        let steps = 64, sides = 8
        let pipe: Float = 0.006
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = []
        var indices: [UInt16] = []
        for i in 0...steps {
            let angle = -handAngle + 2 * handAngle * Float(i) / Float(steps)
            let out = SIMD3<Float>(cos(angle), 0, sin(angle))
            for k in 0..<sides {
                let around = 2 * Float.pi * Float(k) / Float(sides)
                let normal = out * cos(around) + SIMD3<Float>(0, 1, 0) * sin(around)
                vertices.append(SCNVector3(out * ropeRadius + normal * pipe))
                normals.append(SCNVector3(normal))
            }
            guard i < steps else { continue }
            for k in 0..<sides {
                let a = UInt16(i * sides + k), b = UInt16(i * sides + (k + 1) % sides)
                let c = a + UInt16(sides), d = b + UInt16(sides)
                indices += [a, b, c, b, d, c]
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    /// The long, thin pieces of equipment as they sit now (ends and thickness), for the overlap check in the tests.
    var rods: [(from: SIMD3<Float>, to: SIMD3<Float>, radius: Float)] {
        var found: [(from: SIMD3<Float>, to: SIMD3<Float>, radius: Float)] = []
        for (name, half, radius) in [("bar", Float(0.5), Float(0.016)), ("db0", 0.11, 0.05), ("db1", 0.11, 0.05)] {
            guard let node = propNodes[name], !node.isHidden else { continue }
            let axis = node.simdOrientation.act(SIMD3<Float>(0, 1, 0))
            found.append((node.simdPosition - axis * half, node.simdPosition + axis * half, radius))
        }
        return found
    }

    /// Places the equipment against the posed body. `grips` is where each
    /// hand holds (in the curl of the fingers) and `knuckles` the line across each fist.
    private func poseProps(grips: [SIMD3<Float>], knuckles: [SIMD3<Float>], pose: FigurePose) {
        let j = joints
        let hands = (grips[0] + grips[1]) / 2
        let hips = (j.hip[0] + j.hip[1]) / 2
        let across = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))     // lay a rod along z
        func lay(_ name: String, along axis: SIMD3<Float>, at centre: SIMD3<Float>) {
            guard let node = propNodes[name] else { return }
            let a = simd_normalize(axis)
            node.simdPosition = centre
            node.simdOrientation = a.y < -0.9999 ? simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0)) : simd_quatf(from: SIMD3(0, 1, 0), to: a)
        }
        func barbell(at centre: SIMD3<Float>) {
            propNodes["bar"]?.simdPosition = centre
            propNodes["bar"]?.simdOrientation = across
            for (side, sign) in [("L", Float(1)), ("R", -1)] {
                for (name, z) in [("collar", Float(0.6)), ("plate", 0.635), ("plateSmall", 0.67)] {
                    propNodes[name + side]?.simdPosition = centre + SIMD3(0, 0, z * sign)
                    propNodes[name + side]?.simdOrientation = across
                }
            }
        }
        /// The bench sits under the back, wherever the body's own proportions put it.
        func bench() {
            let surface = min(hips.y, j.top.y) - 0.135
            let centre = (hips.x + j.top.x) / 2 - 0.1
            propNodes["bench"]?.simdPosition = SIMD3(centre, surface - 0.04, 0)
            let height = max(surface - 0.08, 0.05)
            for (i, x) in [Float(-0.5), 0.5].enumerated() {
                propNodes["benchLeg\(i)"]?.simdPosition = SIMD3(centre + x, height / 2, 0)
                propNodes["benchLeg\(i)"]?.simdScale = SIMD3(1, height / 0.4, 1)
            }
        }
        switch prop {
        case .none:
            break
        case .pedals:
            // The captured climb gives the size of a step and where one sat under the planted
            // foot; the steps travel back and down at the pace the climber went up.
            guard let clip, clip.aux.count >= 4, clip.aux[0] > 0.05 else { break }
            let run = clip.aux[0] * capturedScale, rise = clip.aux[1] * capturedScale
            let stepTime = clip.duration / 2
            let travelled = Float((capturedTime / stepTime).truncatingRemainder(dividingBy: 1))
            let base = SIMD2<Float>(clip.aux[2] * capturedScale, clip.aux[3] * capturedScale) - SIMD2(run, rise) * travelled
            for i in 0..<Self.stairCount {
                guard let step = propNodes["stair\(i)"] else { continue }
                let n = Float(i - 2)
                let top = base.y + rise * n, x = base.x + run * n
                // Each step is a block from the floor up to its tread.
                step.isHidden = top < 0.02
                step.simdScale = SIMD3(run, max(top, 0.02), 1)
                step.simdPosition = SIMD3(x, max(top, 0.02) / 2, 0)
            }
        case .barbell:
            barbell(at: hands)
        case .bench:
            barbell(at: hands); bench()
        case .dumbbells:
            for i in 0..<2 { lay("db\(i)", along: knuckles[i], at: grips[i]) }
        case .oneDumbbell:
            lay("db0", along: knuckles[0], at: grips[0])
        case .benchDumbbells:
            for i in 0..<2 { lay("db\(i)", along: knuckles[i], at: grips[i]) }
            bench()
        case .goblet:
            // One dumbbell held upright in front of the chest, its top head between the palms.
            lay("db0", along: SIMD3(0, 1, 0), at: hands - SIMD3(0, 0.07, 0))
        case .highBar:
            // The bar sits in the hands, which do not move.
            propNodes["bar"]?.simdPosition = hands
            propNodes["bar"]?.simdOrientation = across
        case .pulldown:
            propNodes["bar"]?.simdPosition = hands
            propNodes["bar"]?.simdOrientation = across
            if let cable = propNodes["cable"] { stretch(cable, from: hands, to: SIMD3(hands.x, 2.6, 0)) }
            let seat = SIMD3<Float>(hips.x + 0.04, hips.y - 0.15, 0)
            propNodes["seat"]?.simdPosition = seat
            if let post = propNodes["post"] { stretch(post, from: SIMD3(seat.x, 0, 0), to: seat) }
        case .step:
            // A chair behind the hands for dips, a low box under the lead foot for step-ups.
            let chair = pose.handF.y > 0.55 && pose.footF.y > 0.85 && pose.handF.x < 0.5
            propNodes["box"]?.isHidden = chair
            propNodes["chairSeat"]?.isHidden = !chair
            for i in 0..<4 { propNodes["chairLeg\(i)"]?.isHidden = !chair }
            if chair {
                // The hands rest on the front edge of the seat.
                let top = min(j.hand[0].y, j.hand[1].y) - 0.035
                let middle = (j.hand[0].x + j.hand[1].x) / 2 - 0.17
                propNodes["chairSeat"]?.simdPosition = SIMD3(middle, top - 0.025, 0)
                for (i, corner) in [(Float(-0.19), Float(-0.27)), (-0.19, 0.27), (0.19, -0.27), (0.19, 0.27)].enumerated() {
                    propNodes["chairLeg\(i)"]?.simdPosition = SIMD3(middle + corner.0, (top - 0.05) / 2, corner.1)
                    propNodes["chairLeg\(i)"]?.simdScale = SIMD3(1, max(top - 0.05, 0.05), 1)
                }
            } else {
                propNodes["box"]?.simdPosition = SIMD3(0.3, 0.13, 0)
            }
        case .rope:
            // The rope is a loop through both hands that swings over the head
            // on the way down and under the feet at the top of the jump,
            // coming back round behind the body.
            let angle = Float.pi * lastProgress
            let swing = SIMD3<Float>(sin(angle) * (rising ? 1 : -1), cos(angle), 0)
            if let rope = propNodes["rope"] {
                // The arc's own x axis points along the swing and its z axis across the body.
                let centre = SIMD3(hands.x, hands.y, 0) + swing * Self.ropeReach
                rope.simdTransform = simd_float4x4(SIMD4(swing, 0), SIMD4(simd_cross(SIMD3(0, 0, 1), swing), 0),
                                                   SIMD4(0, 0, 1, 0), SIMD4(centre, 1))
            }
        case .cableHandle:
            // One handle held in both hands, on a cable from a high pulley behind.
            propNodes["bar"]?.simdPosition = hands
            propNodes["bar"]?.simdOrientation = across
            if let cable = propNodes["cable"] { stretch(cable, from: hands, to: SIMD3(-1.1, 2.3, 0)) }
        case .wheels:
            // The saddle sits under the hips and the bars in the hands; the wheels and crank stay put.
            let seat = SIMD3<Float>(hips.x - 0.03, hips.y - 0.14, 0), crank = SIMD3<Float>(0.06, 0.3, 0)
            if let a = propNodes["frameA"], let b = propNodes["frameB"], let c = propNodes["frameC"] {
                stretch(a, from: SIMD3(-0.48, 0.3, 0), to: seat)
                stretch(b, from: seat, to: crank)
                stretch(c, from: crank, to: SIMD3(hands.x, hands.y, 0))
            }
            propNodes["bar"]?.simdPosition = hands
            propNodes["bar"]?.simdOrientation = across
        case .seat:
            propNodes["seat"]?.simdPosition = hips - SIMD3(0, 0.15, 0)
            // The foot plate meets the soles, square to the line of the push.
            let ankles = (j.foot[0] + j.foot[1]) / 2
            let push = simd_normalize(SIMD3(ankles.x - hips.x, ankles.y - hips.y, 0))
            if let plate = propNodes["plate"] {
                plate.simdPosition = SIMD3(ankles.x, ankles.y, 0) + push * 0.1
                plate.simdOrientation = simd_quatf(from: SIMD3(1, 0, 0), to: push)
            }
        case .cableSeat:
            propNodes["seat"]?.simdPosition = hips - SIMD3(0, 0.15, 0)
            propNodes["bar"]?.simdPosition = hands
            propNodes["bar"]?.simdOrientation = across
            if let cable = propNodes["cable"] { stretch(cable, from: hands, to: SIMD3(1.5, hands.y - 0.02, 0)) }
        }
    }
}

// MARK: - Captured motion

extension FigureScene {
    /// Poses the body from captured joint positions (`MotionClip`). Every bone
    /// keeps the body's own length and takes its direction from the capture,
    /// in three dimensions; the lowest foot is held at the height the captured
    /// one had, so feet neither sink into the floor nor float.
    func apply(clip: MotionClip, at time: Double) {
        capturedTime = time
        if prop == .rope, let hops = clip.aux.first, hops >= 1 {
            // The rope goes round once per hop: under the feet at the top, overhead at the bottom.
            let phase = (time / clip.duration * Double(hops)).truncatingRemainder(dividingBy: 1)
            lastProgress = Float(0.5 + 0.5 * cos(2 * .pi * phase))
            rising = phase > 0.5
        }
        apply(captured: clip.joints(at: time), clip: clip)
    }

    private func apply(captured j: [SIMD3<Float>], clip: MotionClip) {
        guard j.count >= 20 else { return }
        typealias J = MotionClip.Joint
        let up = SIMD3<Float>(0, 1, 0)
        func direction(_ a: J, _ b: J, _ fallback: SIMD3<Float>) -> SIMD3<Float> {
            let v = j[b.rawValue] - j[a.rawValue], l = simd_length(v)
            return l > 0.0001 ? v / l : fallback
        }
        func unit(_ v: SIMD3<Float>, _ fallback: SIMD3<Float>) -> SIMD3<Float> {
            let l = simd_length(v)
            return l > 0.0001 ? v / l : fallback
        }
        func length(_ bone: Int, _ fallback: Float) -> Float { bone < rest.count ? rest[bone].length : fallback }
        let waistLength = length(1, 0.29), chestLength = length(2, 0.29), neckLength = length(3, 0.24)
        let upperArm = length(4, 0.28), forearm = length(5, 0.26), thighLength = length(6, 0.34), shinLength = length(7, 0.36)
        let scale = (thighLength + shinLength) / max(clip.leg, 0.3)

        // Spine, from the pelvis up.
        var bottom = SIMD3<Float>(j[J.pelvis.rawValue].x * scale, 0, j[J.pelvis.rawValue].z * scale)
        var mid = bottom + direction(.pelvis, .mid, up) * waistLength
        var top = mid + direction(.mid, .top, up) * chestLength
        // The neck follows the capture but stays within 25° of the line of the trunk:
        // some captures put the head marker well behind the shoulders, which would
        // throw the head back (and in a back squat, behind the bar).
        let trunkUp = unit(top - mid, up)
        var neckDir = direction(.top, .head, up)
        let lean = simd_dot(neckDir, trunkUp), most = cos(Float(25) * .pi / 180)
        if lean < most {
            let away = unit(neckDir - trunkUp * lean, SIMD3(1, 0, 0))
            neckDir = trunkUp * most + away * (1 - most * most).squareRoot()
        }
        var headAt = top + neckDir * neckLength

        // Shoulders and hips sit on the captured lines across the chest and the pelvis.
        // Index 0 is the near side (+z), which is the figure's right.
        let shoulderAxis = unit(j[J.rShoulder.rawValue] - j[J.lShoulder.rawValue], SIMD3(0, 0, 1))
        let hipAxis = unit(j[J.rHip.rawValue] - j[J.lHip.rawValue], SIMD3(0, 0, 1))
        let sides: [(shoulder: J, elbow: J, wrist: J, hip: J, knee: J, ankle: J, sole: J, sign: Float)] = [
            (.rShoulder, .rElbow, .rWrist, .rHip, .rKnee, .rAnkle, .rSole, 1),
            (.lShoulder, .lElbow, .lWrist, .lHip, .lKnee, .lAnkle, .lSole, -1),
        ]
        var shoulder = [SIMD3<Float>](repeating: .zero, count: 2), elbow = shoulder, hand = shoulder
        var hip = shoulder, knee = shoulder, foot = shoulder, sole = shoulder
        for (i, side) in sides.enumerated() {
            shoulder[i] = top + shoulderAxis * (shoulderHalf * side.sign)
            elbow[i] = shoulder[i] + direction(side.shoulder, side.elbow, -up) * upperArm
            hand[i] = elbow[i] + direction(side.elbow, side.wrist, -up) * forearm
            hip[i] = bottom + hipAxis * (hipHalf * side.sign)
            knee[i] = hip[i] + direction(side.hip, side.knee, -up) * thighLength
            foot[i] = knee[i] + direction(side.knee, side.ankle, -up) * shinLength
            sole[i] = direction(side.ankle, side.sole, SIMD3(1, 0, 0))
        }

        // A loaded squat: the arms stay on the weight, wherever the captured arms went.
        let chestUp = unit(top - mid, up), chestForward = unit(simd_cross(shoulderAxis, -chestUp), SIMD3(1, 0, 0))
        func reach(_ i: Int, to target: SIMD3<Float>, pole: SIMD3<Float>) {
            let delta = target - shoulder[i]
            let distance = min(max(simd_length(delta), abs(upperArm - forearm) + 0.001), upperArm + forearm - 0.0005)
            let along = unit(delta, -up)
            let cosine = (upperArm * upperArm + distance * distance - forearm * forearm) / (2 * upperArm * distance)
            let side = unit(pole - along * simd_dot(pole, along), -up)
            elbow[i] = shoulder[i] + along * (upperArm * cosine) + side * (upperArm * (max(1 - cosine * cosine, 0)).squareRoot())
            hand[i] = shoulder[i] + along * distance
        }
        switch armHold {
        case .backRack:
            // The bar across the upper back, hands just outside the shoulders, elbows down and back.
            for (i, sign) in [Float(1), -1].enumerated() {
                reach(i, to: top + shoulderAxis * (sign * (shoulderHalf + 0.13)) + chestUp * 0.015 - chestForward * 0.075,
                      pole: -chestUp - chestForward * 0.45)
            }
        case .goblet:
            // One weight held at the chest, elbows tucked under it. (`ArmHold.goblet`)
            for (i, sign) in [Float(1), -1].enumerated() {
                reach(i, to: top + shoulderAxis * (sign * 0.062) - chestUp * 0.09 + chestForward * 0.21,
                      pole: -chestUp + shoulderAxis * (sign * 0.35))
            }
        case .hang:
            // Weights hang at the sides, whatever the captured arms did.
            for (i, sign) in [Float(1), -1].enumerated() {
                reach(i, to: shoulder[i] + shoulderAxis * (sign * 0.07) - up * (upperArm + forearm - 0.02) + chestForward * 0.02,
                      pole: -chestForward)
            }
        case nil:
            break
        }

        // This body is broader than most captured ones: an arm that would pass
        // through the trunk is moved out to its surface, elbow first, then the hand.
        func clear(_ p: SIMD3<Float>, radius: Float) -> SIMD3<Float> {
            var out = p
            for (a, b, r) in [(bottom, mid, radius), (mid, top, radius + 0.015)] {
                let ab = b - a
                let along = min(max(simd_dot(out - a, ab) / max(simd_length_squared(ab), 0.0001), 0), 1)
                let nearest = a + ab * along
                var away = out - nearest
                // The trunk is deeper than a tube: flatten front-to-back before measuring.
                let depth = simd_dot(away, chestForward)
                away -= chestForward * (depth * 0.2)
                let distance = simd_length(away)
                if distance < r, distance > 0.0001 { out += away / distance * (r - distance) }
            }
            return out
        }
        if armHold == nil {
            for i in 0..<2 {
                let lower = unit(hand[i] - elbow[i], -up)
                elbow[i] = clear(elbow[i], radius: 0.2)
                hand[i] = clear(elbow[i] + lower * forearm, radius: 0.215)
            }
        }

        // Height: the lower ankle goes where the captured one was, scaled to this body.
        // Lying down, the lowest part of the body rests on the floor instead.
        let captured = min(j[J.lAnkle.rawValue].y, j[J.rAnkle.rawValue].y)
        let wanted = (captured - clip.ankleRest) * scale + 0.04 + lift
        var raise = SIMD3<Float>(0, wanted - min(foot[0].y, foot[1].y), 0)
        if clip.lying {
            let lowest = [bottom.y - 0.12, mid.y - 0.12, top.y - 0.11, headAt.y - 0.1,
                          foot[0].y - 0.04 - lift, foot[1].y - 0.04 - lift, hand[0].y - 0.03, hand[1].y - 0.03].min() ?? 0
            raise = SIMD3(0, -lowest, 0)
        }
        bottom += raise; mid += raise; top += raise; headAt += raise
        for i in 0..<2 {
            shoulder[i] += raise; elbow[i] += raise; hand[i] += raise
            hip[i] += raise; knee[i] += raise; foot[i] += raise
        }
        joints = Joints(top: top, mid: mid, bottom: bottom, head: headAt, shoulder: shoulder, elbow: elbow, hand: hand,
                        hip: hip, knee: knee, foot: foot)

        /// A bone from `a` to `b` whose across-the-body axis stays close to `across`.
        func oriented(_ a: SIMD3<Float>, _ b: SIMD3<Float>, across: SIMD3<Float>) -> Frame {
            let delta = b - a
            let length = max(simd_length(delta), 0.0001)
            let down = delta / length
            var front = simd_cross(across, down)
            front = simd_length(front) > 0.001 ? simd_normalize(front) : unit(simd_cross(SIMD3(0, 0, 1), down), SIMD3(1, 0, 0))
            return Frame(origin: a, basis: simd_float3x3(simd_cross(down, front), down, front), length: length)
        }
        /// The axis a two-bone limb bends about, falling back to `rest` as the limb straightens.
        func hinge(_ first: SIMD3<Float>, _ second: SIMD3<Float>, rest: SIMD3<Float>) -> SIMD3<Float> {
            let axis = simd_cross(first, second)
            let bend = simd_smoothstep(0.1, 0.4, simd_length(axis))
            return unit(unit(axis, rest) * bend + rest * (1 - bend), rest)
        }

        var waist = oriented(mid, bottom, across: unit(hipAxis + shoulderAxis, hipAxis))
        place(1, at: waist)
        waist = oriented(mid, bottom, across: hipAxis)
        waist.origin = bottom
        place(0, at: waist, stretch: false)
        let chest = oriented(top, mid, across: shoulderAxis)
        place(2, at: chest)
        place(3, at: oriented(headAt, top, across: shoulderAxis), stretch: false)
        let chestFront = chest.basis.columns.2

        var grips: [SIMD3<Float>] = [], knuckles: [SIMD3<Float>] = []
        for i in 0..<2 {
            let b = 4 + i * 5
            // Arms: the elbow bends about its own hinge; a straight arm keeps its palm toward the body.
            let upper = unit(elbow[i] - shoulder[i], -up), lower = unit(hand[i] - elbow[i], -up)
            let armAcross = hinge(upper, lower, rest: unit(simd_cross(upper, chestFront), shoulderAxis))
            place(b, at: oriented(shoulder[i], elbow[i], across: armAcross))
            let forearmFrame = oriented(elbow[i], hand[i], across: armAcross)
            place(b + 1, at: forearmFrame)

            let along = forearmFrame.basis.columns.1, biceps = forearmFrame.basis.columns.2
            let inward = shoulderAxis * (i == 0 ? -1 : 1)
            var handFrame: Frame
            switch grip {
            case .bar:
                handFrame = .facing(hand[i], down: along, front: -biceps)
            case .neutral, .cup:
                handFrame = .facing(hand[i], down: along, front: inward)
            case .open:
                let onFloor = 1 - simd_smoothstep(0.1, 0.24, hand[i].y - lift)
                var level = along + biceps
                level.y = 0
                level = simd_length(level) > 0.2 ? simd_normalize(level) : SIMD3(1, 0, 0)
                handFrame = .facing(hand[i], down: simd_mix(along, level, SIMD3(repeating: onFloor)),
                                    front: simd_mix(inward, SIMD3(0, -1, 0), SIMD3(repeating: onFloor)))
            }
            place(14 + i, at: handFrame, stretch: false)
            grips.append(hand[i] + handFrame.basis.columns.1 * 0.085 + handFrame.basis.columns.2 * 0.028)
            knuckles.append(handFrame.basis.columns.0)

            // Legs: the knee bends the other way round.
            let thigh = unit(knee[i] - hip[i], -up), shin = unit(foot[i] - knee[i], -up)
            let legAcross = hinge(shin, thigh, rest: hipAxis)
            place(b + 2, at: oriented(hip[i], knee[i], across: legAcross))
            place(b + 3, at: oriented(knee[i], foot[i], across: legAcross))
            // The foot points where the captured sole pointed.
            let down = unit(simd_cross(sole[i], legAcross), -up)
            var footFrame = oriented(foot[i], foot[i] + down, across: legAcross)
            footFrame.length = 1
            place(b + 4, at: footFrame, stretch: false)
        }
        capturedScale = scale
        poseProps(grips: grips, knuckles: knuckles, pose: FigurePose())
    }
}

// MARK: - Drawing data

extension FigureScene {
    /// Heel and toe of each foot (index 0 the near side), as the foot bones sit now.
    var feet: [(heel: SIMD3<Float>, toe: SIMD3<Float>)] {
        (0..<2).map { i in
            let b = 8 + i * 5, ankle = joints.foot[i]
            guard b < bones.count, b < rest.count else {
                return (ankle + SIMD3(-0.055, -0.035, 0), ankle + SIMD3(0.16, -0.035, 0))
            }
            let frame = rest[b], m = bones[b].simdTransform
            func posed(_ p: SIMD3<Float>) -> SIMD3<Float> { let v = m * SIMD4(p, 1); return SIMD3(v.x, v.y, v.z) }
            let forward = frame.basis.columns.2, down = frame.basis.columns.1
            return (posed(frame.origin - forward * 0.055 + down * 0.035), posed(frame.origin + forward * 0.16 + down * 0.035))
        }
    }

    /// A piece of equipment as simple shapes, in world space.
    enum PropShape {
        /// A bar, handle, cable or frame tube.
        case rod(SIMD3<Float>, SIMD3<Float>, radius: Float)
        /// A plate or dumbbell head: a short cylinder.
        case disc(centre: SIMD3<Float>, axis: SIMD3<Float>, radius: Float, thickness: Float)
        /// A bench, seat, box or step: its eight corners.
        case box([SIMD3<Float>])
        /// A wheel: points round its rim, and the tube's radius.
        case ring([SIMD3<Float>], radius: Float)
        /// A skipping rope: points along it.
        case line([SIMD3<Float>])
    }

    /// Every visible piece of equipment, as it sits after the last pose.
    func propShapes() -> [PropShape] {
        var shapes: [PropShape] = []
        func visit(_ node: SCNNode, name: String) {
            guard !node.isHidden else { return }
            let m = node.simdWorldTransform
            func at(_ p: SIMD3<Float>) -> SIMD3<Float> { let v = m * SIMD4(p, 1); return SIMD3(v.x, v.y, v.z) }
            func along(_ p: SIMD3<Float>) -> SIMD3<Float> { let v = m * SIMD4(p, 0); return SIMD3(v.x, v.y, v.z) }
            if name == "rope" {
                let reach = Float.pi - asin(0.3 / Self.ropeRadius)
                shapes.append(.line((0...40).map { i in
                    let angle = -reach + 2 * reach * Float(i) / 40
                    return at(SIMD3(cos(angle), 0, sin(angle)) * Self.ropeRadius)
                }))
            } else if let c = node.geometry as? SCNCylinder {
                let half = along(SIMD3(0, Float(c.height) / 2, 0)), centre = at(.zero), radius = Float(c.radius)
                let length = simd_length(half) * 2
                if length < radius * 3 {
                    shapes.append(.disc(centre: centre, axis: half / max(length / 2, 0.00001), radius: radius, thickness: length))
                } else {
                    shapes.append(.rod(centre - half, centre + half, radius: radius))
                }
            } else if let b = node.geometry as? SCNBox {
                let w = Float(b.width) / 2, h = Float(b.height) / 2, l = Float(b.length) / 2
                let signs: [Float] = [-1, 1]
                shapes.append(.box(signs.flatMap { x in signs.flatMap { y in signs.map { z in at(SIMD3(x * w, y * h, z * l)) } } }))
            } else if let t = node.geometry as? SCNTorus {
                shapes.append(.ring((0..<40).map { i in
                    let angle = 2 * Float.pi * Float(i) / 40
                    return at(SIMD3(cos(angle), 0, sin(angle)) * Float(t.ringRadius))
                }, radius: Float(t.pipeRadius)))
            }
            for child in node.childNodes { visit(child, name: "") }
        }
        for (name, node) in propNodes.sorted(by: { $0.key < $1.key }) { visit(node, name: name) }
        return shapes
    }

    /// Everything the line drawing needs for the current pose.
    func frame() -> FigureFrame {
        FigureFrame(joints: joints, feet: feet, props: propShapes(), camera: cameraNode.simdPosition, focus: focus)
    }
}
