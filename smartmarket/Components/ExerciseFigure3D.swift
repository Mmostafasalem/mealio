import SwiftUI
import SceneKit

// MARK: - 3D exercise figure
//
// The how-to figure as a small jointed mannequin in SceneKit. The flat side
// view hid one arm and one leg behind the other; here both sides are modelled
// and the camera sits at a three-quarter angle, so a press shows two arms and
// a lunge shows which leg is forward. Poses still come from `ExerciseMotion`
// (a side-view start and finish); each joint is placed in depth by which side
// of the body it belongs to. The large demo can be dragged to look around.

@MainActor
final class FigureScene {

    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let prop: ExerciseMotion.Prop
    private var joints: [SCNNode] = []
    private var bones: [SCNNode] = []
    private var propNodes: [String: SCNNode] = [:]
    private let head = SCNNode()

    // Half-widths of the body, in scene units (the figure is about 1.7 tall).
    private static let shoulderHalf: Float = 0.2
    private static let hipHalf: Float = 0.11

    init(prop: ExerciseMotion.Prop, working: (arms: Bool, legs: Bool), dark: Bool) {
        self.prop = prop
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let body = UIColor(Color.labelPrimary).resolvedColor(with: traits)
        let accent = UIColor(Color.progress).resolvedColor(with: traits)
        let kit = UIColor(Color.labelSecondary).resolvedColor(with: traits)
        let ground = UIColor(Color.labelTertiary).resolvedColor(with: traits).withAlphaComponent(0.14)

        func material(_ colour: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = colour
            m.lightingModel = .lambert
            return m
        }
        let bodyMaterial = material(body), armMaterial = material(working.arms ? accent : body)
        let legMaterial = material(working.legs ? accent : body), kitMaterial = material(kit)

        func bone(radius: CGFloat, _ m: SCNMaterial) -> SCNNode {
            let geometry = SCNCylinder(radius: radius, height: 1)
            geometry.radialSegmentCount = 16
            geometry.materials = [m]
            let node = SCNNode(geometry: geometry)
            scene.rootNode.addChildNode(node)
            bones.append(node)
            return node
        }
        func joint(radius: CGFloat, _ m: SCNMaterial) -> SCNNode {
            let geometry = SCNSphere(radius: radius)
            geometry.segmentCount = 16
            geometry.materials = [m]
            let node = SCNNode(geometry: geometry)
            scene.rootNode.addChildNode(node)
            joints.append(node)
            return node
        }
        // Order matters: `apply` fills these in the same order.
        // Bones: spine upper, spine lower, shoulders, hips, then per side: upper arm, forearm, thigh, shin.
        _ = bone(radius: 0.115, bodyMaterial); _ = bone(radius: 0.115, bodyMaterial)
        _ = bone(radius: 0.075, bodyMaterial); _ = bone(radius: 0.085, bodyMaterial)
        for _ in 0..<2 {
            _ = bone(radius: 0.052, armMaterial); _ = bone(radius: 0.046, armMaterial)
            _ = bone(radius: 0.068, legMaterial); _ = bone(radius: 0.056, legMaterial)
        }
        // Joints: spine top, mid, bottom, then per side: shoulder, elbow, hand, hip, knee, foot.
        _ = joint(radius: 0.115, bodyMaterial); _ = joint(radius: 0.115, bodyMaterial); _ = joint(radius: 0.115, bodyMaterial)
        for _ in 0..<2 {
            _ = joint(radius: 0.075, armMaterial); _ = joint(radius: 0.052, armMaterial); _ = joint(radius: 0.06, armMaterial)
            _ = joint(radius: 0.085, legMaterial); _ = joint(radius: 0.068, legMaterial); _ = joint(radius: 0.075, legMaterial)
        }
        let skull = SCNSphere(radius: 0.14)
        skull.materials = [bodyMaterial]
        head.geometry = skull
        scene.rootNode.addChildNode(head)

        // Ground: a soft disc so the figure has something to stand on.
        let disc = SCNCylinder(radius: 1.1, height: 0.012)
        disc.radialSegmentCount = 48
        disc.materials = [material(ground)]
        let floor = SCNNode(geometry: disc)
        floor.position = SCNVector3(0, -0.006, 0)
        scene.rootNode.addChildNode(floor)

        buildProps(kitMaterial)

        // Soft, even light: readable shapes without hard shadows.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 620
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 620
        key.eulerAngles = SCNVector3(-0.9, 0.7, 0)
        scene.rootNode.addChildNode(key)

        // Three-quarter view from the front-right, slightly above.
        let camera = SCNCamera()
        camera.fieldOfView = 36
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(1.85, 1.4, 2.7)
        cameraNode.look(at: SCNVector3(0, 0.8, 0))
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: Props

    private func buildProps(_ m: SCNMaterial) {
        func add(_ name: String, _ geometry: SCNGeometry) -> SCNNode {
            geometry.materials = [m]
            let node = SCNNode(geometry: geometry)
            scene.rootNode.addChildNode(node)
            propNodes[name] = node
            return node
        }
        switch prop {
        case .none:
            break
        case .barbell:
            _ = add("bar", SCNCylinder(radius: 0.022, height: 1.3))
            _ = add("plateL", SCNCylinder(radius: 0.17, height: 0.05))
            _ = add("plateR", SCNCylinder(radius: 0.17, height: 0.05))
        case .dumbbells:
            _ = add("dbL", SCNCapsule(capRadius: 0.05, height: 0.26))
            _ = add("dbR", SCNCapsule(capRadius: 0.05, height: 0.26))
        case .bench:
            let top = add("bench", SCNBox(width: 1.1, height: 0.08, length: 0.42, chamferRadius: 0.03))
            top.position = SCNVector3(-0.14, 0.44, 0)
            for (i, x) in [Float(-0.58), 0.3].enumerated() {
                let leg = add("benchLeg\(i)", SCNBox(width: 0.06, height: 0.4, length: 0.36, chamferRadius: 0.01))
                leg.position = SCNVector3(x, 0.2, 0)
            }
            _ = add("bar", SCNCylinder(radius: 0.022, height: 1.3))
            _ = add("plateL", SCNCylinder(radius: 0.17, height: 0.05))
            _ = add("plateR", SCNCylinder(radius: 0.17, height: 0.05))
        case .highBar:
            _ = add("bar", SCNCylinder(radius: 0.022, height: 1.0))
        case .step:
            _ = add("box", SCNBox(width: 0.5, height: 0.26, length: 0.6, chamferRadius: 0.03))
        case .wheels:
            for (i, x) in [Float(-0.48), 0.56].enumerated() {
                let wheel = add("wheel\(i)", SCNTorus(ringRadius: 0.3, pipeRadius: 0.022))
                wheel.position = SCNVector3(x, 0.3, 0)
                wheel.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            }
            _ = add("frameA", SCNCylinder(radius: 0.02, height: 1))
            _ = add("frameB", SCNCylinder(radius: 0.02, height: 1))
            _ = add("frameC", SCNCylinder(radius: 0.02, height: 1))
        case .seat:
            _ = add("seat", SCNBox(width: 0.32, height: 0.06, length: 0.34, chamferRadius: 0.02))
            let rail = add("rail", SCNBox(width: 1.6, height: 0.04, length: 0.1, chamferRadius: 0.01))
            rail.position = SCNVector3(0, 0.02, 0)
        }
    }

    // MARK: Posing

    /// Side-view unit coordinates → scene: x runs forward, y up, z across the body.
    private func world(_ p: CGPoint, z: Float) -> SIMD3<Float> {
        SIMD3((Float(p.x) - 0.5) * 2, (0.92 - Float(p.y)) * 2, z)
    }

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

    func apply(_ pose: FigurePose) {
        let sw = Self.shoulderHalf, hw = Self.hipHalf
        let top = world(pose.shoulder, z: 0), bottom = world(pose.hip, z: 0)
        let midPoint = pose.spine ?? CGPoint(x: (pose.shoulder.x + pose.hip.x) / 2, y: (pose.shoulder.y + pose.hip.y) / 2)
        let mid = world(midPoint, z: 0)

        // The near ("front") side is +z, toward the camera; the far side is -z.
        struct Side { let shoulder, elbow, hand, hip, knee, foot: SIMD3<Float> }
        let near = Side(shoulder: top + SIMD3(0, 0, sw), elbow: world(pose.elbowF, z: sw + 0.03), hand: world(pose.handF, z: sw),
                        hip: bottom + SIMD3(0, 0, hw), knee: world(pose.kneeF, z: hw), foot: world(pose.footF, z: hw))
        let far = Side(shoulder: top - SIMD3(0, 0, sw), elbow: world(pose.elbowB, z: -sw - 0.03), hand: world(pose.handB, z: -sw),
                       hip: bottom - SIMD3(0, 0, hw), knee: world(pose.kneeB, z: -hw), foot: world(pose.footB, z: -hw))

        stretch(bones[0], from: top, to: mid)
        stretch(bones[1], from: mid, to: bottom)
        stretch(bones[2], from: near.shoulder, to: far.shoulder)
        stretch(bones[3], from: near.hip, to: far.hip)
        for (i, side) in [near, far].enumerated() {
            let b = 4 + i * 4
            stretch(bones[b], from: side.shoulder, to: side.elbow)
            stretch(bones[b + 1], from: side.elbow, to: side.hand)
            stretch(bones[b + 2], from: side.hip, to: side.knee)
            stretch(bones[b + 3], from: side.knee, to: side.foot)
            let j = 3 + i * 6
            joints[j].simdPosition = side.shoulder; joints[j + 1].simdPosition = side.elbow; joints[j + 2].simdPosition = side.hand
            joints[j + 3].simdPosition = side.hip; joints[j + 4].simdPosition = side.knee; joints[j + 5].simdPosition = side.foot
        }
        joints[0].simdPosition = top; joints[1].simdPosition = mid; joints[2].simdPosition = bottom
        head.simdPosition = world(pose.head, z: 0)

        poseProps(near: (near.hand, near.hip, near.foot), far: (far.hand, far.hip, far.foot), pose: pose)
    }

    private func poseProps(near: (hand: SIMD3<Float>, hip: SIMD3<Float>, foot: SIMD3<Float>),
                           far: (hand: SIMD3<Float>, hip: SIMD3<Float>, foot: SIMD3<Float>), pose: FigurePose) {
        let hands = (near.hand + far.hand) / 2
        let across = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))     // lay a cylinder along z
        func bar(at centre: SIMD3<Float>) {
            propNodes["bar"]?.simdPosition = centre
            propNodes["bar"]?.simdOrientation = across
            for (name, z) in [("plateL", Float(0.6)), ("plateR", -0.6)] {
                propNodes[name]?.simdPosition = centre + SIMD3(0, 0, z)
                propNodes[name]?.simdOrientation = across
            }
        }
        switch prop {
        case .barbell, .bench:
            bar(at: hands)
        case .dumbbells:
            let along = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))  // lay a capsule along x
            propNodes["dbL"]?.simdPosition = near.hand; propNodes["dbL"]?.simdOrientation = along
            propNodes["dbR"]?.simdPosition = far.hand; propNodes["dbR"]?.simdOrientation = along
        case .highBar:
            // A pulldown bar travels with the hands; a hanging bar stays put.
            let seated = pose.hip.y > 0.6
            propNodes["bar"]?.simdPosition = seated ? hands : SIMD3(hands.x, 1.74, 0)
            propNodes["bar"]?.simdOrientation = across
        case .step:
            // A chair behind the hands for dips, a low box under the lead foot for step-ups.
            let chair = pose.handF.y > 0.55 && pose.footF.y > 0.85 && pose.handF.x < 0.5
            propNodes["box"]?.simdPosition = chair ? SIMD3(-0.42, 0.27, 0) : SIMD3(0.3, 0.13, 0)
            propNodes["box"]?.simdScale = chair ? SIMD3(0.8, 2.05, 1) : SIMD3(1, 1, 1)
        case .wheels:
            let seat = SIMD3<Float>(-0.2, 0.74, 0), crank = SIMD3<Float>(0.06, 0.3, 0), bars = SIMD3<Float>(0.5, 0.92, 0)
            if let a = propNodes["frameA"], let b = propNodes["frameB"], let c = propNodes["frameC"] {
                stretch(a, from: SIMD3(-0.48, 0.3, 0), to: seat)
                stretch(b, from: seat, to: crank)
                stretch(c, from: crank, to: bars)
            }
        case .seat:
            let hips = (near.hip + far.hip) / 2
            propNodes["seat"]?.simdPosition = hips - SIMD3(0, 0.14, 0)
        case .none:
            break
        }
    }
}

