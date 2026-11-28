import SwiftUI

// MARK: - Exercise drawings
//
// Hand-drawn line art for the exercises, three frames each, with the muscles
// the exercise works filled red under the lines. The drawings are from
// Workout Guide by Bryl Lim, based on Everkinetic (CC BY-SA 4.0, credited under
// every drawing); `scripts/build-exercise-frames.py` converts them and the
// muscle marks into `Resources/ExerciseFrames.json.zlib`. Exercises without a
// drawing fall back to the posed line figure (`ExerciseDemo`).

nonisolated struct ExerciseDrawing: Sendable {
    let slug: String
    let frames: [Frame]

    struct Frame: Sendable {
        let outline: Path
        let muscles: Path
    }

    /// The drawings' own square, in points.
    static let size: CGFloat = 512
}

/// Loads the drawings once, off the main thread, and turns each into paths off
/// the main thread the first time it is shown.
///
/// The file is large (a few MB deflated, about 20 MB of path text), so it is never
/// read on the main thread: `preload()` starts reading it in the background at
/// launch, and views ask `ExerciseDrawingsStatus.shared.drawing(forExercise:)`,
/// which returns `nil` (draw a placeholder) until the file is ready and the
/// drawing's paths are built in the background, then updates them. Built drawings
/// are kept in a bounded cache, so scrolling the whole library doesn't keep every
/// one in memory; an evicted drawing is rebuilt from its text when shown again.
nonisolated final class ExerciseDrawings: @unchecked Sendable {
    static let shared = ExerciseDrawings()

    private struct File: Decodable {
        let credit: String
        let link: String
        let byExercise: [String: String]
        let drawings: [String: Drawing]
        struct Drawing: Decodable { let frames: [Frame] }
        struct Frame: Decodable { let path: String; let muscles: [[Double]] }
    }

    /// A built drawing, boxed for `NSCache`.
    private final class Built: @unchecked Sendable {
        let drawing: ExerciseDrawing
        init(_ drawing: ExerciseDrawing) { self.drawing = drawing }
    }

    /// Drawings that show a different exercise from the catalogue entry they were
    /// mapped to (a captain's-chair knee raise for "Seated knee tuck", a seated
    /// plate twist for "Thoracic rotation"). Those show their posed figure instead.
    private static let mismatched: Set<String> = ["leg-extension-crunch", "thoracic-rotation"]

    /// How many built drawings stay in memory: more than a screen of library rows.
    static let cacheLimit = 60

    /// Guards the state below; held only briefly, never while reading the file or building paths.
    private let lock = NSLock()
    /// Serialises reading the file, so it is read once however many callers ask.
    private let loadQueue = DispatchQueue(label: "ExerciseDrawings.load", qos: .utility)
    /// Builds drawings' paths for views, off the main thread.
    private let buildQueue = DispatchQueue(label: "ExerciseDrawings.build", qos: .userInitiated, attributes: .concurrent)
    /// Built drawings by slug. Thread-safe and bounded.
    private let cache = NSCache<NSString, Built>()
    /// Runs on the loading thread just before the file is read. For tests.
    private let willRead: (@Sendable () -> Void)?
    private var loaded = false
    private var creditText: String?
    private var creditLink: URL?
    private var byExercise: [String: String] = [:]
    /// The decoded drawings' path text, kept so an evicted drawing can be rebuilt.
    private var sources: [String: File.Drawing] = [:]
    private var readOnMainThread: Bool?
    private var backgroundBuildOnMainThread: Bool?

    /// The app uses `shared`; tests make their own, optionally with a hook that
    /// runs on the loading thread just before the file is read.
    init(willRead: (@Sendable () -> Void)? = nil) {
        self.willRead = willRead
        cache.countLimit = Self.cacheLimit
    }

    /// Starts reading the drawings in the background. Safe to call any number of
    /// times; call it at launch so the drawings are ready by the time the Train tab opens.
    static func preload() {
        shared.startLoading()
    }

    /// Starts reading this instance's file in the background and returns at once.
    func startLoading() {
        loadQueue.async { self.loadNow() }
    }

    /// True once the file has been read (or found missing).
    var isLoaded: Bool { lock.withLock { loaded } }

    /// Whether the file was read on the main thread (`nil` until it has been read). Should always be false.
    var wasReadOnMainThread: Bool? { lock.withLock { readOnMainThread } }

    /// Whether the last view-requested build ran on the main thread (`nil` before any). Should always be false.
    var lastBackgroundBuildWasOnMainThread: Bool? { lock.withLock { backgroundBuildOnMainThread } }

    /// Reads the file if it hasn't been read yet. Blocks; only called on `loadQueue`.
    private func loadNow() {
        if isLoaded { return }
        willRead?()
        let onMain = Thread.isMainThread
        // Deflated JSON (see scripts/build-exercise-frames.py).
        let file = Bundle.main.url(forResource: "ExerciseFrames.json", withExtension: "zlib")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? ($0 as NSData).decompressed(using: .zlib) as Data }
            .flatMap { try? JSONDecoder().decode(File.self, from: $0) }
        lock.withLock {
            guard !loaded else { return }
            if let file {
                creditText = file.credit
                creditLink = URL(string: file.link)
                byExercise = file.byExercise.filter { !Self.mismatched.contains($0.key) }
                sources = file.drawings
            }
            readOnMainThread = onMain
            loaded = true
        }
        if self === Self.shared {
            Task { @MainActor in ExerciseDrawingsStatus.shared.markReady() }
        }
    }

    /// The credit the drawings' licence asks for, shown wherever a drawing is. `nil` until loaded.
    var credit: (text: String, link: URL)? {
        lock.withLock {
            guard let creditText, let creditLink else { return nil }
            return (creditText, creditLink)
        }
    }

    /// The drawing for a catalogue exercise, reading the file and building the paths
    /// first if needed. Blocks: for tests and background work, not for views
    /// (they use `ExerciseDrawingsStatus.shared.drawing(forExercise:)`).
    func drawing(forExercise id: String) -> ExerciseDrawing? {
        if !isLoaded { loadQueue.sync { loadNow() } }
        return loadedDrawing(forExercise: id)
    }

    /// True when the file has been read and has a drawing for this exercise. Never blocks.
    func hasDrawing(forExercise id: String) -> Bool {
        lock.withLock {
            guard loaded, let slug = byExercise[id], let source = sources[slug] else { return false }
            return !source.frames.isEmpty
        }
    }

    /// The drawing if it is already built; never reads the file or builds paths.
    func cachedDrawing(forExercise id: String) -> ExerciseDrawing? {
        guard let slug = lock.withLock({ loaded ? byExercise[id] : nil }) else { return nil }
        return cache.object(forKey: slug as NSString)?.drawing
    }

    /// Builds the drawing on a background queue (if it isn't cached), then calls `done` there.
    func buildInBackground(forExercise id: String, done: @escaping @Sendable () -> Void) {
        buildQueue.async {
            let onMain = Thread.isMainThread
            _ = self.loadedDrawing(forExercise: id)
            self.lock.withLock { self.backgroundBuildOnMainThread = onMain }
            done()
        }
    }

    /// The drawing for a catalogue exercise if the file has been read, building its
    /// paths now if they aren't cached; `nil` otherwise. Never waits for the file.
    func loadedDrawing(forExercise id: String) -> ExerciseDrawing? {
        let (slug, source): (String?, File.Drawing?) = lock.withLock {
            guard loaded, let slug = byExercise[id] else { return (nil, nil) }
            return (slug, sources[slug])
        }
        guard let slug else { return nil }
        if let cached = cache.object(forKey: slug as NSString) { return cached.drawing }
        guard let source, !source.frames.isEmpty else { return nil }
        let made = ExerciseDrawing(slug: slug, frames: source.frames.map {
            ExerciseDrawing.Frame(outline: Self.path($0.path), muscles: Self.polygons($0.muscles))
        })
        cache.setObject(Built(made), forKey: slug as NSString)
        return made
    }

    /// Reads the relative commands the build script writes: m dx dy, l dx dy,
    /// c (two control points and the end, each relative to the pen), z.
    /// Works on the raw bytes: the text is only letters, digits, '.', '-' and spaces.
    private static func path(_ text: String) -> Path {
        var path = Path()
        var numbers: [CGFloat] = []
        numbers.reserveCapacity(6)
        var command: UInt8 = 0
        var pen = CGPoint.zero, start = CGPoint.zero
        // The number being read.
        var hasNumber = false, negative = false, whole: Double = 0, fraction: Double = 0, scale: Double = 1, inFraction = false
        func at(_ i: Int) -> CGPoint { CGPoint(x: pen.x + numbers[i], y: pen.y + numbers[i + 1]) }
        func flushNumber() {
            guard hasNumber else { return }
            let value = whole + fraction / scale
            numbers.append(CGFloat(negative ? -value : value))
            hasNumber = false; negative = false; whole = 0; fraction = 0; scale = 1; inFraction = false
        }
        func emit() {
            switch command {
            case UInt8(ascii: "m") where numbers.count >= 2:
                pen = at(0); start = pen
                path.move(to: pen)
            case UInt8(ascii: "l") where numbers.count >= 2:
                pen = at(0)
                path.addLine(to: pen)
            case UInt8(ascii: "c") where numbers.count >= 6:
                let c1 = at(0), c2 = at(2), end = at(4)
                path.addCurve(to: end, control1: c1, control2: c2)
                pen = end
            case UInt8(ascii: "z"):
                path.closeSubpath()
                pen = start
            default:
                break
            }
            numbers.removeAll(keepingCapacity: true)
        }
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                hasNumber = true
                let digit = Double(byte - UInt8(ascii: "0"))
                if inFraction { fraction = fraction * 10 + digit; scale *= 10 } else { whole = whole * 10 + digit }
            case UInt8(ascii: "."):
                if inFraction { flushNumber() }               // ".5.5" is two numbers
                hasNumber = true; inFraction = true
            case UInt8(ascii: "-"):
                flushNumber(); negative = true
            case UInt8(ascii: " "), UInt8(ascii: ","):
                flushNumber()
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"):
                flushNumber(); emit(); command = byte
            default:
                flushNumber()
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

/// Tells views when the drawings have finished loading, and when a drawing's
/// paths have been built, so a placeholder can turn into the drawing. Reading
/// `drawing(forExercise:)` or `credit` in a view's body is enough to be updated.
@MainActor
@Observable
final class ExerciseDrawingsStatus {
    static let shared = ExerciseDrawingsStatus()
    private init() { isReady = ExerciseDrawings.shared.isLoaded }

    private(set) var isReady: Bool
    /// Bumped whenever a drawing finishes building, so views showing a placeholder re-read.
    private(set) var builtCount = 0
    /// Exercises whose drawing is being built in the background.
    @ObservationIgnored private var building: Set<String> = []
    /// The most recently built drawings, held strongly so the shared cache evicting
    /// one under memory pressure can't start a build → evict → rebuild loop.
    @ObservationIgnored private var recent: [String: ExerciseDrawing] = [:]
    @ObservationIgnored private var recentOrder: [String] = []
    private static let recentLimit = 40

    fileprivate func markReady() { if !isReady { isReady = true } }

    private func didBuild(_ id: String) {
        building.remove(id)
        guard let built = ExerciseDrawings.shared.cachedDrawing(forExercise: id) else { return }
        remember(built, for: id)
        builtCount &+= 1
    }

    private func remember(_ drawing: ExerciseDrawing, for id: String) {
        if recent.updateValue(drawing, forKey: id) == nil { recentOrder.append(id) }
        else { recentOrder.removeAll { $0 == id }; recentOrder.append(id) }
        while recentOrder.count > Self.recentLimit { recent.removeValue(forKey: recentOrder.removeFirst()) }
    }

    /// The drawing once the file is ready and its paths are built; `nil` before that
    /// (starting whatever is still to do, off the main thread) or when the exercise has no drawing.
    func drawing(forExercise id: String) -> ExerciseDrawing? {
        guard isReady else { ExerciseDrawings.preload(); return nil }
        _ = builtCount
        if let held = recent[id] { return held }
        let drawings = ExerciseDrawings.shared
        if let cached = drawings.cachedDrawing(forExercise: id) { remember(cached, for: id); return cached }
        guard drawings.hasDrawing(forExercise: id) else { return nil }
        if building.insert(id).inserted {
            drawings.buildInBackground(forExercise: id) {
                Task { @MainActor in ExerciseDrawingsStatus.shared.didBuild(id) }
            }
        }
        return nil
    }

    /// True while the exercise's drawing is still loading or being built, so a placeholder can stand in.
    func isPending(forExercise id: String) -> Bool {
        guard isReady else { return true }
        _ = builtCount
        let drawings = ExerciseDrawings.shared
        return drawings.hasDrawing(forExercise: id) && drawings.cachedDrawing(forExercise: id) == nil
    }

    /// True when the exercise will have a drawing (or might, while still loading).
    func mayHaveDrawing(forExercise id: String) -> Bool {
        !isReady || ExerciseDrawings.shared.hasDrawing(forExercise: id)
    }

    /// The drawings' credit, once loaded.
    var credit: (text: String, link: URL)? {
        guard isReady else { ExerciseDrawings.preload(); return nil }
        return ExerciseDrawings.shared.credit
    }
}

/// The CC BY-SA credit for the drawings, as a small tappable link. Shown on every
/// screen that shows a drawing. Draws nothing until the drawings are loaded.
struct ExerciseDrawingCredit: View {
    var body: some View {
        if let credit = ExerciseDrawingsStatus.shared.credit {
            // CC BY-SA 4.0: who made them, that Nourlo changed them, and the licence.
            VStack(alignment: .leading, spacing: 2) {
                Link(destination: credit.link) {
                    Label(credit.text.replacingOccurrences(of: " · CC BY-SA 4.0", with: "") + " · adapted by Nourlo (muscle areas added)", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(Color.labelSecondary)
                        .multilineTextAlignment(.leading)
                }
                .accessibilityHint("Opens the drawings' source")
                .accessibilityIdentifier("exerciseDrawing.credit")
                Link("Licence: CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                    .font(.caption2)
                    .foregroundStyle(Color.labelSecondary)
                    .padding(.leading, 22)
            }
        }
    }
}

private enum ExerciseDrawingColor {
    /// The lines: the text colour in light mode; in dark mode a calm light grey rather than near-white, so they don't glare.
    static let ink: Color = {
        let light = UIColor(Color(hex: "#111111")), dark = UIColor(Color(hex: "#C9C9CE"))
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
/// and when tapped, then rests on the first frame. Under Reduce Motion every
/// frame is shown side by side, in order, without movement.
struct ExerciseDrawingDemo: View {
    let drawing: ExerciseDrawing
    var rounds: Int = 4
    /// What VoiceOver reads for the demo, e.g. "Demonstration of Push-up, works chest, triceps".
    var description: String = "Exercise demonstration"

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
        if reduceMotion {
            stills
        } else {
            animated
        }
    }

    /// Every frame in order, as a still sequence.
    private var stills: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(drawing.frames.indices, id: \.self) { index in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.labelTertiary)
                }
                ExerciseDrawingCanvas(drawing: drawing, frame: index)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description + ", shown in \(drawing.frames.count) steps")
        .accessibilityAddTraits(.isImage)
    }

    private var animated: some View {
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(description)
            .accessibilityAddTraits(.isImage)

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
