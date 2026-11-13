import SwiftUI

// MARK: - Weight wave
//
// Port of designbookmark.com/motion "Weight wave" (weight-wave/wave.js).
// Each letter's weight is a spring pulled toward a bell curve around a focus
// point, so a swell of bold rolls through the word. With no finger on it the
// swell sweeps back and forth by itself.

enum WeightWaveMotion {
    static let light: Double = 300
    static let bold: Double = 820
    /// Width of the swell, as a share of the line.
    static let spread: Double = 0.13
    static let letter = MotionTokens.Preset(k: 260, c: 22)
    static let focus = MotionTokens.Preset(k: 150, c: 22)
    /// Seconds for one full sweep there and back.
    static let period: Double = 4.6
    /// Seconds after a release before the sweep resumes.
    static let resumeDelay: Double = 2
    static let reducedWeight: Double = 700
}

struct WeightWaveText: View {
    let text: String
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
                    .opacity(reduceMotion ? 1 : model.opacity(at: index))
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
                .onEnded { _ in model.release() }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
        .onAppear {
            model.configure(count: letters.count, autoplay: autoplay)
            model.visible = true
            updateRunning()
        }
        .onDisappear {
            model.visible = false
            updateRunning()
        }
        .onChange(of: scenePhase) { _, _ in updateRunning() }
        .onChange(of: reduceMotion) { _, _ in updateRunning() }
        .onChange(of: text) { _, _ in model.configure(count: letters.count, autoplay: autoplay) }
    }

    private func updateRunning() {
        model.setRunning(model.visible && scenePhase == .active && !reduceMotion)
    }
}

// MARK: - Model

@MainActor @Observable
final class WeightWaveModel {
    static let space = "weightWave"

    /// Published once per frame for SwiftUI.
    private(set) var weights: [Double] = []

    @ObservationIgnored var centres: [Int: CGFloat] = [:]
    @ObservationIgnored var lineWidth: CGFloat = 1
    @ObservationIgnored var visible = false
    @ObservationIgnored private var springs: [MotionSpring] = []
    /// Where the swell is: 0 = left end of the line, 1 = right end.
    @ObservationIgnored private var focus = MotionSpring(-0.2, WeightWaveMotion.focus)
    @ObservationIgnored private var touching = false
    @ObservationIgnored private var sweepTime: Double = 0
    @ObservationIgnored private var autoplay = true
    @ObservationIgnored private var resumeToken: Int?
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func configure(count: Int, autoplay: Bool) {
        self.autoplay = autoplay
        guard springs.count != count else { return }
        springs = (0..<count).map { _ in MotionSpring(WeightWaveMotion.light, WeightWaveMotion.letter) }
        weights = springs.map(\.x)
    }

    func weight(at index: Int) -> Double {
        index < weights.count ? weights[index] : WeightWaveMotion.light
    }

    func opacity(at index: Int) -> Double {
        let w = weight(at: index)
        let g = motionClamp((w - WeightWaveMotion.light) / (WeightWaveMotion.bold - WeightWaveMotion.light), 0, 1)
        return 0.42 + 0.58 * g
    }

    @ObservationIgnored private var wantsToRun = false
    @ObservationIgnored private var coverPoll: Timer?

    /// Runs while visible and active, and pauses while a sheet or full-screen
    /// cover hides the line (onDisappear does not fire for those).
    func setRunning(_ running: Bool) {
        wantsToRun = running
        coverPoll?.invalidate()
        coverPoll = nil
        guard running else { clock.stop(); return }
        applyCover()
        let poll = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyCover() }
        }
        RunLoop.main.add(poll, forMode: .common)
        coverPoll = poll
    }

    private func applyCover() {
        guard wantsToRun else { return }
        Self.isCovered ? clock.stop() : clock.start()
    }

    private static var isCovered: Bool {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        return window?.rootViewController?.presentedViewController != nil
    }

    deinit { coverPoll?.invalidate() }

    func point(at x: CGFloat) {
        if let token = resumeToken { clock.cancel(token); resumeToken = nil }
        touching = true
        focus.t = Double(x / max(lineWidth, 1))
        if visible { clock.start() }
    }

    func release() {
        if let token = resumeToken { clock.cancel(token) }
        resumeToken = clock.after(WeightWaveMotion.resumeDelay) { [weak self] in
            guard let self else { return }
            touching = false
            sweepTime = 0
            resumeToken = nil
        }
        if !visible { clock.stop() }
    }

    private func frame(_ dt: Double) {
        if !touching && autoplay {
            sweepTime += dt
            focus.t = -0.06 + 1.12 * (0.5 - 0.5 * cos(sweepTime * .pi * 2 / WeightWaveMotion.period))
        }
        focus.step(dt)
        let total = Double(max(lineWidth, 1))
        for i in springs.indices {
            let centre = Double(centres[i] ?? 0) / total
            let d = (centre - focus.x) / WeightWaveMotion.spread
            springs[i].t = WeightWaveMotion.light + (WeightWaveMotion.bold - WeightWaveMotion.light) * exp(-d * d)
            springs[i].step(dt)
        }
    }

    private func render() {
        weights = springs.map { motionClamp($0.x, 100, 900) }
        // Without autoplay there is nothing to sweep: rest once everything has landed.
        if !autoplay && !touching && resumeToken == nil && focus.isSettled && springs.allSatisfy(\.isSettled) {
            clock.stop()
        }
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
