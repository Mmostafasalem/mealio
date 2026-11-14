import SwiftUI
import UIKit

// MARK: - Streaming Reply Text
//
// Port of designbookmark.com/motion "Streaming Reply" (streaming-reply/stream.js).
// The reply appears a word at a time: each word rises and sharpens (blur → 0) on
// its own spring. The view reports only the lines revealed so far as its height,
// so a bubble around it grows a line at a time. The backend returns the whole
// reply at once, so the pace is local: ~22 words a second, at most ~2.5 s in all.
// Tapping shows everything. VoiceOver reads the full text from the label and hears
// "Reply ready" when it lands; Reduce Motion shows it at once. Once finished it renders as plain Text.

struct StreamingReplyText: View {
    let text: String
    /// Seconds to wait before the first word (e.g. while a bubble opens).
    var delay: Double = 0
    /// Called once, when every word has landed.
    var onFinished: (() -> Void)? = nil

    @State private var engine = StreamingReplyEngine()

    init(text: String, delay: Double = 0, onFinished: (() -> Void)? = nil) {
        self.text = text
        self.delay = delay
        self.onFinished = onFinished
    }

    var body: some View {
        Group {
            if engine.finished {
                Text(verbatim: text)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ReplyFlowLayout(revealed: engine.revealed, generation: engine.generation) {
                    Text(verbatim: "\u{00A0}").hidden()   // measures a space and a line
                    ForEach(Array(engine.words.enumerated()), id: \.offset) { _, word in
                        if let text = word.text {
                            ReplyWord(text: text, word: word)
                        } else {
                            Color.clear.frame(width: 0, height: 0)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { engine.revealAll() }
            }
        }
        .onAppear { engine.load(text, delay: delay) }
        .onDisappear { engine.pause() }
        .onChange(of: text) { _, new in engine.load(new, delay: 0) }
        .onChange(of: engine.finished) { _, done in
            guard done else { return }
            onFinished?()
            // The full text is read from the label (this view's, or the bubble around it);
            // announcing it as well would read it twice. Just say it has landed.
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: String(localized: "Reply ready"))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// One word. It observes only its own progress, so a frame re-renders just the words still moving.
private struct ReplyWord: View {
    let text: String
    let word: StreamingReplyEngine.Word

    var body: some View {
        let p = word.progress
        let v = motionClamp(p, 0, 1)
        let base = Text(verbatim: text)
            .opacity(v)
            .offset(y: (1 - p) * 6)
        if p < 0.98 {
            base.blur(radius: (1 - v) * 4)
        } else {
            base   // landed: no blur pass
        }
    }
}

// MARK: - Flow layout: words wrap like Text; the reported height stops at the last revealed word

private struct ReplyFlowLayout: Layout {
    /// How many tokens (words and line breaks) are showing.
    var revealed: Int
    /// Changes when the words change, so cached sizes are thrown away.
    var generation: Int

    struct Arranged {
        var frames: [CGRect] = []   // one per token (subview 1…)
        var width: CGFloat = 0
        var lineHeight: CGFloat = 0
    }

    /// Words are measured once per proposal width (and font, via the space's size),
    /// so the per-frame passes while words land only re-read the arrangement.
    struct Cache {
        var generation = -1
        var count = -1
        var maxWidth: CGFloat = -1
        var unit: CGSize = .zero
        var arranged = Arranged()
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        // Keep the measurements: `arranged(_:_:_:)` checks whether they still apply.
        if cache.generation != generation || cache.count != subviews.count { cache = Cache() }
    }

    private func arranged(_ maxWidth: CGFloat, _ subviews: Subviews, _ cache: inout Cache) -> Arranged {
        guard let measure = subviews.first else { return Arranged() }
        let unit = measure.sizeThatFits(.unspecified)   // one cheap measure; changes with Dynamic Type
        if cache.generation == generation, cache.count == subviews.count,
           cache.maxWidth == maxWidth, cache.unit == unit {
            return cache.arranged
        }
        var out = Arranged()
        let space = unit.width
        let lineH = unit.height
        out.lineHeight = lineH
        var x: CGFloat = 0, y: CGFloat = 0, lineMax = lineH
        for sub in subviews.dropFirst() {
            let s = sub.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if s == .zero {
                // a line break: the next word starts a new line (an empty line if there were no words)
                out.frames.append(CGRect(x: 0, y: y, width: 0, height: lineH))
                y += lineMax; x = 0; lineMax = lineH
                continue
            }
            if x > 0 && x + s.width > maxWidth {
                y += lineMax; x = 0; lineMax = lineH
            }
            let w = min(s.width, maxWidth)
            out.frames.append(CGRect(x: x, y: y, width: w, height: s.height))
            out.width = max(out.width, x + w)
            lineMax = max(lineMax, s.height)
            x += w + space
        }
        cache = Cache(generation: generation, count: subviews.count, maxWidth: maxWidth, unit: unit, arranged: out)
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let a = arranged(proposal.width ?? .infinity, subviews, &cache)
        let shown = a.frames.prefix(max(revealed, 0))
        let bottom = shown.map(\.maxY).max() ?? 0
        return CGSize(width: a.width, height: max(bottom, a.lineHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let a = arranged(proposal.width ?? bounds.width, subviews, &cache)
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
        for (i, sub) in subviews.dropFirst().enumerated() where i < a.frames.count {
            let f = a.frames[i]
            sub.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), anchor: .topLeading,
                      proposal: ProposedViewSize(width: f.width, height: nil))
        }
    }
}

// MARK: - Engine

@MainActor
@Observable
final class StreamingReplyEngine {
    /// One token's published state. Each word view observes only its own.
    @MainActor
    @Observable
    final class Word {
        /// The word, or nil for a line break.
        let text: String?
        /// Spring value: 0 hidden, 1 landed.
        fileprivate(set) var progress: Double = 0
        init(_ text: String?) { self.text = text }
    }

    private(set) var words: [Word] = []
    private(set) var revealed = 0
    private(set) var finished = false
    /// Bumped on every load, so the layout drops its cached measurements.
    private(set) var generation = 0

    static let wordsPerSecond: Double = 22
    static let maxDuration: Double = 2.5
    /// Changes smaller than this are not published (invisible in opacity, offset or blur).
    private static let publishStep: Double = 0.002

    @ObservationIgnored private var springs: [MotionSpring] = []
    @ObservationIgnored private var interval: Double = 1 / StreamingReplyEngine.wordsPerSecond
    @ObservationIgnored private var elapsed: Double = 0
    @ObservationIgnored private var loadedText: String?
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func load(_ text: String, delay: Double) {
        guard text != loadedText else { resume(); return }
        loadedText = text
        var t: [String?] = []
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        for (n, line) in lines.enumerated() {
            if n > 0 { t.append(nil) }
            t.append(contentsOf: line.split(separator: " ", omittingEmptySubsequences: true).map { String($0) })
        }
        generation += 1
        words = t.map { Word($0) }
        springs = t.map { _ in MotionSpring(0, 340, 26) }   // stream.js word spring
        interval = min(1 / Self.wordsPerSecond, Self.maxDuration / Double(max(t.count, 1)))
        elapsed = -delay
        revealed = 0
        finished = false
        if MotionSettings.reduceMotion || t.isEmpty { revealAll(); return }
        clock.start()
    }

    func revealAll() {
        guard !finished else { return }
        clock.stop()
        for i in springs.indices { springs[i].snap(1) }
        for w in words where w.progress != 1 { w.progress = 1 }
        revealed = words.count
        finished = true
    }

    func pause() { clock.stop() }

    private func resume() { if !finished { clock.start() } }

    private func frame(_ dt: Double) {
        elapsed += dt
        if elapsed >= 0 {
            let due = min(words.count, Int(elapsed / interval) + 1)
            if due > revealed {
                for i in revealed..<due {
                    springs[i].t = 1
                    if words[i].text == nil { springs[i].snap(1) }
                }
                revealed = due
            }
        }
        for i in 0..<revealed { springs[i].step(dt) }
    }

    private func render() {
        var allSettled = revealed == words.count
        for i in 0..<revealed {
            let settled = springs[i].isSettled
            if !settled { allSettled = false }
            let x = settled ? springs[i].t : springs[i].x
            // Only words that visibly moved invalidate their view.
            if abs(words[i].progress - x) >= Self.publishStep || (settled && words[i].progress != x) {
                words[i].progress = x
            }
        }
        if allSettled {
            clock.stop()
            finished = true
        }
    }
}

// MARK: - Preview

#Preview("Streaming Reply") {
    @Previewable @State var run = 0
    VStack(alignment: .leading, spacing: 24) {
        StreamingReplyText(text: "Try a lentil bowl tonight: the spinach and feta in your fridge plus a 0.89 € can of lentils from Maxima. It covers about 28 g of the protein you still need today.")
            .id(run)
            .font(.subheadline)
            .foregroundStyle(Color.labelPrimary)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.trailing, 60)
        Button("Replay") { run += 1 }
            .buttonStyle(.bordered)
    }
    .padding(Spacing.lg)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Color.surfaceGrouped)
}
