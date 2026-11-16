import XCTest
import UIKit
import SceneKit
@testable import smartmarket

/// Renders every exercise figure for visual review and measures where body
/// parts pass through each other. The pictures go to `/tmp/mealio-run/figures`
/// (skipped silently if the folder can't be made); nothing asserts on pixels.
@MainActor
final class ExerciseFigureSnapshotTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/mealio-run/figures", isDirectory: true)

    private func render(_ figure: FigureScene, side: CGFloat) -> UIImage {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = figure.scene
        renderer.pointOfView = figure.cameraNode
        return renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .multisampling4X)
    }

    private func sheet(columns: Int, rows: Int, cell: CGFloat, dark: Bool = false,
                       draw: (_ column: Int, _ row: Int) -> (UIImage?, String?)) -> UIImage {
        let size = CGSize(width: cell * CGFloat(columns), height: cell * CGFloat(rows))
        return UIGraphicsImageRenderer(size: size).image { context in
            (dark ? UIColor(white: 0.1, alpha: 1) : UIColor.white).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for row in 0..<rows {
                for column in 0..<columns {
                    let origin = CGPoint(x: CGFloat(column) * cell, y: CGFloat(row) * cell)
                    let (image, label) = draw(column, row)
                    image?.draw(in: CGRect(origin: origin, size: CGSize(width: cell, height: cell)))
                    (label as NSString?)?.draw(at: CGPoint(x: origin.x + 6, y: origin.y + 4), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                        .foregroundColor: dark ? UIColor.white : UIColor.black,
                    ])
                }
            }
        }
    }

    /// Every movement: start, half-way and finish from the app's camera, then
    /// the half-way and finish positions from the opposite side and the front.
    func testRenderExerciseFigures() throws {
        guard (try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)) != nil else { return }
        let motions = ExerciseMotion.allCases
        let perSheet = 6
        for (index, start) in stride(from: 0, to: motions.count, by: perSheet).enumerated() {
            let group = Array(motions[start..<min(start + perSheet, motions.count)])
            let figures = group.map { FigureScene(motion: $0, dark: false) }
            let homes = figures.map { $0.cameraNode.simdPosition - $0.focus }
            let review = sheet(columns: 6, rows: group.count, cell: 300) { column, row in
                let motion = group[row], figure = figures[row], home = homes[row]
                let progress: [CGFloat] = [0, 0.5, 1, 0.5, 1, 1]
                switch column {
                case 3, 4: figure.cameraNode.simdPosition = figure.focus + SIMD3(-home.x, home.y, -home.z)     // opposite corner
                case 5:    figure.cameraNode.simdPosition = figure.focus + SIMD3(home.x > 0 ? 1 : -1, 0.12, 0.004) * simd_length(home)  // face on
                default:   figure.cameraNode.simdPosition = figure.focus + home
                }
                figure.cameraNode.look(at: SCNVector3(figure.focus.x, figure.focus.y, figure.focus.z))
                figure.apply(from: motion.poses.0, to: motion.poses.1, progress: progress[column])
                return (render(figure, side: 300), column == 0 ? motion.rawValue : nil)
            }
            try? review.pngData()?.write(to: outDir.appendingPathComponent("review-\(index).png"))
        }
        let dark = sheet(columns: 6, rows: 1, cell: 300, dark: true) { column, _ in
            let motion = [ExerciseMotion.benchPress, .lunge, .seatedRow, .gobletSquat, .pushUp, .cycle][column]
            return (ExerciseSnapshot.image(motion, finish: true, dark: true, side: 300), motion.rawValue)
        }
        try? dark.pngData()?.write(to: outDir.appendingPathComponent("review-dark.png"))
        XCTAssertTrue(motions.allSatisfy { !$0.muscles.isEmpty }, "every motion highlights at least one muscle")
    }

    /// Close-ups of the hands on their equipment and of the red muscle areas.
    func testRenderCloseUps() throws {
        guard (try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)) != nil else { return }
        // (name, motion, progress, camera offset from the hands, look-at offset from the hands)
        let shots: [(String, ExerciseMotion, CGFloat, SIMD3<Float>)] = [
            ("dip chair", .dip, 1, SIMD3(1.0, 0.5, 1.6)), ("bench start feet", .benchPress, 0, SIMD3(1.0, 0.5, 0.8)),
            ("bench finish", .benchPress, 1, SIMD3(-0.9, 0.3, 0.9)), ("db bench start", .dumbbellBench, 0, SIMD3(1.0, 0.6, 0.9)),
            ("db bench finish", .dumbbellBench, 1, SIMD3(-0.9, 0.3, 0.9)), ("barbell row", .barbellRow, 1, SIMD3(1.2, 0.3, 1.6)),
            ("pulldown", .pulldown, 1, SIMD3(0.9, 0.2, 0.9)), ("lunge", .lunge, 1, SIMD3(0.5, 0.3, 1.1)),
            ("goblet", .gobletSquat, 0, SIMD3(1.0, 0.2, 0.7)), ("goblet down", .gobletSquat, 1, SIMD3(1.0, 0.3, 0.7)),
            ("back squat", .backSquat, 0, SIMD3(-0.9, 0.4, 0.8)), ("back squat down", .backSquat, 1, SIMD3(-0.9, 0.5, 0.8)),
            ("row start", .seatedRow, 0, SIMD3(0.4, 0.5, 1.2)), ("row finish", .seatedRow, 1, SIMD3(0.6, 0.5, 1.1)),
            ("one-arm row", .bentRow, 1, SIMD3(0.8, 0.2, 1.0)), ("pike side", .pikePushUp, 0, SIMD3(0.0, 0.3, 3.0)),
            ("pike side down", .pikePushUp, 1, SIMD3(0.0, 0.3, 3.0)), ("cycle", .cycle, 0, SIMD3(0.7, 0.4, 1.0)),
            ("jump rope", .jumpRope, 0.5, SIMD3(1.6, 0.0, 2.6)), ("woodchop", .woodchop, 0.5, SIMD3(1.3, 0.2, 2.2)),
        ]
        let figures = shots.map { FigureScene(motion: $0.1, dark: false) }
        let closeUps = sheet(columns: 5, rows: 4, cell: 420) { column, row in
            let i = row * 5 + column
            let shot = shots[i], figure = figures[i]
            figure.apply(from: shot.1.poses.0, to: shot.1.poses.1, progress: shot.2)
            let hands = (figure.joints.hand[0] + figure.joints.hand[1]) / 2
            figure.cameraNode.simdPosition = hands + shot.3
            figure.cameraNode.look(at: SCNVector3(hands.x, hands.y, hands.z))
            return (render(figure, side: 420), shot.0)
        }
        try? closeUps.pngData()?.write(to: outDir.appendingPathComponent("closeups.png"))
    }

    /// Measures, for every movement at five moments, how far one body part
    /// sinks into another, treating limbs as rounded rods and the torso as a
    /// flattened one. Writes the list to `overlaps.txt`; anything deep fails.
    func testBodyPartsDoNotPassThroughEachOther() throws {
        func closest(_ a0: SIMD3<Float>, _ a1: SIMD3<Float>, _ b0: SIMD3<Float>, _ b1: SIMD3<Float>) -> Float {
            // Sampled, which is plenty for rods a few centimetres thick.
            var best = Float.greatestFiniteMagnitude
            for i in 0...8 {
                let p = a0 + (a1 - a0) * (Float(i) / 8)
                let ab = b1 - b0
                let t = min(max(simd_dot(p - b0, ab) / max(simd_length_squared(ab), 0.0001), 0), 1)
                best = min(best, simd_length(p - (b0 + ab * t)))
            }
            return best
        }
        var lines: [String] = []
        var worst: Float = 0
        for motion in ExerciseMotion.allCases {
            let figure = FigureScene(motion: motion, dark: false)
            var found: [String: Float] = [:]
            for step in 0...4 {
                figure.apply(from: motion.poses.0, to: motion.poses.1, progress: CGFloat(step) / 4)
                let j = figure.joints
                func note(_ name: String, _ depth: Float) { if depth > 0.02 { found[name] = max(found[name] ?? 0, depth) } }
                // Torso: wider than deep. Squash the across-body axis so one radius serves.
                func squash(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(p.x, p.y, p.z * 0.62) }
                for side in 0..<2 {
                    let other = 1 - side
                    // Forearm and hand against the torso (the upper arm starts inside the shoulder, so skip it).
                    for (name, a, b, radius) in [("forearm", j.elbow[side], j.hand[side], Float(0.045)),
                                                 ("lower upper-arm", (j.shoulder[side] + j.elbow[side]) / 2, j.elbow[side], 0.055)] {
                        let d = min(closest(squash(a), squash(b), squash(j.top), squash(j.mid)),
                                    closest(squash(a), squash(b), squash(j.mid), squash(j.bottom)))
                        note("\(name) \(side) in torso", 0.125 + radius * 0.8 - d)
                    }
                    note("forearm \(side) in own thigh", 0.135 - closest(j.elbow[side], j.hand[side], (j.hip[side] + j.knee[side]) / 2, j.knee[side]))
                    note("forearm \(side) in other thigh", 0.135 - closest(j.elbow[side], j.hand[side], (j.hip[other] + j.knee[other]) / 2, j.knee[other]))
                    note("forearm \(side) in shin", 0.105 - closest(j.elbow[side], j.hand[side], j.knee[side], j.foot[side]))
                    note("hand \(side) in head", 0.16 - simd_length(j.hand[side] - j.head))
                    note("forearm \(side) in head", 0.15 - closest(j.elbow[side], j.hand[side], j.head, j.head))
                }
                // Equipment against the body. A bar may rest on the shoulders or
                // collarbone, so the top fifth of the chest is left out for it.
                for (i, rod) in figure.rods.enumerated() {
                    let upper = j.top + (j.mid - j.top) * 0.2
                    let torso = min(closest(squash(rod.from), squash(rod.to), squash(upper), squash(j.mid)),
                                    closest(squash(rod.from), squash(rod.to), squash(j.mid), squash(j.bottom)))
                    note("equipment \(i) in torso", 0.125 + rod.radius - torso)
                    note("equipment \(i) in head", 0.105 + rod.radius - closest(rod.from, rod.to, j.head, j.head))
                    for side in 0..<2 {
                        note("equipment \(i) in thigh \(side)", 0.085 + rod.radius - closest(rod.from, rod.to, (j.hip[side] + j.knee[side]) / 2, j.knee[side]))
                        note("equipment \(i) in shin \(side)", 0.05 + rod.radius - closest(rod.from, rod.to, j.knee[side], j.foot[side]))
                    }
                }
                note("forearms cross", 0.085 - closest(j.elbow[0], j.hand[0], j.elbow[1], j.hand[1]))
                note("thighs", 0.16 - closest((j.hip[0] + j.knee[0]) / 2, j.knee[0], (j.hip[1] + j.knee[1]) / 2, j.knee[1]))
                note("shins", 0.11 - closest(j.knee[0], j.foot[0], j.knee[1], j.foot[1]))
                note("shin 0 in thigh 1", 0.14 - closest(j.knee[0], j.foot[0], (j.hip[1] + j.knee[1]) / 2, j.knee[1]))
                note("shin 1 in thigh 0", 0.14 - closest(j.knee[1], j.foot[1], (j.hip[0] + j.knee[0]) / 2, j.knee[0]))
                note("feet", 0.09 - simd_length(j.foot[0] - j.foot[1]))
                note("hand 0 below floor", -j.hand[0].y - 0.0)
                note("foot below floor", -min(j.foot[0].y, j.foot[1].y))
                note("knee below floor", 0.03 - min(j.knee[0].y, j.knee[1].y))
            }
            for (name, depth) in found.sorted(by: { $0.value > $1.value }) {
                lines.append(String(format: "%-14@ %-28@ %.3f", motion.rawValue as NSString, name as NSString, depth))
                worst = max(worst, depth)
            }
        }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try? (lines.isEmpty ? "no overlaps over 2 cm\n" : lines.joined(separator: "\n") + "\n")
            .write(to: outDir.appendingPathComponent("overlaps.txt"), atomically: true, encoding: .utf8)
        XCTAssertLessThan(worst, 0.06, "a body part sinks more than 6 cm into another; see overlaps.txt")
    }
}
