import SwiftUI
import AVFoundation

// MARK: - Read Along
//
// Port of designbookmark.com/motion "Read Along" (read-along/read.js), driven by
// real speech instead of the demo's timer. AVSpeechSynthesizer reads the text;
// each word it is about to say gets a pill behind it, and words already read
// turn full ink. The pill's two edges are separate springs: the one in front of
// the move is quick (520, 40), the one behind lags (210, 26), so it stretches
// as it travels and settles back to the word's width. At a line break (or a
// new paragraph) it closes up and opens again from the new word's left edge
// instead of sliding across the text. Tap a word to read from there.
// No autoplay: speech starts only from a tap.
// Reduce Motion: the pill jumps to each word and only fades, no stretch.
// VoiceOver: each paragraph is one static text element (with a "Read aloud from
// here" action); the speaker uses VoiceOver's voice settings and the highlight
// is hidden, so nothing on screen competes with VoiceOver's own cursor.

// MARK: - Speaker

@MainActor
@Observable
final class ReadAlongSpeaker {
    struct Word: Equatable {
        let text: String
        /// UTF-16 range in its paragraph (speech ranges are NSRange).
        let start: Int
        let end: Int
    }

    struct Position: Equatable, Comparable {
        let paragraph: Int
        let word: Int
        static func < (a: Position, b: Position) -> Bool {
            (a.paragraph, a.word) < (b.paragraph, b.word)
        }
    }

    private(set) var paragraphs: [String] = []
    private(set) var words: [[Word]] = []
    /// True from the first tap until speech finishes or is stopped.
    private(set) var isSpeaking = false
    /// The word being said.
    private(set) var current: Position?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let delegate = Delegate()
    /// Utterance → (paragraph, UTF-16 offset of the utterance in the paragraph).
    @ObservationIgnored private var spans: [ObjectIdentifier: (paragraph: Int, base: Int)] = [:]
    @ObservationIgnored private var utterances: [AVSpeechUtterance] = []

    init() {
        synthesizer.delegate = delegate
        delegate.owner = self
    }

    func load(_ paragraphs: [String]) {
        guard paragraphs != self.paragraphs else { return }
        stop()
        self.paragraphs = paragraphs
        words = paragraphs.map(Self.tokenize)
    }

    /// Whether the word at `position` has been read already (while speaking).
    func isRead(_ position: Position) -> Bool {
        guard isSpeaking, let current else { return false }
        return position < current
    }

    /// Speaks from a word (default: the start) to the end of the last paragraph.
    /// `language`: the app language code, "en" or "lt".
    func start(from position: Position = Position(paragraph: 0, word: 0), language: String) {
        guard position.paragraph < words.count else { return }
        synthesizer.stopSpeaking(at: .immediate)
        spans = [:]
        utterances = []

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        let voice = AVSpeechSynthesisVoice(language: language == "lt" ? "lt-LT" : "en-US")
        let voiceOver = UIAccessibility.isVoiceOverRunning
        for p in position.paragraph..<paragraphs.count {
            let text = paragraphs[p]
            let firstWord = p == position.paragraph ? position.word : 0
            guard firstWord < words[p].count else { continue }
            let base = words[p][firstWord].start
            let slice = String(text[String.Index(utf16Offset: base, in: text)...])
            guard !slice.isEmpty else { continue }
            let u = AVSpeechUtterance(string: slice)
            u.voice = voice
            u.postUtteranceDelay = 0.3
            u.prefersAssistiveTechnologySettings = voiceOver
            spans[ObjectIdentifier(u)] = (p, base)
            utterances.append(u)
        }
        guard !utterances.isEmpty else { return }
        isSpeaking = true
        current = position
        utterances.forEach(synthesizer.speak)
    }

