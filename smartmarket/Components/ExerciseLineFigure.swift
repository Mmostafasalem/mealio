import SwiftUI
import simd

// MARK: - Line-drawing exercise figure
//
// Draws a posed `FigureScene` like an instruction manual: a white body with a
// dark outline, the far-side limbs darker with a fainter outline, and the muscles the
// exercise works filled in red inside the outline. Every limb is a rounded
// tube seen in perspective from the figure's camera; pieces are painted back
// to front, each outlined first and filled after, so where two pieces meet
// the nearer one's outline shows the joint.

/// Everything needed to draw one moment of the figure.
struct FigureFrame {
    var joints: FigureScene.Joints
    var feet: [(heel: SIMD3<Float>, toe: SIMD3<Float>)]
    var props: [FigureScene.PropShape]
    var camera: SIMD3<Float>
    var focus: SIMD3<Float>
}

struct LineFigureCanvas: View {
    let frame: FigureFrame
    let muscles: Set<Muscle>
    /// Extra turn of the camera around the figure, in radians (from dragging).
    var turn: Float = 0

    var body: some View {
        Canvas { context, size in
            LineFigurePainter(frame: frame, muscles: muscles, turn: turn, size: size).draw(in: &context)
        }
        .accessibilityHidden(true)
    }
}

private enum LineFigureColor {
    static let ink = Color.labelPrimary
    static let near = adaptive("#FFFFFF", "#2B3547")
    static let far = adaptive("#C9CDD5", "#141A25")
    /// The far side's outline: fainter, so the near limbs read as in front.
    static let farInk = adaptive("#8D93A1", "#6B7486")
    static let worked = adaptive("#E24B4A", "#F0605E")
    static let workedFar = adaptive("#E79A99", "#8E3E44")
    static let kit = adaptive("#DCDEE3", "#3B4558")
    static let plate = adaptive("#A7ACB6", "#5A6479")