// MARK: - Live view

/// The figure in a live 3D view. Drag to look around it.
struct ExerciseFigure3DView: UIViewRepresentable {
    let pose: FigurePose
    let motion: ExerciseMotion
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.maximumVerticalAngle = 60
        view.defaultCameraController.minimumVerticalAngle = -5
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let dark = colorScheme == .dark
        if context.coordinator.figure == nil || context.coordinator.dark != dark || context.coordinator.motion != motion {
            let figure = FigureScene(prop: motion.prop, working: motion.workingLimbs, dark: dark)
            context.coordinator.figure = figure
            context.coordinator.dark = dark
            context.coordinator.motion = motion
            view.scene = figure.scene
            view.pointOfView = figure.cameraNode
        }
        context.coordinator.figure?.apply(pose)
    }

    @MainActor
    final class Coordinator {
        var figure: FigureScene?
        var dark = false
        var motion: ExerciseMotion?
    }
}

// MARK: - Still frames

/// Rendered stills of the start and finish positions, cached, for list rows
/// and the key-frame pair. A live 3D view per row would be far too heavy.
@MainActor
enum ExerciseSnapshot {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ motion: ExerciseMotion, finish: Bool, dark: Bool, side: CGFloat = 240) -> UIImage? {
        let key = "\(motion.rawValue)-\(finish)-\(dark)-\(Int(side))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let figure = FigureScene(prop: motion.prop, working: motion.workingLimbs, dark: dark)
        figure.apply(finish ? motion.poses.1 : motion.poses.0)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = figure.scene
        renderer.pointOfView = figure.cameraNode
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .multisampling4X)
        cache.setObject(image, forKey: key)
        return image
    }
}
