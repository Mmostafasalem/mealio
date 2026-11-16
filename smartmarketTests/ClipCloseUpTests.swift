import XCTest
import UIKit
import SceneKit
@testable import smartmarket

/// Large stills of captured clips at chosen moments, from several sides, for judging form.
@MainActor
final class ClipCloseUpTests: XCTestCase {
    func testRenderCloseUps() throws {
        let out = URL(fileURLWithPath: "/tmp/mealio-run/closeups", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let names = (ProcessInfo.processInfo.environment["CLIPS"] ?? "reverseFly,backSquat,squat").split(separator: ",").map(String.init)
        let cell: CGFloat = 520
        for name in names {
            guard let motion = ExerciseMotion(rawValue: name), let clip = motion.clip else { continue }
            let moments: [Double] = [0, 0.25, Double(clip.key), 0.75]
            let size = CGSize(width: cell * CGFloat(moments.count), height: cell * 3)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor(white: 0.12, alpha: 1).setFill(); context.fill(CGRect(origin: .zero, size: size))
                let figure = FigureScene(motion: motion, dark: true)
                let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
                renderer.scene = figure.scene
                let home = figure.cameraNode.simdPosition - figure.focus
                let distance = simd_length(home)
                let views: [SIMD3<Float>] = [home, SIMD3(distance, 0.3, 0), SIMD3(0.01, 0.3, distance)]   // app, front, side
                for (row, offset) in views.enumerated() {
                    figure.cameraNode.simdPosition = figure.focus + offset
                    figure.cameraNode.look(at: SCNVector3(figure.focus))
                    renderer.pointOfView = figure.cameraNode
                    for (column, moment) in moments.enumerated() {
                        figure.apply(clip: clip, at: clip.duration * moment)
                        renderer.snapshot(atTime: 0, with: CGSize(width: cell, height: cell), antialiasingMode: .multisampling4X)
                            .draw(in: CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                    }
                }
            }
            try image.jpegData(compressionQuality: 0.85)?.write(to: out.appendingPathComponent("\(name).jpg"))
        }
    }
}
