import XCTest
import SwiftUI
@testable import smartmarket

/// Renders the code-drawn bowl mascot to PNGs for visual review. Never asserts
/// on pixels and silently skips writing when the folder can't be created.
@MainActor
final class MascotSnapshotTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-mmostafasalem/7fe0ca52-e40e-4c45-b23c-5ec0fc3013b8/scratchpad/mascot-snapshots", isDirectory: true)

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
            rig.stop()
        }
        write(MascotFigure(pose: small.pose, size: 36), name: "idle-36pt-light", scheme: .light, side: 36)
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
