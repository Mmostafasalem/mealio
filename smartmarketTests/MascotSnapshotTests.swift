import XCTest
import SwiftUI
@testable import smartmarket

/// Renders the code-drawn bowl mascot to PNGs for visual review. Never asserts
/// on pixels and silently skips writing when the folder can't be created.
@MainActor
final class MascotSnapshotTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/mealio-run/mascot", isDirectory: true)

    func testRenderMascotPoses() throws {
        var poses: [(String, MascotRig)] = []
        for mood in MascotMood.allCases {
            let rig = MascotRig()
            rig.reduceMotion = false
            rig.set(mood: mood)
            rig.setActive(true)
            rig.stop()
            rig.simulate(seconds: 1.5)
            poses.append((mood.rawValue, rig))
        }
        let stretched = MascotRig()
        stretched.reduceMotion = false
        stretched.set(mood: .idle)
        stretched.setActive(true)
        stretched.stop()
        stretched.pickUp()
        for _ in 0..<12 {
            stretched.drag(velocity: CGVector(dx: 1400, dy: -1700))
            stretched.simulate(seconds: 1.0 / 30)
        }
        poses.append(("pickedup-stretched", stretched))

        let landing = MascotRig()
        landing.reduceMotion = false
        landing.set(mood: .idle)
        landing.setActive(true)
        landing.stop()
        landing.drop()
        landing.simulate(seconds: 0.1)
        landing.land(impact: 1)
        landing.simulate(seconds: 0.07)
        poses.append(("landing-squash", landing))

        let small = MascotRig()
        small.set(mood: .idle)

        guard (try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)) != nil else { return }
        for (name, rig) in poses {
            for scheme in [ColorScheme.light, .dark] {
                write(MascotFigure(pose: rig.pose, size: 132), name: "\(name)-\(scheme == .dark ? "dark" : "light")", scheme: scheme, side: 132)
            }
            if MascotMood(rawValue: name) != nil {
                write(MascotFigure(pose: rig.pose, size: 36), name: "\(name)-36pt-light", scheme: .light, side: 36)
            }
            rig.stop()
        }
        write(MascotFigure(pose: small.pose, size: 36), name: "idle-36pt-light", scheme: .light, side: 36)
    }

    /// The happy mascot, large and on a clear background, for the app icon (docs/brand/app-icon.py).
    func testRenderIconMascot() throws {
        let rig = MascotRig()
        rig.reduceMotion = true
        rig.set(mood: .happy)
        rig.simulate(seconds: 2)
        guard (try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)) != nil else { return }
        // 512 pt = the mascot's 512-unit design space; at scale 3 that's 3 px a unit.
        let renderer = ImageRenderer(content: MascotFigure(pose: rig.pose, size: 512).frame(width: 768, height: 768).environment(\.colorScheme, .light))
        renderer.scale = 3
        renderer.isOpaque = false
        guard let data = renderer.uiImage?.pngData() else { return XCTFail("no image") }
        try data.write(to: outDir.appendingPathComponent("mascot-icon-happy.png"))
    }

    /// Frame-by-frame clips of the mascot's own animation (30 fps, clear background) for the
    /// adverts in video/. Opt-in: TEST_RUNNER_NOURLO_MASCOT_CLIPS=1.
    func testRenderMascotClips() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NOURLO_MASCOT_CLIPS"] == "1", "Only for advert footage")
        let dir = URL(fileURLWithPath: "/tmp/mealio-run/clips", isDirectory: true)
        typealias Setup = (MascotRig) -> Void
        let clips: [(String, Double, Setup)] = [
            ("idle", 3, { $0.set(mood: .idle) }),
            ("happy", 2.5, { $0.set(mood: .happy) }),
            ("celebrate", 3, { $0.set(mood: .celebrate) }),
            ("love", 3, { $0.set(mood: .love) }),
            ("help", 3, { $0.set(mood: .help) }),
            ("thinking", 3, { $0.set(mood: .thinking) }),
            ("worried", 3, { $0.set(mood: .worried) }),
            ("sleepy", 3, { $0.set(mood: .sleepy) }),
            ("cheeky", 2.5, { $0.set(mood: .cheeky) }),
            ("hello", 2.5, { $0.set(mood: .idle); $0.react(.tap) }),
        ]
        for (name, seconds, setup) in clips {
            let rig = MascotRig()
            rig.reduceMotion = false
            rig.set(mood: .idle)
            rig.setActive(true)
            rig.stop()
            rig.simulate(seconds: 0.6)
            setup(rig)
            let folder = dir.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for i in 0..<Int(seconds * 30) {
                if i > 0 { rig.simulate(seconds: 1.0 / 30, fps: 120) }
                let renderer = ImageRenderer(content: MascotFigure(pose: rig.pose, size: 256).frame(width: 384, height: 384).environment(\.colorScheme, .light))
                renderer.scale = 2
                renderer.isOpaque = false
                guard let data = renderer.uiImage?.pngData() else { return XCTFail("no image") }
                try data.write(to: folder.appendingPathComponent(String(format: "f%03d.png", i)))
            }
            rig.stop()
        }
    }

    /// One continuous performance for the all-features advert (video/src/ads/combo.json):
    /// a scripted run of moods, looks, hops, waves and a jog, one frame per 1/30 s, so the mascot
    /// never repeats a loop. Opt-in: TEST_RUNNER_NOURLO_MASCOT_CLIPS=1.
    func testRenderAdvertPerformance() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NOURLO_MASCOT_CLIPS"] == "1", "Only for advert footage")
        // The simulator can't read ~/Documents, so video/make-performance.sh copies the timeline here first.
        let json = URL(fileURLWithPath: "/tmp/mealio-run/combo.json")
        let timeline = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: json)) as? [String: Any])
        let beats = try XCTUnwrap(timeline["beats"] as? [[String: Any]])
        func start(_ id: String) -> Double { ((beats.first { $0["id"] as? String == id }?["span"] as? [Double])?.first) ?? 0 }
        let outro = ((timeline["outro"] as? [Double])?.first) ?? 0, end = (timeline["end"] as? Double) ?? 0

        typealias Cue = (Double, (MascotRig) -> Void)
        let up = CGPoint(x: 0, y: -1)
        let cues: [Cue] = [
            (0.1, { $0.react(.tap) }), (0.9, { $0.look(at: CGPoint(x: -0.7, y: -0.7)) }), (1.4, { $0.look(at: nil) }),
            // plan: watches the typing above, hops when the week appears
            (start("plan"), { $0.set(mood: .happy); $0.look(at: up) }), (start("plan") + 1.1, { $0.look(at: nil); $0.hop() }),
            // budget: hearts, a happy stretch, a hop
            (start("budget"), { $0.set(mood: .love) }), (start("budget") + 0.6, { $0.resize(by: 0.7) }), (start("budget") + 1.35, { $0.hop() }),
            // voice: leans in to listen, then pleased when it's logged
            (start("voice"), { $0.set(mood: .idle); $0.look(at: up) }), (start("voice") + 0.5, { $0.resize(by: -0.4) }),
            (start("voice") + 1.3, { $0.set(mood: .happy); $0.look(at: nil); $0.hop() }),
            // scan: a wink at the scanner, a hop when it's found
            (start("scan"), { $0.set(mood: .cheeky); $0.look(at: CGPoint(x: 0.4, y: -0.9)) }), (start("scan") + 0.95, { $0.look(at: nil); $0.hop() }),
            // stock: thinks, then the idea lands
            (start("stock"), { $0.set(mood: .thinking); $0.look(at: CGPoint(x: -0.6, y: -0.8)) }),
            (start("stock") + 0.85, { $0.set(mood: .happy); $0.look(at: nil); $0.resize(by: 0.8) }), (start("stock") + 1.15, { $0.hop() }),
            // train: jogs in place, a wave mid-way
            (start("train"), { $0.set(mood: .idle); $0.walk(speed: 1.3) }), (start("train") + 1.0, { $0.wave() }), (start("train") + 2.1, { $0.walk(speed: 0) }),
            // cheer: confetti and jumps
            (start("cheer"), { $0.set(mood: .celebrate) }), (start("cheer") + 0.75, { $0.hop() }), (start("cheer") + 1.5, { $0.hop() }),
            // goodbye
            (outro, { $0.set(mood: .love) }), (outro + 0.4, { $0.wave() }),
        ]
        let rig = MascotRig()
        rig.reduceMotion = false
        rig.set(mood: .idle)
        rig.setActive(true)
        rig.stop()
        rig.simulate(seconds: 0.5)
        let folder = URL(fileURLWithPath: "/tmp/mealio-run/clips/perf", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var next = 0
        let sorted = cues.sorted { $0.0 < $1.0 }
        for i in 0..<Int((end + 1) * 30) {
            let t = Double(i) / 30
            while next < sorted.count, sorted[next].0 <= t { sorted[next].1(rig); next += 1 }
            if i > 0 { rig.simulate(seconds: 1.0 / 30, fps: 120) }
            let renderer = ImageRenderer(content: MascotFigure(pose: rig.pose, size: 256).frame(width: 384, height: 384).environment(\.colorScheme, .light))
            renderer.scale = 2
            renderer.isOpaque = false
            guard let data = renderer.uiImage?.pngData() else { return XCTFail("no image") }
            try data.write(to: folder.appendingPathComponent(String(format: "f%04d.png", i)))
        }
        rig.stop()
    }

    private func write<V: View>(_ view: V, name: String, scheme: ColorScheme, side: CGFloat) {
        let canvas = view
            .frame(width: side * 1.6, height: side * 1.6)
            .background(scheme == .dark ? Color(white: 0.08) : Color(white: 0.97))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return }
        try? data.write(to: outDir.appendingPathComponent("mascot-\(name).png"))
    }
}
