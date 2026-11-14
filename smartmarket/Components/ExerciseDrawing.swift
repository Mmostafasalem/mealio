import SwiftUI

// MARK: - Exercise drawings
//
// Hand-drawn line art for the exercises, three frames each, with the muscles
// the exercise works filled red under the lines. The drawings are from
// Workout Guide by Bryl Lim, based on Everkinetic (CC BY-SA 4.0, credited under
// every drawing); `scripts/build-exercise-frames.py` converts them and the
// muscle marks into `Resources/ExerciseFrames.json.zlib`. Exercises without a
// drawing fall back to the posed line figure (`ExerciseDemo`).

struct ExerciseDrawing {
    let slug: String
    let frames: [Frame]

    struct Frame {
        let outline: Path
        let muscles: Path
    }

    /// The drawings' own square, in points.
    static let size: CGFloat = 512
}

/// Loads the drawings once and turns each into paths the first time it is shown.
final class ExerciseDrawings: @unchecked Sendable {
    static let shared = ExerciseDrawings()

    private struct File: Decodable {
        let credit: String
        let link: String
        let byExercise: [String: String]
        let drawings: [String: Drawing]
        struct Drawing: Decodable { let frames: [Frame] }
        struct Frame: Decodable { let path: String; let muscles: [[Double]] }
    }

    private let file: File?
    private var built: [String: ExerciseDrawing] = [:]
    private let lock = NSLock()

    private init() {
        // Deflated JSON (see scripts/build-exercise-frames.py).
        file = Bundle.main.url(forResource: "ExerciseFrames.json", withExtension: "zlib")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? ($0 as NSData).decompressed(using: .zlib) as Data }
            .flatMap { try? JSONDecoder().decode(File.self, from: $0) }
    }

    /// The credit the drawings' licence asks for, shown under every drawing.
    var credit: (text: String, link: URL)? {
        guard let file, let url = URL(string: file.link) else { return nil }
        return (file.credit, url)
    }

    /// The drawing for a catalogue exercise, if there is one.
    func drawing(forExercise id: String) -> ExerciseDrawing? {
        guard let file, let slug = file.byExercise[id], let source = file.drawings[slug], !source.frames.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let hit = built[slug] { return hit }
        let made = ExerciseDrawing(slug: slug, frames: source.frames.map {
            ExerciseDrawing.Frame(outline: Self.path($0.path), muscles: Self.polygons($0.muscles))
        })
        built[slug] = made
        return made
    }

    /// Reads the relative commands the build script writes: m dx dy, l dx dy,
    /// c (two control points and the end, each relative to the pen), z.
    private static func path(_ text: String) -> Path {
        var path = Path()
        var numbers: [CGFloat] = []
        var command: Character = " "
        var token = ""
        var pen = CGPoint.zero, start = CGPoint.zero
        func at(_ i: Int) -> CGPoint { CGPoint(x: pen.x + numbers[i], y: pen.y + numbers[i + 1]) }
        func flushNumber() {
            if let v = Double(token) { numbers.append(CGFloat(v)) }
            token = ""
        }
        func emit() {
            switch command {
            case "m" where numbers.count >= 2:
                pen = at(0); start = pen
                path.move(to: pen)
            case "l" where numbers.count >= 2:
                pen = at(0)
                path.addLine(to: pen)
            case "c" where numbers.count >= 6:
                let c1 = at(0), c2 = at(2), end = at(4)
                path.addCurve(to: end, control1: c1, control2: c2)
                pen = end
            case "z":
                path.closeSubpath()
                pen = start
            default:
                break
            }
            numbers.removeAll(keepingCapacity: true)
        }
        for ch in text {
            if ch.isLetter {
                flushNumber(); emit(); command = ch
            } else if ch == " " || ch == "," {
                flushNumber()
            } else if ch == "-" {
                flushNumber(); token = "-"
            } else {
                token.append(ch)
            }
        }
        flushNumber(); emit()
        return path
    }

    private static func polygons(_ shapes: [[Double]]) -> Path {
        var path = Path()
        for flat in shapes where flat.count >= 6 {
            path.move(to: CGPoint(x: flat[0], y: flat[1]))
            for k in stride(from: 2, to: flat.count - 1, by: 2) { path.addLine(to: CGPoint(x: flat[k], y: flat[k + 1])) }
            path.closeSubpath()
        }
        return path
    }
}

