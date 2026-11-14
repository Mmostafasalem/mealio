import Foundation
import simd

// MARK: - Captured motion clips
//
// Real human movement for the exercise demos, cut from the CMU Graphics Lab
// Motion Capture Database (mocap.cs.cmu.edu; free to include in products,
// credited under the demo) by `scripts/build-exercise-clips.py` into
// `Resources/ExerciseClips.bin`. A clip is a seamless loop of joint positions
// at 30 frames a second; `FigureScene.apply(captured:clip:)` fits them onto the
// app's own body, bone by bone.

struct MotionClip {
    /// The capture sources, in the order the builder numbers them.
    enum Credit: Int {
        case cmu, arkitVicon, hundredStyle, accad, cyclists

        var text: String {
            switch self {
            case .cmu: return "Movement: CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu), funded by NSF EIA-0196217"
            case .arkitVicon: return "Movement: Reimer, Kapsecker, Fukushima & Jonas, ARKit vs Vicon exercise dataset · CC BY 4.0"
            case .hundredStyle: return "Movement: 100STYLE dataset by Mason, Starke & Komura · CC BY 4.0"
            case .accad: return "Movement: ACCAD Motion Lab, The Ohio State University · CC BY 3.0"
            case .cyclists: return "Movement: cyclists motion capture dataset · CC BY 4.0"
            }
        }

        var link: URL {
            switch self {
            case .cmu: return URL(string: "http://mocap.cs.cmu.edu")!
            case .arkitVicon: return URL(string: "https://doi.org/10.5281/zenodo.6527283")!
            case .hundredStyle: return URL(string: "https://www.ianxmason.com/100style/")!
            case .accad: return URL(string: "https://accad.osu.edu/research/motion-lab/mocap-system-and-data")!
            case .cyclists: return URL(string: "https://doi.org/10.5281/zenodo.10668611")!
            }
        }
    }

    /// Joint order in every frame.
    enum Joint: Int {
        case pelvis, mid, top, head
        case lShoulder, lElbow, lWrist, lHip, lKnee, lAnkle, lSole
        case rShoulder, rElbow, rWrist, rHip, rKnee, rAnkle, rSole
        case lHand, rHand
    }

    let name: String
    let framesPerSecond: Float
    /// The captured person's leg length (thigh + shin), in metres.
    let leg: Float
    /// Their ankle height above the floor with the foot flat.
    let ankleRest: Float
    /// Where the "finish" still is taken, as a fraction of the clip.
    let key: Float
    /// The body lies or crawls: the lowest joint rests on the floor, not a foot.
    let lying: Bool
    /// Whose capture this is (they are credited under the demo).
    let credit: Credit
    /// Extra numbers for some clips. Jump rope: how many hops the loop holds. Stairs: one step's run and rise, and where the top of a step
    /// sat under the planted foot at the first frame (x, y), all in the captured person's metres.
    let aux: [Float]
    let frameCount: Int
    let jointCount: Int
    /// Millimetres: frame × joint × (x forward, y up, z to the figure's right).
    private let data: [Int16]

    var duration: Double { Double(frameCount) / Double(framesPerSecond) }

    /// Joint positions (metres) at `time`, looping, blended between frames.
    func joints(at time: Double) -> [SIMD3<Float>] {
        let position = (time / duration - (time / duration).rounded(.down)) * Double(frameCount)
        let a = Int(position) % frameCount, b = (a + 1) % frameCount
        let w = Float(position - position.rounded(.down))
        return (0..<jointCount).map { j in
            func point(_ frame: Int) -> SIMD3<Float> {
                let i = (frame * jointCount + j) * 3
                return SIMD3(Float(data[i]), Float(data[i + 1]), Float(data[i + 2])) / 1000
            }
            return simd_mix(point(a), point(b), SIMD3(repeating: w))
        }
    }

    // MARK: Loading

    static let library: [String: MotionClip] = load()

    private static func load() -> [String: MotionClip] {
        guard let url = Bundle.main.url(forResource: "ExerciseClips", withExtension: "bin"),
              let file = try? Data(contentsOf: url), file.count > 8, file.prefix(4) == Data("NCP3".utf8) else { return [:] }
        var cursor = 4
        func take<T>(_ type: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard cursor + size <= file.count else { return nil }
            defer { cursor += size }
            return file.subdata(in: cursor..<cursor + size).withUnsafeBytes { $0.loadUnaligned(as: T.self) }
        }
        guard let count = take(UInt32.self) else { return [:] }
        var clips: [String: MotionClip] = [:]
        for _ in 0..<count {
            guard let nameLength = take(UInt8.self), cursor + Int(nameLength) <= file.count else { break }
            let name = String(decoding: file.subdata(in: cursor..<cursor + Int(nameLength)), as: UTF8.self)
            cursor += Int(nameLength)
            guard let flags = take(UInt8.self), let source = take(UInt8.self),
                  let fps = take(Float.self), let leg = take(Float.self), let ankle = take(Float.self),
                  let key = take(Float.self),
                  let a0 = take(Float.self), let a1 = take(Float.self), let a2 = take(Float.self), let a3 = take(Float.self),
                  let frames = take(UInt32.self), let joints = take(UInt32.self) else { break }
            let values = Int(frames) * Int(joints) * 3
            guard frames > 1, joints >= 20, cursor + values * 2 <= file.count else { break }
            let data = file.subdata(in: cursor..<cursor + values * 2).withUnsafeBytes { raw in
                (0..<values).map { raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self) }
            }
            cursor += values * 2
            clips[name] = MotionClip(name: name, framesPerSecond: fps, leg: leg, ankleRest: ankle, key: key,
                                     lying: flags & 1 != 0, credit: Credit(rawValue: Int(source)) ?? .cmu, aux: [a0, a1, a2, a3],
                                     frameCount: Int(frames), jointCount: Int(joints), data: data)
        }
        return clips
    }
}

extension ExerciseMotion {
    /// The captured movement for this exercise, when there is one. The loaded
    /// squats use the bodyweight squat's legs and back, with the arms on the weight.
    var clip: MotionClip? {
        switch self {
        case .backSquat, .gobletSquat: return MotionClip.library["squat"]
        default: return MotionClip.library[rawValue]
        }
    }
}
