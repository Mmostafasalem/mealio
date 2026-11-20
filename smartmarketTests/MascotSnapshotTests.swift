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

    /// Nourlo's poses for the App Store images (scripts/make-store-images.py), 2304 px on a
    /// clear background: flexing, waving, mid-jump, heart eyes, cheeky, thinking, happy.
    func testRenderStorePoses() throws {
        typealias Setup = (MascotRig) -> Void
        let poses: [(String, Double, Setup)] = [
            ("flex", 1.2, { $0.set(mood: .flex) }),
            ("wave", 0.55, { $0.set(mood: .happy); $0.wave() }),
            ("jump", 0.32, { $0.set(mood: .celebrate); $0.hop() }),
            ("love", 1.5, { $0.set(mood: .love) }),
            ("cheeky", 1.5, { $0.set(mood: .cheeky) }),
            ("thinking", 1.5, { $0.set(mood: .thinking) }),
            ("happy", 1.5, { $0.set(mood: .happy) }),
        ]
        guard (try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)) != nil else { return }
        for (name, seconds, setup) in poses {
            let rig = MascotRig()
            rig.reduceMotion = false
            rig.set(mood: .idle)
            rig.setActive(true)
            rig.stop()
            rig.simulate(seconds: 0.6)
            setup(rig)
            rig.simulate(seconds: seconds, fps: 120)
            let renderer = ImageRenderer(content: MascotFigure(pose: rig.pose, size: 512).frame(width: 768, height: 768).environment(\.colorScheme, .light))
            renderer.scale = 3
            renderer.isOpaque = false
            guard let data = renderer.uiImage?.pngData() else { return XCTFail("no image") }
            try data.write(to: outDir.appendingPathComponent("store-\(name).png"))
            rig.stop()
        }
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

    /// Renders every advert script in /tmp/mealio-run/stories (video/make-stories.sh copies them there)
    /// into /tmp/mealio-run/clips/<id>/fNNNN.png. A script has `dur`, `path` (where the picture moves the
    /// mascot: walking keys step its feet, jump keys lift it, stretch it in flight and land it) and `rig`
    /// cues ("mood flex", "hop", "wave", "look 0.4 -0.9", "look none", "resize 0.7", "walk 1.2", "tap").
    /// Only one script: TEST_RUNNER_NOURLO_STORY=<id>.
    func testRenderStories() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NOURLO_MASCOT_CLIPS"] == "1", "Only for advert footage")
        let dir = URL(fileURLWithPath: "/tmp/mealio-run/stories", isDirectory: true)
        let only = ProcessInfo.processInfo.environment["NOURLO_STORY"]
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && (only == nil || only!.isEmpty || $0.deletingPathExtension().lastPathComponent == only) }
        XCTAssertFalse(files.isEmpty)
        for file in files { try renderStory(file) }
    }

    private struct PathKey { let t: Double; let x: Double; let y: Double; let size: Double; let move: String; let arc: Double }

    /// The picture's mascot position at time t: the same easing as video/src/story/path.ts.
    private static func place(_ keys: [PathKey], _ t: Double) -> (x: Double, y: Double, size: Double, moving: String?) {
        guard let first = keys.first else { return (540, 1400, 480, nil) }
        if t <= first.t { return (first.x, first.y, first.size, nil) }
        for i in 1..<keys.count where t < keys[i].t {
            let a = keys[i - 1], b = keys[i]
            let u = (t - a.t) / max(0.001, b.t - a.t)
            let e = u * u * (3 - 2 * u)
            let lift = b.move == "jump" ? -4 * b.arc * u * (1 - u) : 0
            let still = a.x == b.x && a.y == b.y
            return (a.x + (b.x - a.x) * e, a.y + (b.y - a.y) * e + lift, a.size + (b.size - a.size) * e, still ? nil : b.move)
        }
        let last = keys[keys.count - 1]
        return (last.x, last.y, last.size, nil)
    }

    private func renderStory(_ file: URL) throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let id = file.deletingPathExtension().lastPathComponent
        let dur = try XCTUnwrap(json["dur"] as? Double)
        let keys: [PathKey] = ((json["path"] as? [[String: Any]]) ?? []).map {
            PathKey(t: $0["t"] as? Double ?? 0, x: $0["x"] as? Double ?? 540, y: $0["y"] as? Double ?? 1400,
                    size: $0["size"] as? Double ?? 480, move: $0["move"] as? String ?? "glide", arc: $0["arc"] as? Double ?? 220)
        }
        let cues: [(Double, String)] = ((json["rig"] as? [[Any]]) ?? []).compactMap { c in
            guard c.count == 2, let t = (c[0] as? NSNumber)?.doubleValue, let cmd = c[1] as? String else { return nil }
            return (t, cmd)
        }.sorted { $0.0 < $1.0 }

        let rig = MascotRig()
        rig.reduceMotion = false
        rig.set(mood: .idle)
        rig.setActive(true)
        rig.stop()
        rig.simulate(seconds: 0.5)
        func run(_ cmd: String) {
            let w = cmd.split(separator: " ").map(String.init)
            switch w.first {
            case "mood": if let m = MascotMood(rawValue: w[1]) { rig.set(mood: m) }
            case "hop": rig.hop()
            case "wave": rig.wave()
            case "tap": rig.react(.tap)
            case "walk": rig.walk(speed: Double(w[1]) ?? 1)
            case "resize": rig.resize(by: Double(w[1]) ?? 0.5)
            case "look": rig.look(at: w[1] == "none" ? nil : CGPoint(x: Double(w[1]) ?? 0, y: Double(w[2]) ?? 0))
            default: XCTFail("unknown cue \(cmd)")
            }
        }
        let folder = URL(fileURLWithPath: "/tmp/mealio-run/clips/\(id)", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var next = 0, wasMoving: String? = nil, walkingByPath = false
        var last = Self.place(keys, 0)
        for i in 0..<Int((dur + 0.5) * 30) {
            let t = Double(i) / 30
            while next < cues.count, cues[next].0 <= t { run(cues[next].1); next += 1 }
            // Follow the picture: walking steps the feet, a jump is a lift, a flight and a landing.
            let now = Self.place(keys, t)
            if now.moving != wasMoving {
                if wasMoving == "jump" { rig.land(impact: 0.8) }
                if wasMoving == "walk", walkingByPath { rig.walk(speed: 0); walkingByPath = false }
                if now.moving == "jump" { rig.pickUp() }
                if now.moving == "walk" { rig.walk(speed: 1.2); walkingByPath = true }
                wasMoving = now.moving
            }
            if now.moving == "jump" {
                let k = 256 / max(1, now.size * 2 / 3)     // picture pixels to the rig's points
                rig.drag(velocity: CGVector(dx: (now.x - last.x) * 30 * k, dy: (now.y - last.y) * 30 * k))
            }
            last = now
            if i > 0 { rig.simulate(seconds: 1.0 / 30, fps: 120) }
            let renderer = ImageRenderer(content: MascotFigure(pose: rig.pose, size: 256).frame(width: 384, height: 384).environment(\.colorScheme, .light))
            renderer.scale = 1.5
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
