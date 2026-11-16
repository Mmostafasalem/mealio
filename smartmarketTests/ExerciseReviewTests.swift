import XCTest
import UIKit
import SceneKit
@testable import smartmarket

/// Builds the exercise review: every exercise in the app, then every captured
/// candidate no exercise uses yet. Each one is put through the same automatic
/// checks and rendered as numbered frames (two views) for a review video.
///
/// Output in `/tmp/mealio-run/review`: `frames/f%06d.jpg` and `results.json`.
/// `scripts/make-exercise-review.sh` runs this and turns it into a video and a
/// checklist. Opt-in: it only runs with `TEST_RUNNER_EXERCISE_REVIEW=1`.
@MainActor
final class ExerciseReviewTests: XCTestCase {
    private let out = URL(fileURLWithPath: "/tmp/mealio-run/review", isDirectory: true)
    private let fps = 20.0

    private struct Item {
        let title: String
        let group: String          // "In the app" or "Candidate"
        let source: String         // where the movement comes from
        /// Built when its turn comes and dropped after, so a hundred bodies are never in memory at once.
        let make: () -> FigureScene
        let loop: Double           // seconds for one loop
        let show: (FigureScene, Double) -> Void
    }

    private struct Result: Encodable {
        let number: Int
        let title: String
        let group: String
        let source: String
        let verdict: String
        let flags: [String]
        let seconds: Double
        let startSecond: Double
    }