    func stop() {
        guard isSpeaking || synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    // MARK: Delegate events

    fileprivate func willSpeak(_ id: ObjectIdentifier, _ range: NSRange) {
        guard isSpeaking, let span = spans[id], span.paragraph < words.count else { return }
        let at = span.base + range.location
        let list = words[span.paragraph]
        // The word that contains the range start, or the last one before it.
        let index = list.lastIndex(where: { $0.start <= at }) ?? 0
        let next = Position(paragraph: span.paragraph, word: index)
        if next != current { current = next }
    }

    fileprivate func didFinish(_ id: ObjectIdentifier) {
        guard isSpeaking, let last = utterances.last, ObjectIdentifier(last) == id else { return }
        finish()
    }

    private func finish() {
        isSpeaking = false
        current = nil
        spans = [:]
        utterances = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    static func tokenize(_ text: String) -> [Word] {
        var out: [Word] = []
        var offset = 0
        var start: Int?
        var buffer = ""
        for ch in text {
            let n = String(ch).utf16.count
            if ch.isWhitespace {
                if let s = start { out.append(Word(text: buffer, start: s, end: offset)); start = nil; buffer = "" }
            } else {
                if start == nil { start = offset }
                buffer.append(ch)
            }
            offset += n
        }
        if let s = start { out.append(Word(text: buffer, start: s, end: offset)) }
        return out
    }

    private final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
        @MainActor weak var owner: ReadAlongSpeaker?

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                           willSpeakRangeOfSpeechString characterRange: NSRange,
                                           utterance: AVSpeechUtterance) {
            let id = ObjectIdentifier(utterance)
            Task { @MainActor [weak self] in self?.owner?.willSpeak(id, characterRange) }
        }

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            let id = ObjectIdentifier(utterance)
            Task { @MainActor [weak self] in self?.owner?.didFinish(id) }
        }
    }
}

// MARK: - Text

/// One paragraph of a `ReadAlongSpeaker`, laid out word by word with the pill.
struct ReadAlongText: View {
    let speaker: ReadAlongSpeaker
    let paragraph: Int
    /// The paragraph's text; shown as-is until the speaker has loaded it.
    let text: String
    /// App language code for speech ("en" / "lt").
    var language: String = "en"
    var font: Font = .body

    @ScaledMetric(relativeTo: .body) private var space: CGFloat = 4.5
    @ScaledMetric(relativeTo: .body) private var lineGap: CGFloat = 3
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private var words: [ReadAlongSpeaker.Word] {
        if paragraph < speaker.paragraphs.count, speaker.paragraphs[paragraph] == text {
            return speaker.words[paragraph]
        }
        return ReadAlongSpeaker.tokenize(text)
    }

    private var currentWord: Int? {
        guard !voiceOver, speaker.isSpeaking, let c = speaker.current, c.paragraph == paragraph else { return nil }
        return c.word
    }

    var body: some View {
        ReadAlongFlow(spacing: space, lineSpacing: lineGap) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                Text(word.text)
                    .font(font)
                    .foregroundStyle(color(i))
                    .animation(.easeOut(duration: 0.18), value: color(i))
                    .anchorPreference(key: ReadAlongWordAnchors.self, value: .bounds) { [i: $0] }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        speaker.start(from: .init(paragraph: paragraph, word: i), language: language)
                    }
            }
        }
        .backgroundPreferenceValue(ReadAlongWordAnchors.self) { anchors in
            GeometryReader { g in
                ReadAlongPill(target: currentWord.flatMap { anchors[$0] }.map { g[$0] })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityAction(named: "Read aloud from here") {
            speaker.start(from: .init(paragraph: paragraph, word: 0), language: language)
        }
    }

    private func color(_ i: Int) -> Color {
        guard speaker.isSpeaking, !voiceOver else { return .labelPrimary }
        if i == currentWord { return .onAccent }
        return speaker.isRead(.init(paragraph: paragraph, word: i)) ? .labelPrimary : .labelSecondary
    }
}