private enum ExerciseDrawingColor {
    /// The lines: the text colour in light mode; in dark mode a calm light grey rather than near-white, so they don't glare.
    static let ink: Color = {
        let light = UIColor(Color(hex: "#1E2A40")), dark = UIColor(Color(hex: "#C3C9D4"))
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }()
    static let worked: Color = {
        let light = UIColor(Color(hex: "#E24B4A")), dark = UIColor(Color(hex: "#F0605E"))
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }()
}

/// One frame of a drawing: the worked muscles in red, the lines over them.
struct ExerciseDrawingCanvas: View {
    let drawing: ExerciseDrawing
    let frame: Int

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            context.scaleBy(x: side / ExerciseDrawing.size, y: side / ExerciseDrawing.size)
            let f = drawing.frames[min(max(frame, 0), drawing.frames.count - 1)]
            context.fill(f.muscles, with: .color(ExerciseDrawingColor.worked), style: FillStyle(eoFill: true))
            context.fill(f.outline, with: .color(ExerciseDrawingColor.ink), style: FillStyle(eoFill: true))
        }
        .accessibilityHidden(true)
    }
}

/// The drawing playing through its frames (1, 2, 3, 2, 1 …), each held a
/// moment and cross-faded into the next. Plays a few rounds when it appears
/// and when tapped, then rests on the first frame. Still under Reduce Motion.
struct ExerciseDrawingDemo: View {
    let drawing: ExerciseDrawing
    var rounds: Int = 4

    @State private var startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let hold = 0.6, fade = 0.32
    private var stepTime: Double { Self.hold + Self.fade }
    /// Frame order for one round: there and back.
    private var order: [Int] {
        let n = drawing.frames.count
        return n > 1 ? Array(0..<n) + Array((1..<(n - 1)).reversed()) : [0]
    }
    private var runTime: Double { stepTime * Double(order.count * rounds) }
    private var isPlaying: Bool { startedAt != nil }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
                let elapsed = startedAt.map { timeline.date.timeIntervalSince($0) } ?? runTime
                let done = elapsed >= runTime
                let (from, to, blend) = moment(done ? 0 : elapsed)
                Canvas2(drawing: drawing, from: from, to: to, blend: blend)
                    .padding(Spacing.md)
                    .onChange(of: done) { _, finished in if finished { startedAt = nil } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !reduceMotion {
                Button { play() } label: {
                    Label(isPlaying ? "Playing" : "Play", systemImage: isPlaying ? "waveform" : "play.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
                        .foregroundStyle(Color.labelPrimary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ScalePressStyle())
                .disabled(isPlaying)
                .opacity(isPlaying ? 0.6 : 1)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xs)
                .accessibilityLabel("Play the movement")
                .accessibilityIdentifier("exerciseDemo.play")
            }
        }
        .onAppear { play() }
        .animation(.snappyValue, value: isPlaying)
    }

    /// Which frame shows at this moment, which comes next, and how far the fade between them is.
    private func moment(_ elapsed: Double) -> (Int, Int, Double) {
        let steps = order
        let step = Int(elapsed / stepTime)
        let into = elapsed - Double(step) * stepTime
        let from = steps[step % steps.count], to = steps[(step + 1) % steps.count]
        let t = max(0, (into - Self.hold) / Self.fade)
        return (from, to, t * t * (3 - 2 * t))
    }

    private func play() {
        guard !reduceMotion else { return }
        startedAt = Date()
    }

    /// Two frames cross-faded.
    private struct Canvas2: View {
        let drawing: ExerciseDrawing
        let from: Int, to: Int
        let blend: Double
        var body: some View {
            ZStack {
                ExerciseDrawingCanvas(drawing: drawing, frame: from).opacity(1 - blend)
                if blend > 0.001 { ExerciseDrawingCanvas(drawing: drawing, frame: to).opacity(blend) }
            }
        }
    }
}