    private static func adaptive(_ light: String, _ dark: String) -> Color {
        let light = UIColor(Color(hex: light)), dark = UIColor(Color(hex: dark))
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

private struct LineFigurePainter {
    let frame: FigureFrame
    let muscles: Set<Muscle>
    let turn: Float
    let size: CGSize

    /// One outlined shape, in world space.
    enum Shape {
        /// A rounded tube; an end without a cap is cut square (for a long bar drawn in pieces).
        case tube(SIMD3<Float>, SIMD3<Float>, width: Float, capA: Bool = true, capB: Bool = true)
        /// The flat outline around a set of points (box, plate, the trunk between shoulders and hips).
        case hull([SIMD3<Float>])
        /// A closed loop of tube (a wheel).
        case loop([SIMD3<Float>], width: Float)
        /// A thin ink line with no fill (rope, cable).
        case thread(SIMD3<Float>, SIMD3<Float>)
    }

    /// Shapes drawn together at one depth: all outlines, then all fills, then the red muscles.
    struct Piece {
        var depth: Float
        var shapes: [(Shape, Color)]
        var muscles: [(Shape, Color)] = []
        /// On the far side of the body: darker fill and a fainter outline.
        var far = false
    }

    // MARK: Camera

    private struct Camera {
        let eye: SIMD3<Float>, forward: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>
        let focal: Float, centre: CGPoint
        func project(_ p: SIMD3<Float>) -> (point: CGPoint, depth: Float, scale: Float) {
            let v = p - eye
            let z = max(simd_dot(v, forward), 0.05)
            return (CGPoint(x: centre.x + CGFloat(focal * simd_dot(v, right) / z),
                            y: centre.y - CGFloat(focal * simd_dot(v, up) / z)), z, focal / z)
        }
    }

    private func camera() -> Camera {
        var offset = frame.camera - frame.focus
        if turn != 0 {
            let c = cos(turn), s = sin(turn)
            offset = SIMD3(offset.x * c + offset.z * s, offset.y, -offset.x * s + offset.z * c)
        }
        let eye = frame.focus + offset
        let forward = simd_normalize(frame.focus - eye)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let side = min(size.width, size.height)
        // The same 36° field of view the figure was framed for.
        return Camera(eye: eye, forward: forward, right: right, up: simd_cross(right, forward),
                      focal: Float(side / 2) / tan(18 * .pi / 180),
                      centre: CGPoint(x: size.width / 2, y: size.height / 2))
    }

    // MARK: Building the pieces

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }
    private func unit(_ v: SIMD3<Float>, _ fallback: SIMD3<Float>) -> SIMD3<Float> {
        let l = simd_length(v)
        return l > 0.0001 ? v / l : fallback
    }

    private func pieces(_ cam: Camera) -> [Piece] {
        let j = frame.joints
        let works = { (m: Muscle) in muscles.contains(m) }
        var out: [Piece] = []
        func depth(_ p: SIMD3<Float>) -> Float { cam.project(p).depth }
        let up = SIMD3<Float>(0, 1, 0)

        // Trunk, neck and hips as one piece, so their outlines merge into one silhouette.
        let near = LineFigureColor.near, red = LineFigureColor.worked
        let headDir = unit(j.head - j.top, up)
        var trunk = Piece(depth: depth(j.mid), shapes: [
            (.hull([j.shoulder[0], j.shoulder[1], j.hip[1], j.hip[0]]), near),
            (.tube(j.hip[0], j.hip[1], width: 0.21), near),
            (.tube(mix(j.bottom, j.mid, 0.4), j.mid, width: 0.25), near),
            (.tube(j.mid, mix(j.mid, j.top, 0.8), width: 0.3), near),
            (.tube(j.shoulder[0], j.shoulder[1], width: 0.13), near),
            (.tube(j.top, j.top + headDir * 0.13, width: 0.1), near),
        ])
        let across = unit(j.hip[0] - j.hip[1], SIMD3(0, 0, 1))
        if works(.chest) { trunk.muscles.append((.tube(mix(j.mid, j.top, 0.3), mix(j.mid, j.top, 0.85), width: 0.2), red)) }
        if works(.lats) { trunk.muscles.append((.tube(mix(j.mid, j.top, 0.05), mix(j.mid, j.top, 0.7), width: 0.24), red)) }
        if works(.abs) { trunk.muscles.append((.tube(mix(j.bottom, j.mid, 0.4), mix(j.mid, j.top, 0.15), width: 0.12), red)) }
        if works(.obliques) {
            for s: Float in [1, -1] {
                trunk.muscles.append((.tube(mix(j.bottom, j.mid, 0.35) + across * (0.085 * s), j.mid + across * (0.095 * s), width: 0.06), red))
            }
        }
        if works(.lowerBack) { trunk.muscles.append((.tube(mix(j.bottom, j.mid, 0.25), mix(j.bottom, j.mid, 0.95), width: 0.15), red)) }
        if works(.traps) {
            trunk.muscles.append((.tube(mix(j.shoulder[1], j.shoulder[0], 0.22), mix(j.shoulder[1], j.shoulder[0], 0.78), width: 0.075), red))
            trunk.muscles.append((.tube(j.top, j.top + headDir * 0.07, width: 0.07), red))
        }
        if works(.glutes) { trunk.muscles.append((.tube(mix(j.hip[1], j.hip[0], 0.15), mix(j.hip[1], j.hip[0], 0.85), width: 0.15), red)) }
        out.append(trunk)

        // Head: a slightly long egg above the neck.
        out.append(Piece(depth: depth(j.head), shapes: [(.tube(j.head - headDir * 0.02, j.head + headDir * 0.035, width: 0.22), near)]))

        for i in 0..<2 {
            let fill = i == 0 ? near : LineFigureColor.far
            let tint = i == 0 ? red : LineFigureColor.workedFar
            let (sh, el, hand) = (j.shoulder[i], j.elbow[i], j.hand[i])
            let (hip, knee, ankle) = (j.hip[i], j.knee[i], j.foot[i])

            var upper = Piece(depth: depth(mix(sh, el, 0.5)), shapes: [(.tube(sh, el, width: 0.105), fill)], far: i == 1)
            if works(.biceps) || works(.triceps) { upper.muscles.append((.tube(mix(sh, el, 0.28), mix(sh, el, 0.86), width: 0.068), tint)) }
            if works(.shoulders) { upper.muscles.append((.tube(sh, mix(sh, el, 0.2), width: 0.085), tint)) }
            out.append(upper)

            let lower = unit(hand - el, -up)
            var forearm = Piece(depth: depth(mix(el, hand, 0.5)), shapes: [
                (.tube(el, hand, width: 0.085), fill),
                (.tube(hand, hand + lower * 0.075, width: 0.075), fill),
            ], far: i == 1)
            if works(.forearms) { forearm.muscles.append((.tube(mix(el, hand, 0.1), mix(el, hand, 0.7), width: 0.058), tint)) }
            out.append(forearm)

            var thigh = Piece(depth: depth(mix(hip, knee, 0.5)), shapes: [(.tube(hip, knee, width: 0.16), fill)], far: i == 1)
            if works(.quads) || works(.hamstrings) { thigh.muscles.append((.tube(mix(hip, knee, 0.14), mix(hip, knee, 0.86), width: 0.11), tint)) }
            out.append(thigh)

            let foot: (heel: SIMD3<Float>, toe: SIMD3<Float>) = i < frame.feet.count
                ? frame.feet[i] : (ankle, ankle + SIMD3(0.16, -0.035, 0))
            var shin = Piece(depth: depth(mix(knee, ankle, 0.5)), shapes: [
                (.tube(knee, ankle, width: 0.112), fill),
                (.tube(foot.heel, foot.toe, width: 0.085), fill),
            ], far: i == 1)
            if works(.calves) { shin.muscles.append((.tube(mix(knee, ankle, 0.1), mix(knee, ankle, 0.6), width: 0.075), tint)) }
            out.append(shin)
        }

        // Equipment. Long pieces are cut into short lengths, each at its own depth,
        // so a bar across the back passes behind the neck and in front of the far hand.
        // A piece close to the trunk or head is put wholly behind or wholly in front
        // of them, by which side of the body it is on, since one point says little
        // about which of two big shapes is nearer.
        let trunkDepth = depth(j.mid), headDepth = depth(j.head)
        func rodDepth(_ p: SIMD3<Float>) -> Float {
            let own = depth(p)
            var nearest = j.bottom, best = Float.greatestFiniteMagnitude
            for (a, b) in [(j.bottom, j.top), (j.top, j.head)] {
                let ab = b - a
                let t = min(max(simd_dot(p - a, ab) / max(simd_length_squared(ab), 0.0001), 0), 1)
                let q = a + ab * t
                if simd_distance(p, q) < best { best = simd_distance(p, q); nearest = q }
            }
            guard best < 0.3 else { return own }
            return own > depth(nearest) ? max(own, trunkDepth, headDepth) + 0.01 : min(own, trunkDepth, headDepth) - 0.01
        }
        for prop in frame.props {
            switch prop {
            case let .rod(a, b, radius):
                let thread = radius < 0.008
                let count = max(1, Int((simd_length(b - a) / 0.22).rounded(.up)))
                for k in 0..<count {
                    let p = mix(a, b, Float(k) / Float(count)), q = mix(a, b, Float(k + 1) / Float(count))
                    let shape: Shape = thread ? .thread(p, q) : .tube(p, q, width: radius * 2, capA: k == 0, capB: k == count - 1)
                    out.append(Piece(depth: rodDepth(mix(p, q, 0.5)), shapes: [(shape, LineFigureColor.kit)]))
                }
            case let .disc(centre, axis, radius, thickness):
                let a = unit(simd_cross(axis, abs(axis.y) < 0.9 ? up : SIMD3(1, 0, 0)), SIMD3(1, 0, 0))
                let b = simd_cross(axis, a)
                func rim(_ offset: Float) -> [SIMD3<Float>] {
                    (0..<24).map { k in
                        let t = Float(k) / 24 * 2 * .pi
                        return centre + axis * offset + (a * cos(t) + b * sin(t)) * radius
                    }
                }
                let front = rim(thickness / 2), back = rim(-thickness / 2)
                let face = depth(centre + axis * thickness / 2) < depth(centre - axis * thickness / 2) ? front : back
                out.append(Piece(depth: depth(centre), shapes: [(.hull(front + back), LineFigureColor.plate),
                                                              (.hull(face), LineFigureColor.kit)]))
            case let .box(corners):
                let centre = corners.reduce(SIMD3<Float>(repeating: 0), +) / Float(max(corners.count, 1))
                out.append(Piece(depth: depth(centre), shapes: [(.hull(corners), LineFigureColor.kit)]))
            case let .ring(points, radius):
                let centre = points.reduce(SIMD3<Float>(repeating: 0), +) / Float(max(points.count, 1))
                out.append(Piece(depth: depth(centre) + 0.3, shapes: [(.loop(points, width: radius * 2), LineFigureColor.kit)]))
            case let .line(points):
                for (p, q) in zip(points, points.dropFirst()) {
                    out.append(Piece(depth: depth(mix(p, q, 0.5)), shapes: [(.thread(p, q), LineFigureColor.ink)]))
                }
            }
        }
        return out
    }

    // MARK: Drawing

    func draw(in context: inout GraphicsContext) {
        let cam = camera()
        let side = min(size.width, size.height)
        let outline = max(1.2, side * 0.0085)

        // A soft patch of floor under the figure.
        let j = frame.joints
        let ground = SIMD3<Float>((j.foot[0].x + j.foot[1].x + j.bottom.x) / 3, 0, (j.foot[0].z + j.foot[1].z) / 2)
        let floorPoints = (0..<32).map { k -> CGPoint in
            let t = Float(k) / 32 * 2 * .pi
            return cam.project(ground + SIMD3(cos(t) * 0.62, 0, sin(t) * 0.42)).point
        }
        var floor = Path()
        floor.addLines(floorPoints)
        floor.closeSubpath()
        context.fill(floor, with: .color(LineFigureColor.ink.opacity(0.05)))

        for piece in pieces(cam).sorted(by: { $0.depth > $1.depth }) {
            let ink = piece.far ? LineFigureColor.farInk : LineFigureColor.ink
            for (shape, _) in piece.shapes { paint(shape, colour: ink, grow: piece.far ? outline * 0.8 : outline, cam: cam, in: &context) }
            for (shape, colour) in piece.shapes { paint(shape, colour: colour, grow: 0, cam: cam, in: &context) }
            for (shape, colour) in piece.muscles { paint(shape, colour: colour, grow: 0, cam: cam, in: &context) }
        }
    }

    /// Fills one shape, `grow` points wider on every side (the outline pass).
    private func paint(_ shape: Shape, colour: Color, grow: CGFloat, cam: Camera, in context: inout GraphicsContext) {
        let shading = GraphicsContext.Shading.color(colour)
        switch shape {
        case let .tube(a, b, width, capA, capB):
            let pa = cam.project(a), pb = cam.project(b)
            let w = CGFloat(width * (pa.scale + pb.scale) / 2) + grow * 2
            var line = Path()
            line.move(to: pa.point)
            line.addLine(to: pb.point)
            context.stroke(line, with: shading, style: StrokeStyle(lineWidth: w, lineCap: .butt))
            for (point, capped) in [(pa.point, capA), (pb.point, capB)] where capped {
                context.fill(Path(ellipseIn: CGRect(x: point.x - w / 2, y: point.y - w / 2, width: w, height: w)), with: shading)
            }
        case let .hull(points):
            let outline = Self.convexHull(points.map { cam.project($0).point })
            guard outline.count > 2 else { return }
            var path = Path()
            path.addLines(outline)
            path.closeSubpath()
            context.fill(path, with: shading)
            if grow > 0 { context.stroke(path, with: shading, style: StrokeStyle(lineWidth: grow * 2, lineJoin: .round)) }
        case let .loop(points, width):
            let projected = points.map { cam.project($0) }
            guard let first = projected.first else { return }
            var path = Path()
            path.addLines(projected.map(\.point))
            path.closeSubpath()
            context.stroke(path, with: shading, style: StrokeStyle(lineWidth: CGFloat(width * first.scale) + grow * 2, lineJoin: .round))
        case let .thread(a, b):
            // Ink only: drawn once, in the outline pass.
            guard grow > 0 else { return }
            var line = Path()
            line.move(to: cam.project(a).point)
            line.addLine(to: cam.project(b).point)
            context.stroke(line, with: .color(LineFigureColor.ink.opacity(0.8)), style: StrokeStyle(lineWidth: grow, lineCap: .round))
        }
    }

    /// Andrew's monotone chain.
    private static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count > 2 else { return sorted }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
}

// MARK: - Posing for the views

/// Keeps one posed figure for a view, rebuilt only when the movement changes.
@MainActor
final class FigureHolder {
    private var figure: FigureScene?
    private var motion: ExerciseMotion?