private struct ReadAlongWordAnchors: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Words left to right, wrapping like text.
private struct ReadAlongFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(maxWidth: maxWidth, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in row.items {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [(Int, CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, s) in subviews.enumerated() {
            var size = s.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = s.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if needed > maxWidth, !row.items.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((i, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Pill

private struct ReadAlongPill: View {
    let target: CGRect?
    @State private var model = ReadAlongPillModel()

    var body: some View {
        RoundedRectangle(cornerRadius: model.height * 0.26, style: .continuous)
            .fill(Color.progress)
            .frame(width: max(0, model.right - model.left), height: model.height)
            .offset(x: model.left, y: model.top)
            .opacity(model.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transaction { $0.animation = nil }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { model.update(target) }
            .onChange(of: target) { _, t in model.update(t) }
            .onDisappear { model.stop() }
    }
}

@MainActor
@Observable
final class ReadAlongPillModel {
    private(set) var left: Double = 0
    private(set) var right: Double = 0
    private(set) var top: Double = 0
    private(set) var height: Double = 0
    private(set) var opacity: Double = 0

    @ObservationIgnored private var l = MotionSpring(0, 520, 40)
    @ObservationIgnored private var r = MotionSpring(0, 520, 40)
    @ObservationIgnored private var y = MotionSpring(0, 600, 48)
    @ObservationIgnored private var o = MotionSpring(0, 300, 30)
    @ObservationIgnored private var h: Double = 0
    @ObservationIgnored private var lineTop: Double?
    @ObservationIgnored private let clock = MotionClock()

    static let front = MotionTokens.Preset(k: 520, c: 40)
    static let back = MotionTokens.Preset(k: 210, c: 26)

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func update(_ target: CGRect?) {
        guard let t = target else {
            o.t = 0
            lineTop = nil
            clock.start()
            return
        }
        // Reach a little past each side of the word, and a touch above and below.
        let pad = t.height * 0.14
        let bl = t.minX - pad, br = t.maxX + pad, bt = t.minY - 1
        h = t.height + 2
        o.t = 1
        if MotionSettings.reduceMotion {
            // No stretch or slide: the pill is simply on the word.
            l.snap(bl); r.snap(br); y.snap(bt)
        } else {
            if lineTop == nil || abs(bt - (lineTop ?? 0)) > 2 || o.x < 0.05 {
                // New line (or first word): open from the word's left edge, no slide.
                l.snap(bl); r.snap(bl); y.snap(bt)
            }
            let forward = bl >= l.t
            if forward { r.tune(Self.front); l.tune(Self.back) } else { l.tune(Self.front); r.tune(Self.back) }
            l.t = bl; r.t = br; y.t = bt
        }
        lineTop = bt
        clock.start()
    }

    func stop() { clock.stop() }

    private func frame(_ dt: Double) {
        l.step(dt); r.step(dt); y.step(dt); o.step(dt)
    }

    private func render() {
        left = l.x; right = r.x; top = y.x; height = h
        opacity = motionClamp(o.x, 0, 1)
        if clock.isRunning, o.isSettled, l.isSettled(within: MotionSpring.points),
           r.isSettled(within: MotionSpring.points), y.isSettled(within: MotionSpring.points) {
            l.snap(l.t); r.snap(r.t); y.snap(y.t); o.snap(o.t)
            left = l.x; right = r.x; top = y.x; opacity = o.x
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Read Along") {
    @Previewable @State var speaker = ReadAlongSpeaker()
    let steps = [
        "Rinse the buckwheat and simmer it in salted water for 15 minutes.",
        "Slice the chicken, season it and fry for 6 minutes on each side.",
        "Serve with cucumber salad and a spoon of sour cream.",
    ]
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Button(speaker.isSpeaking ? "Stop" : "Read steps aloud",
                   systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2.fill") {
                if speaker.isSpeaking { speaker.stop() } else { speaker.start(language: "en") }
            }
            .buttonStyle(.bordered)
            ForEach(steps.indices, id: \.self) { i in
                ReadAlongText(speaker: speaker, paragraph: i, text: steps[i])
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(Spacing.lg)
    }
    .background(Color.surfaceGrouped)
    .onAppear { speaker.load(steps) }
}