    func testBuildReview() throws {
        guard ProcessInfo.processInfo.environment["EXERCISE_REVIEW"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_EXERCISE_REVIEW=1 to build the review.")
        }
        let frames = out.appendingPathComponent("frames", isDirectory: true)
        try? FileManager.default.removeItem(at: frames)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

        var results: [Result] = []
        var frameIndex = 0
        let items = makeItems()
        for (index, item) in items.enumerated() {
            let figure = item.make()
            let flags = check(item, figure)
            let seconds = min(max(item.loop * (item.loop < 1.5 ? 3 : (item.loop < 3 ? 2 : 1)), 3), 7)
            results.append(Result(number: index + 1, title: item.title, group: item.group, source: item.source,
                                  verdict: flags.isEmpty ? "PASS" : "CHECK", flags: flags, seconds: seconds,
                                  startSecond: Double(frameIndex) / fps))
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = figure.scene
            let home = figure.cameraNode.simdPosition - figure.focus
            let distance = simd_length(home)
            for step in 0..<Int(seconds * fps) {
                let time = Double(step) / fps
                item.show(figure, time)
                let size = CGSize(width: 960, height: 540)
                let image = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { context in
                    UIColor(white: 0.1, alpha: 1).setFill(); context.fill(CGRect(origin: .zero, size: size))
                    for (offset, frame) in [(home, CGRect(x: 0, y: 40, width: 500, height: 500)),
                                            (SIMD3<Float>(distance, 0.25, 0), CGRect(x: 500, y: 60, width: 460, height: 460))] {
                        figure.cameraNode.simdPosition = figure.focus + offset
                        figure.cameraNode.look(at: SCNVector3(figure.focus))
                        renderer.pointOfView = figure.cameraNode
                        renderer.snapshot(atTime: 0, with: frame.size, antialiasingMode: .multisampling2X).draw(in: frame)
                    }
                    let white: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: UIColor.white]
                    ("#\(index + 1)  \(item.title)" as NSString).draw(at: CGPoint(x: 16, y: 8), withAttributes: white)
                    let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: UIColor(white: 0.7, alpha: 1)]
                    ("\(item.group) · \(item.source)" as NSString).draw(at: CGPoint(x: 16, y: 512), withAttributes: small)
                    let pass = flags.isEmpty
                    let badge = (pass ? "AUTO: PASS" : "AUTO: CHECK") as NSString
                    let colour = pass ? UIColor(red: 0.3, green: 0.8, blue: 0.45, alpha: 1) : UIColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1)
                    badge.draw(at: CGPoint(x: 800, y: 12), withAttributes: [.font: UIFont.systemFont(ofSize: 18, weight: .heavy), .foregroundColor: colour])
                    if !pass {
                        (flags.joined(separator: " · ") as NSString).draw(in: CGRect(x: 500, y: 500, width: 450, height: 40),
                                                                           withAttributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: colour])
                    }
                }
                try image.jpegData(compressionQuality: 0.8)?.write(to: frames.appendingPathComponent(String(format: "f%06d.jpg", frameIndex)))
                frameIndex += 1
            }
            // Put the camera back for anything else that uses this figure.
            figure.cameraNode.simdPosition = figure.focus + home
        }
        try JSONEncoder().encode(results).write(to: out.appendingPathComponent("results.json"))
        print("REVIEW items \(items.count) frames \(frameIndex) pass \(results.filter { $0.verdict == "PASS" }.count)")
    }

    // MARK: Items

    private func makeItems() -> [Item] {
        var items: [Item] = []
        var used = Set<String>()
        for exercise in Exercise.catalog {
            guard let motion = exercise.motion else { continue }
            let make = { FigureScene(motion: motion, dark: true) }
            if let clip = motion.clip {
                used.insert(clip.name)
                items.append(Item(title: exercise.name, group: "In the app", source: "captured: \(Self.short(clip.credit))",
                                  make: make, loop: clip.duration) { f, t in f.apply(clip: clip, at: t) })
            } else if let gait = motion.gait {
                items.append(Item(title: exercise.name, group: "In the app", source: "generated stride", make: make, loop: gait.period) { f, t in
                    let pose = gait.pose(phase: t / gait.period)
                    f.apply(from: pose, to: pose, progress: 0)
                })
            } else {
                let (a, b) = motion.poses
                let period = RepTempo.period(for: motion)
                items.append(Item(title: exercise.name, group: "In the app", source: "two drawn poses", make: make, loop: period) { f, t in
                    let state = RepTempo.state(for: motion, elapsed: t)
                    f.apply(from: a, to: b, progress: motion.legsLead ? state.legs : state.armNear, parts: state)
                })
            }
        }
        // Movements built for review that are not exercises yet.
        let inCatalogue = Set(Exercise.catalog.compactMap(\.motion))
        for motion in ExerciseMotion.allCases where !inCatalogue.contains(motion) {
            guard let title = motion.candidateTitle else { continue }
            let make = { FigureScene(motion: motion, dark: true) }
            if let clip = motion.clip {
                items.append(Item(title: title, group: "Candidate · gym", source: "captured: \(Self.short(clip.credit)) + weight",
                                  make: make, loop: clip.duration) { f, t in f.apply(clip: clip, at: t) })
            } else {
                let (a, b) = motion.poses
                let period = RepTempo.period(for: motion)
                items.append(Item(title: title, group: "Candidate · gym", source: "two drawn poses", make: make, loop: period) { f, t in
                    let state = RepTempo.state(for: motion, elapsed: t)
                    f.apply(from: a, to: b, progress: motion.legsLead ? state.legs : state.armNear, parts: state)
                })
            }
        }
        // Captured clips nothing uses yet.
        let titles = (try? JSONDecoder().decode([String: [String: String]].self,
                                                from: Data(contentsOf: out.appendingPathComponent("titles.json")))) ?? [:]
        for name in MotionClip.library.keys.sorted(by: { (titles[$0]?["title"] ?? $0) < (titles[$1]?["title"] ?? $1) }) where !used.contains(name) {
            guard let clip = MotionClip.library[name] else { continue }
            items.append(Item(title: titles[name]?["title"] ?? name, group: "Candidate", source: "captured: \(Self.short(clip.credit))",
                              make: { FigureScene(clip: clip, dark: true) }, loop: clip.duration) { f, t in f.apply(clip: clip, at: t) })
        }
        return items
    }

    private static func short(_ credit: MotionClip.Credit) -> String {
        switch credit {
        case .cmu: return "CMU"
        case .arkitVicon: return "Vicon exercise set"
        case .hundredStyle: return "100STYLE"
        case .accad: return "ACCAD"
        case .cyclists: return "cyclists"
        }
    }

    // MARK: Checks

    /// Runs one loop and returns what looks wrong, in plain words. Empty means it passed.
    private func check(_ item: Item, _ figure: FigureScene) -> [String] {
        let steps = max(Int(item.loop * 30), 12)
        var poses: [FigureScene.Joints] = []
        for i in 0..<steps {
            item.show(figure, item.loop * Double(i) / Double(steps))
            poses.append(figure.joints)
        }
        func points(_ j: FigureScene.Joints) -> [SIMD3<Float>] {
            [j.top, j.mid, j.bottom, j.head] + j.shoulder + j.elbow + j.hand + j.hip + j.knee + j.foot
        }
        var flags: [String] = []
        let pelvisHigh = poses.map(\.bottom.y).max() ?? 0
        let standing = pelvisHigh > 0.65

        // Through the floor.
        let sunk = poses.contains { j in
            j.foot.contains { $0.y < 0.03 } || j.knee.contains { $0.y < 0.02 } || j.hand.contains { $0.y < -0.02 }
                || j.bottom.y < 0.06 || j.head.y < 0.06
        }
        if sunk { flags.append("part of the body goes through the floor") }

        if standing {
            // Hips collapsing to the floor (a squat that sits down).
            if (poses.map(\.bottom.y).min() ?? 1) < 0.3 { flags.append("hips drop almost to the floor") }
            // Never touching down.
            let airborne = poses.filter { min($0.foot[0].y, $0.foot[1].y) > 0.14 }.count
            if Double(airborne) / Double(poses.count) > 0.7 { flags.append("feet float above the floor") }
        }

        // Knees folded past what a knee does.
        func kneeBend(_ j: FigureScene.Joints, _ s: Int) -> Float {
            let a = simd_normalize(j.hip[s] - j.knee[s]), b = simd_normalize(j.foot[s] - j.knee[s])
            return 180 - acos(min(max(simd_dot(a, b), -1), 1)) * 180 / .pi
        }
        if poses.contains(where: { kneeBend($0, 0) > 158 || kneeBend($0, 1) > 158 }) { flags.append("a knee folds too far") }

        // Arms or knees inside the trunk.
        func toSpine(_ p: SIMD3<Float>, _ j: FigureScene.Joints) -> Float {
            func segment(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
                let ab = b - a
                let t = min(max(simd_dot(p - a, ab) / max(simd_length_squared(ab), 0.0001), 0), 1)
                return simd_length(p - (a + ab * t))
            }
            return min(segment(j.bottom, j.mid), segment(j.mid, j.top))
        }
        let armInside = poses.filter { j in (j.elbow + j.hand).contains { toSpine($0, j) < 0.075 } }.count
        if Double(armInside) / Double(poses.count) > 0.08 { flags.append("an arm passes through the body") }
        let kneeInside = poses.filter { j in j.knee.contains { toSpine($0, j) < 0.07 } }.count
        if Double(kneeInside) / Double(poses.count) > 0.08 { flags.append("a knee passes through the body") }

        // Legs through each other.
        let crossed = poses.filter { simd_length($0.knee[0] - $0.knee[1]) < 0.055 || simd_length($0.foot[0] - $0.foot[1]) < 0.045 }.count
        if Double(crossed) / Double(poses.count) > 0.06 { flags.append("the legs pass through each other") }

        // Movement: frozen, popping, or a jump where the loop restarts.
        var moves: [Float] = []
        for i in 0..<poses.count {
            let a = points(poses[i]), b = points(poses[(i + 1) % poses.count])
            moves.append(zip(a, b).map { simd_length($0 - $1) }.max() ?? 0)
        }
        let still = moves.filter { $0 < 0.0008 }.count
        if Double(still) / Double(moves.count) > 0.5 { flags.append("hardly moves (a hold, or a frozen capture)") }
        let typical = moves.sorted()[moves.count / 2]
        if let seam = moves.last, seam > max(typical * 4, 0.06) { flags.append("jumps where the loop restarts") }
        if moves.dropLast().contains(where: { $0 > 0.2 }) { flags.append("pops between frames") }
        return flags
    }
}