    func figure(for motion: ExerciseMotion) -> FigureScene {
        if let figure, self.motion == motion { return figure }
        let made = FigureScene(motion: motion, dark: false)
        figure = made
        self.motion = motion
        return made
    }
}

/// The start and finish positions, posed once and kept, for list rows and the key-frame pair.
@MainActor
enum ExerciseStill {
    private static var cache: [String: FigureFrame] = [:]

    static func frame(_ motion: ExerciseMotion, finish: Bool) -> FigureFrame {
        let key = "\(motion.rawValue)-\(finish)"
        if let hit = cache[key] { return hit }
        let figure = FigureScene(motion: motion, dark: false)
        if let clip = motion.clip {
            figure.apply(clip: clip, at: finish ? clip.duration * Double(clip.key) : 0)
        } else {
            figure.apply(finish ? motion.poses.1 : motion.poses.0)
        }
        let made = figure.frame()
        cache[key] = made
        return made
    }
}

/// A still rendered to an image (used by the review tests).
@MainActor
enum ExerciseSnapshot {
    static func image(_ motion: ExerciseMotion, finish: Bool, dark: Bool, side: CGFloat = 240) -> UIImage? {
        let view = LineFigureCanvas(frame: ExerciseStill.frame(motion, finish: finish), muscles: motion.muscles)
            .frame(width: side, height: side)
            .background(Color.surface)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }
}
