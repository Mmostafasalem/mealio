import XCTest
import UIKit
import SceneKit
@testable import smartmarket

/// Film strips of one rep, for judging the motion: 12 moments across a rep per
/// row. Written to `/tmp/mealio-run/motion`; nothing asserts on pixels.
@MainActor
final class ExerciseMotionFilmTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/mealio-run/motion", isDirectory: true)

    func testRenderFilmStrips() throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let motions: [ExerciseMotion] = [.backSquat, .press, .pushUp, .bentRow, .dumbbellBench, .lunge]
        let frames = 12, cell: CGFloat = 220
        let size = CGSize(width: cell * CGFloat(frames), height: cell * CGFloat(motions.count))
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            for (row, motion) in motions.enumerated() {
                let figure = FigureScene(motion: motion, dark: false)
                let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
                renderer.scene = figure.scene
                renderer.pointOfView = figure.cameraNode
                let (a, b) = motion.poses
                let period = RepTempo.period(for: motion)
                for column in 0..<frames {
                    let state = RepTempo.state(for: motion, elapsed: period * Double(column) / Double(frames))
                    figure.apply(from: a, to: b, progress: motion.legsLead ? state.legs : state.armNear, parts: state)
                    let shot = renderer.snapshot(atTime: 0, with: CGSize(width: cell, height: cell), antialiasingMode: .multisampling4X)
                    shot.draw(in: CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                    let label = String(format: "%@ %.1fs L%.2f S%.2f A%.2f", column == 0 ? motion.rawValue : "", period * Double(column) / Double(frames),
                                       state.legs, state.spine, state.armNear) as NSString
                    label.draw(at: CGPoint(x: CGFloat(column) * cell + 4, y: CGFloat(row) * cell + 2),
                               withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.black])
                }
            }
        }
        try image.pngData()?.write(to: outDir.appendingPathComponent("film.png"))
    }

    /// Every captured clip, 12 moments per row, from the app's camera and from the front.
    func testRenderClipStrips() throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let motions = ExerciseMotion.allCases.filter { $0.clip != nil }
        guard !motions.isEmpty else { return }
        let frames = 12, cell: CGFloat = 300
        for motion in motions {
            guard let clip = motion.clip else { continue }
            let size = CGSize(width: cell * CGFloat(frames), height: cell * 2)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
                let figure = FigureScene(motion: motion, dark: false)
                let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
                renderer.scene = figure.scene
                let home = figure.cameraNode.simdPosition - figure.focus
                for row in 0..<2 {
                    // Row 0: the app's view. Row 1: straight from the front.
                    let offset = row == 0 ? home : SIMD3<Float>(simd_length(home), 0.25, 0)
                    figure.cameraNode.simdPosition = figure.focus + offset
                    figure.cameraNode.look(at: SCNVector3(figure.focus))
                    renderer.pointOfView = figure.cameraNode
                    for column in 0..<frames {
                        figure.apply(clip: clip, at: clip.duration * Double(column) / Double(frames))
                        let shot = renderer.snapshot(atTime: 0, with: CGSize(width: cell, height: cell), antialiasingMode: .multisampling4X)
                        shot.draw(in: CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                    }
                }
            }
            try image.pngData()?.write(to: outDir.appendingPathComponent("clip-\(motion.rawValue).png"))
        }
    }

    /// One full stride of each gait, 12 moments per row.
    func testRenderGaitStrips() throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let motions: [ExerciseMotion] = [.walk, .run, .stairs]
        let frames = 12, cell: CGFloat = 300
        let size = CGSize(width: cell * CGFloat(frames), height: cell * CGFloat(motions.count))
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            for (row, motion) in motions.enumerated() {
                guard let gait = motion.gait else { continue }
                let figure = FigureScene(motion: motion, dark: false)
                let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
                renderer.scene = figure.scene
                renderer.pointOfView = figure.cameraNode
                for column in 0..<frames {
                    let phase = Double(column) / Double(frames)
                    let pose = gait.pose(phase: phase)
                    figure.apply(from: pose, to: pose, progress: CGFloat(phase))
                    let shot = renderer.snapshot(atTime: 0, with: CGSize(width: cell, height: cell), antialiasingMode: .multisampling4X)
                    shot.draw(in: CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                    (String(format: "%@ %.2f", motion.rawValue, phase) as NSString)
                        .draw(at: CGPoint(x: CGFloat(column) * cell + 4, y: CGFloat(row) * cell + 2),
                              withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: UIColor.black])
                }
            }
        }
        try image.pngData()?.write(to: outDir.appendingPathComponent("gait.png"))
    }

    /// A stride is a cycle: it ends where it began, the legs are half a cycle apart,
    /// a planted foot stays on the floor and a swinging foot clears it.
    func testGaitCycles() {
        for gait in [Gait.walk, .run, .stairs] {
            let a = gait.pose(phase: 0), b = gait.pose(phase: 1)
            XCTAssertEqual(a.footF.x, b.footF.x, accuracy: 0.0001)
            XCTAssertEqual(a.handB.y, b.handB.y, accuracy: 0.0001)
            // Half a stride later the two legs have swapped places.
            let half = gait.pose(phase: 0.5)
            XCTAssertEqual(a.footF.x, half.footB.x, accuracy: 0.0001)
            XCTAssertEqual(a.footF.y, half.footB.y, accuracy: 0.0001)
        }
        // Walking: always at least one foot on the floor.
        for i in 0..<100 {
            let p = Gait.walk.pose(phase: Double(i) / 100)
            XCTAssertEqual(max(p.footF.y, p.footB.y), 0.9, accuracy: 0.0001)
        }
        // Running: a moment with both feet off the floor.
        XCTAssertTrue((0..<100).contains { i in
            let p = Gait.run.pose(phase: Double(i) / 100)
            return p.footF.y < 0.89 && p.footB.y < 0.89
        })
        // Arms swing against the legs: near foot forward, near hand back.
        let strike = Gait.walk.pose(phase: 0.02)
        XCTAssertGreaterThan(strike.footF.x, strike.hip.x)
        XCTAssertLessThan(strike.handF.x, strike.shoulder.x)
    }

    /// The tempo itself: parts start in order and the lowering takes longer than the lift.
    func testWorkingPartLeadsAndLoweringIsSlower() {
        let squat = ExerciseMotion.backSquat, period = RepTempo.period(for: squat)
        let early = RepTempo.state(for: squat, elapsed: period * 0.12)
        XCTAssertGreaterThan(early.legs, early.spine)
        XCTAssertGreaterThan(early.spine, early.armNear)
        XCTAssertGreaterThan(early.armNear, early.armFar)

        let press = ExerciseMotion.press
        let lifting = RepTempo.state(for: press, elapsed: RepTempo.period(for: press) * 0.12)
        XCTAssertGreaterThan(lifting.armNear, lifting.spine)

        // Time spent between 10 % and 90 % of the travel, lowering vs lifting.
        func travelTime(_ range: ClosedRange<Double>) -> Double {
            stride(from: range.lowerBound, through: range.upperBound, by: 0.002)
                .filter { (0.1...0.9).contains(Double(RepTempo.state(for: squat, elapsed: period * $0).legs)) }.count.double * 0.002 * period
        }
        XCTAssertGreaterThan(travelTime(0...0.45), travelTime(0.5...0.85) * 1.2)
    }

    /// Starts and ends each rep exactly on the drawn start position.
    func testRepStartsAndEndsAtRest() {
        for motion in ExerciseMotion.allCases where !motion.isContinuous {
            let period = RepTempo.period(for: motion)
            for elapsed in [0, period * 0.999] {
                let s = RepTempo.state(for: motion, elapsed: elapsed)
                for v in [s.legs, s.spine, s.armNear, s.armFar, s.head] { XCTAssertEqual(Double(v), 0, accuracy: 0.01, "\(motion)") }
            }
        }
    }
}

private extension Int { var double: Double { Double(self) } }
