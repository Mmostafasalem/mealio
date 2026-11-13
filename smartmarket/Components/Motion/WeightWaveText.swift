import SwiftUI

// MARK: - Weight wave
//
// Port of designbookmark.com/motion "Weight wave" (weight-wave/wave.js).
// Each letter's weight is a spring pulled toward a bell curve around a focus
// point, so a swell of extra weight rolls through the word. The line rests as a
// bold headline; the swell plays once left to right the first time the word
// appears in a session, and after that only follows a finger. Idle costs nothing:
// the clock stops as soon as every letter has landed.

enum WeightWaveMotion {
    /// Resting weight: the word reads as a headline.
    static let rest: Double = 700
    /// Peak of the swell under the focus point.
    static let bold: Double = 820
    /// Width of the swell, as a share of the line.
    static let spread: Double = 0.13
    static let letter = MotionTokens.Preset(k: 260, c: 22)
    static let focus = MotionTokens.Preset(k: 150, c: 22)
    /// The one intro sweep runs the focus from just left of the line to just right of it.
    static let sweepFrom: Double = -0.06
    static let sweepTo: Double = 1.06
    static let reducedWeight: Double = 700
}

struct WeightWaveText: View {
    let text: String
    /// Play the one intro sweep the first time this word appears in the session.
    var autoplay: Bool = true
    /// Extra space between letters (the old headline used tracking -1).
    var kerning: CGFloat = 0

    @State private var model = WeightWaveModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    init(_ text: String, autoplay: Bool = true, kerning: CGFloat = 0) {
        self.text = text
        self.autoplay = autoplay
        self.kerning = kerning
    }

    private var letters: [String] { text.map(String.init) }

    private var fontSize: CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        return UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 34, compatibleWith: traits)
    }

    var body: some View {
        HStack(spacing: kerning) {
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                let weight = reduceMotion ? WeightWaveMotion.reducedWeight : model.weight(at: index)
                Text(letter)
                    .font(Font(UIFont.systemFont(ofSize: fontSize, weight: .css(weight))))
                    .fixedSize()
                    .background(GeometryReader { geometry in
                        Color.clear.preference(
                            key: LetterCentreKey.self,
                            value: [index: geometry.frame(in: .named(WeightWaveModel.space)).midX])
                    })
            }
        }
        // One preference carries the letter centres and, under key -1, the line width.
        .background(GeometryReader { geometry in
            Color.clear.preference(key: LetterCentreKey.self, value: [-1: geometry.size.width])
        })
        .coordinateSpace(name: WeightWaveModel.space)
        .onPreferenceChange(LetterCentreKey.self) { values in
            var centres = values
            if let width = centres.removeValue(forKey: -1) { model.lineWidth = width }
            model.centres = centres
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !reduceMotion else { return }
                    model.point(at: value.location.x)
                }
                .onEnded { _ in
                    guard !reduceMotion else { return }
                    model.release()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
        .onAppear {
            model.configure(count: letters.count)
            model.visible = true
            if autoplay && !reduceMotion { model.playIntroOnce(key: text) }
            updateRunning()
        }
        .onDisappear {
            model.visible = false
            updateRunning()
        }
        .onChange(of: scenePhase) { _, _ in updateRunning() }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { model.rest() }
            updateRunning()
        }
        .onChange(of: text) { _, _ in model.configure(count: letters.count) }
    }

    private func updateRunning() {
        model.setRunning(model.visible && scenePhase == .active && !reduceMotion)
    }
}

// MARK: - Model

@MainActor @Observable
final class WeightWaveModel {
    static let space = "weightWave"

    /// Words whose intro sweep already played this session.
    private static var introPlayed: Set<String> = []

    /// Published only when a letter's weight actually changed.
    private(set) var weights: [Double] = []

    @ObservationIgnored var centres: [Int: CGFloat] = [:]
    @ObservationIgnored var lineWidth: CGFloat = 1
    @ObservationIgnored var visible = false
    @ObservationIgnored private var springs: [MotionSpring] = []
    /// Where the swell is: 0 = left end of the line, 1 = right end.
    @ObservationIgnored private var focus = MotionSpring(WeightWaveMotion.sweepFrom, WeightWaveMotion.focus)
    @ObservationIgnored private var touching = false
    @ObservationIgnored private var sweeping = false
    @ObservationIgnored private var allowedToRun = false
    @ObservationIgnored private var buffer: [Double] = []
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func configure(count: Int) {
        guard springs.count != count else { return }
        springs = (0..<count).map { _ in MotionSpring(WeightWaveMotion.rest, WeightWaveMotion.letter) }
        weights = springs.map(\.x)
        buffer = weights
    }

    func weight(at index: Int) -> Double {
        index < weights.count ? weights[index] : WeightWaveMotion.rest
    }

    /// One left-to-right swell, the first time this word appears in the session.
    func playIntroOnce(key: String) {
        guard !Self.introPlayed.contains(key) else { return }
        Self.introPlayed.insert(key)
        sweeping = true
        focus.snap(WeightWaveMotion.sweepFrom)
        focus.t = WeightWaveMotion.sweepTo
    }

    /// Jump every letter to rest (Reduce Motion switched on).
    func rest() {
        touching = false
        sweeping = false
        for i in springs.indices { springs[i].snap(WeightWaveMotion.rest) }
        focus.snap(focus.t)
        publish()
        clock.stop()
    }

    /// Runs only while visible, in an active scene, and something still moves.
    func setRunning(_ running: Bool) {
        allowedToRun = running
        if running && isMoving { clock.start() } else { clock.stop() }
    }

    private var isMoving: Bool {
        touching || sweeping
            || !focus.isSettled
            || springs.contains { !$0.isSettled(within: MotionSpring.fontWeight) }
    }

    func point(at x: CGFloat) {
        touching = true
        sweeping = false
        focus.t = Double(x / max(lineWidth, 1))
        if allowedToRun { clock.start() }
    }

    func release() {
        touching = false
    }

    private func frame(_ dt: Double) {
        // Wait for the letters to be measured before moving anything.
        guard centres.count >= springs.count else { return }
        focus.step(dt)
        if sweeping && focus.x >= WeightWaveMotion.sweepTo - 0.01 { sweeping = false }
        let swelling = touching || sweeping
        let total = Double(max(lineWidth, 1))
        for i in springs.indices {
            if swelling {
                let centre = Double(centres[i] ?? 0) / total
                let d = (centre - focus.x) / WeightWaveMotion.spread
                springs[i].t = WeightWaveMotion.rest + (WeightWaveMotion.bold - WeightWaveMotion.rest) * exp(-d * d)
            } else {
                springs[i].t = WeightWaveMotion.rest
            }
            springs[i].step(dt)
        }
    }

    private func render() {
        publish()
        if !isMoving {
            for i in springs.indices { springs[i].snap(WeightWaveMotion.rest) }
            publish()
            clock.stop()
        }
    }

    private func publish() {
        if buffer.count != springs.count { buffer = Array(repeating: WeightWaveMotion.rest, count: springs.count) }
        for i in springs.indices { buffer[i] = motionClamp(springs[i].x, 100, 900) }
        if buffer != weights { weights = buffer }
    }
}

private struct LetterCentreKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] { [:] }
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}


// MARK: - Previews

#Preview("Weight wave") {
    VStack(alignment: .leading, spacing: Spacing.xl) {
        WeightWaveText("Today", kerning: -1)
            .foregroundStyle(Color.labelPrimary)
        WeightWaveText("Feel the weight")
            .foregroundStyle(Color.labelPrimary)
        WeightWaveText("Static", autoplay: false)
            .foregroundStyle(Color.labelSecondary)
    }
    .padding(Spacing.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.surfaceGrouped)
}
